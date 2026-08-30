with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.UTF_Encoding;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;

with AWS.Client;
with AWS.Headers;
with AWS.Messages;
with AWS.Net.SSL;
with AWS.Response;
with GNATCOLL.JSON;

with Adacord.Events;

package body Adacord.REST is

   use Ada.Strings.Unbounded;
   use type AWS.Messages.Status_Code;
   use type GNATCOLL.JSON.JSON_Value_Type;

   Max_Attempts : constant Positive := 3;
   HTTP_Timeout : constant Duration := 30.0;

   type Request_Method is (Get_Request, Post_Request);

   procedure Configure_TLS (API_Base : String);

   procedure Ensure_Initialized (Self : Client);

   function Normalize_API_Base (Value : String) return String;

   function Character_Count
     (Value   : String;
      Context : String) return Natural;

   function Parse_JSON
     (Response_Text : String;
      Context : String) return GNATCOLL.JSON.JSON_Value;

   function Required_Field
     (Value         : GNATCOLL.JSON.JSON_Value;
      Name          : String;
      Expected_Kind : GNATCOLL.JSON.JSON_Value_Type)
      return GNATCOLL.JSON.JSON_Value;

   function Required_String
     (Value : GNATCOLL.JSON.JSON_Value;
      Name  : String) return String;

   function Required_Integer
     (Value : GNATCOLL.JSON.JSON_Value;
      Name  : String) return Long_Long_Integer;

   function As_Natural
     (Value : Long_Long_Integer;
      Name  : String) return Natural;

   function Retry_Delay (Response : AWS.Response.Data) return Duration;

   function Execute_Request
     (Self          : Client;
      Method        : Request_Method;
      URL           : String;
      Payload       : String := "";
      Authenticated : Boolean := True) return AWS.Response.Data;

   function Request_With_Retry
     (Self          : Client;
      Method        : Request_Method;
      URL           : String;
      Payload       : String := "";
      Authenticated : Boolean := True) return AWS.Response.Data;

   -------------------
   -- Configure_TLS --
   -------------------

   procedure Configure_TLS (API_Base : String) is
      use Ada.Environment_Variables;

      function Existing_File (Path : String) return Boolean is
        (Path'Length > 0 and then Ada.Directories.Exists (Path));

      function Environment_File (Name : String) return String is
        (if Exists (Name) and then Existing_File (Value (Name))
         then Value (Name)
         else "");

      function Trusted_CA return String is
         Adacord_CA : constant String :=
           Environment_File ("ADACORD_CA_BUNDLE");
         OpenSSL_CA : constant String := Environment_File ("SSL_CERT_FILE");
      begin
         if Adacord_CA'Length > 0 then
            return Adacord_CA;
         elsif OpenSSL_CA'Length > 0 then
            return OpenSSL_CA;
         end if;

         declare
            Local_Alire_CA : constant String :=
              ".alire-msys2/usr/ssl/certs/ca-bundle.crt";
         begin
            if Existing_File (Local_Alire_CA) then
               return Local_Alire_CA;
            end if;
         end;

         if Exists ("USERPROFILE") then
            declare
               Global_Alire_CA : constant String :=
                 Value ("USERPROFILE")
                 & "/AppData/Local/alire/cache/msys64/usr/ssl/certs/"
                 & "ca-bundle.crt";
            begin
               if Existing_File (Global_Alire_CA) then
                  return Global_Alire_CA;
               end if;
            end;
         end if;

         if Existing_File ("/etc/ssl/certs/ca-certificates.crt") then
            return "/etc/ssl/certs/ca-certificates.crt";
         elsif Existing_File ("/etc/pki/tls/certs/ca-bundle.crt") then
            return "/etc/pki/tls/certs/ca-bundle.crt";
         elsif Existing_File ("/etc/ssl/cert.pem") then
            return "/etc/ssl/cert.pem";
         else
            return "";
         end if;
      end Trusted_CA;

      Is_HTTPS : constant Boolean :=
        API_Base'Length >= 8
        and then Ada.Characters.Handling.To_Lower
          (API_Base (API_Base'First .. API_Base'First + 7)) = "https://";
   begin
      if not Is_HTTPS then
         return;
      end if;

      if not AWS.Net.SSL.Is_Supported then
         raise Adacord.Configuration_Error with
           "HTTPS/TLS support is unavailable; build Adacord with Alire";
      end if;

      declare
         CA_File : constant String := Trusted_CA;
      begin
         if CA_File'Length = 0 then
            raise Adacord.Configuration_Error with
              "no trusted CA bundle was found; set ADACORD_CA_BUNDLE";
         end if;

         AWS.Net.SSL.Initialize_Default_Config
           (Server_Certificate  => "",
            Server_Key          => "",
            Client_Certificate  => "",
            Trusted_CA_Filename => CA_File);
      exception
         when Adacord.Configuration_Error =>
            raise;
         when others =>
            raise Adacord.Configuration_Error with
              "TLS initialization failed; check ADACORD_CA_BUNDLE";
      end;
   end Configure_TLS;

   ------------------------
   -- Ensure_Initialized --
   ------------------------

   procedure Ensure_Initialized (Self : Client) is
   begin
      if not Self.Initialized then
         raise Adacord.Configuration_Error with
           "the Discord REST client is not initialized";
      end if;
   end Ensure_Initialized;

   ------------------------
   -- Normalize_API_Base --
   ------------------------

   function Normalize_API_Base (Value : String) return String is
      Last : Integer := Value'Last;
   begin
      while Last >= Value'First and then Value (Last) = '/' loop
         Last := Last - 1;
      end loop;

      if Last < Value'First then
         return "";
      else
         return Value (Value'First .. Last);
      end if;
   end Normalize_API_Base;

   ---------------------
   -- Character_Count --
   ---------------------

   function Character_Count
     (Value   : String;
      Context : String) return Natural is
   begin
      return
        Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Value)'Length;
   exception
      when Ada.Strings.UTF_Encoding.Encoding_Error =>
         raise Adacord.Configuration_Error with
           Context & " must be valid UTF-8";
   end Character_Count;

   ----------------
   -- Parse_JSON --
   ----------------

   function Parse_JSON
     (Response_Text : String;
      Context : String) return GNATCOLL.JSON.JSON_Value
   is
      Parsed : constant GNATCOLL.JSON.Read_Result :=
        GNATCOLL.JSON.Read (Response_Text);
   begin
      if not Parsed.Success then
         raise Adacord.Protocol_Error with
           "invalid JSON in Discord " & Context & " response";
      end if;

      return Parsed.Value;
   end Parse_JSON;

   --------------------
   -- Required_Field --
   --------------------

   function Required_Field
     (Value         : GNATCOLL.JSON.JSON_Value;
      Name          : String;
      Expected_Kind : GNATCOLL.JSON.JSON_Value_Type)
      return GNATCOLL.JSON.JSON_Value
   is
   begin
      if GNATCOLL.JSON.Kind (Value) /= GNATCOLL.JSON.JSON_Object_Type
        or else not GNATCOLL.JSON.Has_Field (Value, Name)
      then
         raise Adacord.Protocol_Error with
           "missing Discord JSON field: " & Name;
      end if;

      declare
         Result : constant GNATCOLL.JSON.JSON_Value :=
           GNATCOLL.JSON.Get (Value, Name);
      begin
         if GNATCOLL.JSON.Kind (Result) /= Expected_Kind then
            raise Adacord.Protocol_Error with
              "invalid type for Discord JSON field: " & Name;
         end if;

         return Result;
      end;
   end Required_Field;

   ---------------------
   -- Required_String --
   ---------------------

   function Required_String
     (Value : GNATCOLL.JSON.JSON_Value;
      Name  : String) return String
   is
      Field : constant GNATCOLL.JSON.JSON_Value :=
        Required_Field (Value, Name, GNATCOLL.JSON.JSON_String_Type);
   begin
      return GNATCOLL.JSON.Get (Field);
   end Required_String;

   ----------------------
   -- Required_Integer --
   ----------------------

   function Required_Integer
     (Value : GNATCOLL.JSON.JSON_Value;
      Name  : String) return Long_Long_Integer
   is
      Field : constant GNATCOLL.JSON.JSON_Value :=
        Required_Field (Value, Name, GNATCOLL.JSON.JSON_Int_Type);
   begin
      return GNATCOLL.JSON.Get (Field);
   end Required_Integer;

   ----------------
   -- As_Natural --
   ----------------

   function As_Natural
     (Value : Long_Long_Integer;
      Name  : String) return Natural
   is
   begin
      if Value < 0
        or else Value > Long_Long_Integer (Natural'Last)
      then
         raise Adacord.Protocol_Error with
           "Discord JSON field is outside Natural range: " & Name;
      end if;

      return Natural (Value);
   end As_Natural;

   -----------------
   -- Retry_Delay --
   -----------------

   function Retry_Delay (Response : AWS.Response.Data) return Duration is
      Response_Text : constant String :=
        AWS.Response.Message_Body (Response);
      Parsed : constant GNATCOLL.JSON.Read_Result :=
        GNATCOLL.JSON.Read (Response_Text);
      Seconds : Long_Float;
   begin
      if not Parsed.Success
        or else GNATCOLL.JSON.Kind (Parsed.Value) /=
          GNATCOLL.JSON.JSON_Object_Type
        or else not GNATCOLL.JSON.Has_Field
          (Parsed.Value, "retry_after")
      then
         raise Adacord.Rate_Limit_Error with
           "Discord rate limit response has no valid retry_after";
      end if;

      declare
         Value : constant GNATCOLL.JSON.JSON_Value :=
           GNATCOLL.JSON.Get (Parsed.Value, "retry_after");
      begin
         case GNATCOLL.JSON.Kind (Value) is
            when GNATCOLL.JSON.JSON_Int_Type =>
               declare
                  Integer_Seconds : constant Long_Long_Integer :=
                    GNATCOLL.JSON.Get (Value);
               begin
                  Seconds := Long_Float (Integer_Seconds);
               end;

            when GNATCOLL.JSON.JSON_Float_Type =>
               Seconds := GNATCOLL.JSON.Get_Long_Float (Value);

            when others =>
               raise Adacord.Rate_Limit_Error with
                 "Discord retry_after has an invalid type";
         end case;
      end;

      if Seconds < 0.0
        or else Seconds > Long_Float (Duration'Last)
      then
         raise Adacord.Rate_Limit_Error with
           "Discord retry_after is outside Duration range";
      end if;

      return Duration (Seconds);
   end Retry_Delay;

   ---------------------
   -- Execute_Request --
   ---------------------

   function Execute_Request
     (Self          : Client;
      Method        : Request_Method;
      URL           : String;
      Payload       : String := "";
      Authenticated : Boolean := True) return AWS.Response.Data
   is
      Headers : AWS.Client.Header_List := AWS.Client.Empty_Header_List;
   begin
      if Authenticated then
         AWS.Headers.Add
           (Headers,
            Name  => "Authorization",
            Value => "Bot " & To_String (Self.Token));
      end if;

      case Method is
         when Get_Request =>
            return AWS.Client.Get
               (URL                => URL,
               Timeouts           =>
                 AWS.Client.Timeouts (Each => HTTP_Timeout),
               Follow_Redirection => False,
               Headers            => Headers,
               User_Agent         => To_String (Self.User_Agent));

         when Post_Request =>
            return AWS.Client.Post
              (URL          => URL,
               Data         => Payload,
               Content_Type => "application/json",
               Timeouts     =>
                 AWS.Client.Timeouts (Each => HTTP_Timeout),
               Headers      => Headers,
               User_Agent   => To_String (Self.User_Agent));
      end case;
   exception
      when others =>
         --  Keep transport errors generic: exception text from a lower layer
         --  must never accidentally expose the Authorization header.
         raise Adacord.Transport_Error with
           "Discord HTTP transport request failed";
   end Execute_Request;

   ------------------------
   -- Request_With_Retry --
   ------------------------

   function Request_With_Retry
     (Self          : Client;
      Method        : Request_Method;
      URL           : String;
      Payload       : String := "";
      Authenticated : Boolean := True) return AWS.Response.Data
   is
   begin
      for Attempt in 1 .. Max_Attempts loop
         declare
            Response : constant AWS.Response.Data :=
              Execute_Request
                (Self, Method, URL, Payload, Authenticated);
            Status   : constant AWS.Messages.Status_Code :=
              AWS.Response.Status_Code (Response);
         begin
            if Status in AWS.Messages.Success then
               return Response;

            elsif Status in AWS.Messages.S401 | AWS.Messages.S403 then
               raise Adacord.Authentication_Error with
                 "Discord rejected bot authentication or permissions (HTTP "
                 & AWS.Messages.Image (Status) & ")";

            elsif Status = AWS.Messages.S429 then
               if Attempt = Max_Attempts then
                  raise Adacord.Rate_Limit_Error with
                    "Discord rate limit persisted after 3 attempts";
               end if;

               delay Retry_Delay (Response);

            else
               raise Adacord.Protocol_Error with
                 "unexpected Discord HTTP status "
                 & AWS.Messages.Image (Status);
            end if;
         end;
      end loop;

      raise Adacord.Protocol_Error with
        "Discord HTTP retry loop ended unexpectedly";
   end Request_With_Retry;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (Self       : in out Client;
      Token      : String;
      API_Base   : String := "https://discord.com/api/v10";
      User_Agent : String :=
        "DiscordBot (https://github.com/adacord/adacord, 0.1.0)")
   is
      Normalized_Base : constant String := Normalize_API_Base (API_Base);
   begin
      if Token'Length = 0 then
         raise Adacord.Configuration_Error with
           "the Discord bot token must not be empty";
      end if;

      if Normalized_Base'Length = 0 then
         raise Adacord.Configuration_Error with
           "the Discord API base URL must not be empty";
      end if;

      if User_Agent'Length = 0 then
         raise Adacord.Configuration_Error with
           "the Discord HTTP User-Agent must not be empty";
      end if;

      Configure_TLS (Normalized_Base);

      Self.Token := To_Unbounded_String (Token);
      Self.API_Base := To_Unbounded_String (Normalized_Base);
      Self.User_Agent := To_Unbounded_String (User_Agent);
      Self.Initialized := True;
   end Initialize;

   ----------------------
   -- Get_Gateway_Info --
   ----------------------

   function Get_Gateway_Info (Self : Client) return Gateway_Info is
   begin
      Ensure_Initialized (Self);

      declare
         Response : constant AWS.Response.Data :=
           Request_With_Retry
             (Self,
              Get_Request,
              To_String (Self.API_Base) & "/gateway/bot");
         Response_Text : constant String :=
           AWS.Response.Message_Body (Response);
         Root : constant GNATCOLL.JSON.JSON_Value :=
           Parse_JSON (Response_Text, "gateway");
      begin
         if GNATCOLL.JSON.Kind (Root) /= GNATCOLL.JSON.JSON_Object_Type then
            raise Adacord.Protocol_Error with
              "Discord gateway response is not a JSON object";
         end if;

         declare
            Session_Limit : constant GNATCOLL.JSON.JSON_Value :=
              Required_Field
                (Root,
                 "session_start_limit",
                 GNATCOLL.JSON.JSON_Object_Type);
            Shards : constant Long_Long_Integer :=
              Required_Integer (Root, "shards");
         begin
            if Shards <= 0
              or else Shards > Long_Long_Integer (Positive'Last)
            then
               raise Adacord.Protocol_Error with
                 "Discord shards is outside Positive range";
            end if;

            return
              (URL =>
                 To_Unbounded_String (Required_String (Root, "url")),
               Recommended_Shards => Positive (Shards),
               Remaining_Sessions =>
                 As_Natural
                   (Required_Integer (Session_Limit, "remaining"),
                    "remaining"),
               Reset_After_Milliseconds =>
                 As_Natural
                   (Required_Integer (Session_Limit, "reset_after"),
                    "reset_after"),
               Max_Concurrency =>
                 As_Natural
                   (Required_Integer (Session_Limit, "max_concurrency"),
                    "max_concurrency"));
         end;
      end;
   end Get_Gateway_Info;

   ------------------
   -- Send_Message --
   ------------------

   function Send_Message
     (Self       : Client;
      Channel_ID : Adacord.Types.Snowflake;
      Content    : String) return Adacord.Types.Message
   is
   begin
      Ensure_Initialized (Self);

      if Content'Length = 0 then
         raise Adacord.Configuration_Error with
           "Discord message content must not be empty";
      elsif Content'Length > 2_000 then
         raise Adacord.Configuration_Error with
           "Discord message content exceeds 2000 characters";
      end if;

      declare
         Payload          : constant GNATCOLL.JSON.JSON_Value :=
           GNATCOLL.JSON.Create_Object;
         Allowed_Mentions : constant GNATCOLL.JSON.JSON_Value :=
           GNATCOLL.JSON.Create_Object;
      begin
         GNATCOLL.JSON.Set_Field
           (Allowed_Mentions, "parse", GNATCOLL.JSON.Empty_Array);
         GNATCOLL.JSON.Set_Field (Payload, "content", Content);
         GNATCOLL.JSON.Set_Field
           (Payload, "allowed_mentions", Allowed_Mentions);

         declare
            Response : constant AWS.Response.Data :=
              Request_With_Retry
                (Self,
                 Post_Request,
                 To_String (Self.API_Base)
                 & "/channels/"
                 & Adacord.Types.Image (Channel_ID)
                 & "/messages",
                 GNATCOLL.JSON.Write (Payload));
            Response_Text : constant String :=
              AWS.Response.Message_Body (Response);
            Message_JSON : constant GNATCOLL.JSON.JSON_Value :=
              Parse_JSON (Response_Text, "message");
         begin
            return Adacord.Events.Parse_Message (Message_JSON);
         end;
      end;
   end Send_Message;

   -----------------------------
   -- Register_Global_Command --
   -----------------------------

   function Register_Global_Command
     (Self           : Client;
      Application_ID : Adacord.Types.Snowflake;
      Name           : String;
      Description    : String) return Adacord.Types.Application_Command
   is
      Name_Length : constant Natural :=
        Character_Count (Name, "Discord command name");
      Description_Length : constant Natural :=
        Character_Count (Description, "Discord command description");
   begin
      Ensure_Initialized (Self);

      if Name_Length = 0 then
         raise Adacord.Configuration_Error with
           "Discord command name must not be empty";
      elsif Name_Length > 32 then
         raise Adacord.Configuration_Error with
           "Discord command name exceeds 32 characters";
      elsif Description_Length = 0 then
         raise Adacord.Configuration_Error with
           "Discord command description must not be empty";
      elsif Description_Length > 100 then
         raise Adacord.Configuration_Error with
           "Discord command description exceeds 100 characters";
      end if;

      declare
         Payload : constant GNATCOLL.JSON.JSON_Value :=
           GNATCOLL.JSON.Create_Object;
      begin
         GNATCOLL.JSON.Set_Field (Payload, "name", Name);
         GNATCOLL.JSON.Set_Field (Payload, "description", Description);
         GNATCOLL.JSON.Set_Field (Payload, "type", Integer'(1));

         declare
            Response : constant AWS.Response.Data :=
              Request_With_Retry
                (Self,
                 Post_Request,
                 To_String (Self.API_Base)
                 & "/applications/"
                 & Adacord.Types.Image (Application_ID)
                 & "/commands",
                 GNATCOLL.JSON.Write (Payload));
            Root : constant GNATCOLL.JSON.JSON_Value :=
              Parse_JSON
                (AWS.Response.Message_Body (Response),
                 "application command");
         begin
            if GNATCOLL.JSON.Kind (Root) /=
              GNATCOLL.JSON.JSON_Object_Type
            then
               raise Adacord.Protocol_Error with
                 "Discord application command response is not an object";
            end if;

            return
              (ID             => Adacord.Types.Parse_Snowflake
                 (Required_String (Root, "id")),
               Application_ID => Adacord.Types.Parse_Snowflake
                 (Required_String (Root, "application_id")),
               Guild_ID       => (Present => False),
               Name           => To_Unbounded_String
                 (Required_String (Root, "name")),
               Description    => To_Unbounded_String
                 (Required_String (Root, "description")),
               Command_Type   => As_Natural
                 (Required_Integer (Root, "type"), "type"));
         exception
            when Adacord.Invalid_Event =>
               raise Adacord.Protocol_Error with
                 "Discord returned an invalid application command";
         end;
      end;
   end Register_Global_Command;

   ----------------------------
   -- Respond_To_Interaction --
   ----------------------------

   procedure Respond_To_Interaction
     (Self        : Client;
      Interaction : Adacord.Types.Interaction;
      Content     : String;
      Ephemeral   : Boolean := False)
   is
   begin
      Ensure_Initialized (Self);

      if Content'Length = 0 then
         raise Adacord.Configuration_Error with
           "Discord interaction response must not be empty";
      elsif Content'Length > 2_000 then
         raise Adacord.Configuration_Error with
           "Discord interaction response exceeds 2000 characters";
      end if;

      declare
         Payload          : constant GNATCOLL.JSON.JSON_Value :=
           GNATCOLL.JSON.Create_Object;
         Data             : constant GNATCOLL.JSON.JSON_Value :=
           GNATCOLL.JSON.Create_Object;
         Allowed_Mentions : constant GNATCOLL.JSON.JSON_Value :=
           GNATCOLL.JSON.Create_Object;
         Ignored          : AWS.Response.Data;
      begin
         GNATCOLL.JSON.Set_Field
           (Allowed_Mentions, "parse", GNATCOLL.JSON.Empty_Array);
         GNATCOLL.JSON.Set_Field (Data, "content", Content);
         GNATCOLL.JSON.Set_Field
           (Data, "allowed_mentions", Allowed_Mentions);

         if Ephemeral then
            GNATCOLL.JSON.Set_Field (Data, "flags", Integer'(64));
         end if;

         GNATCOLL.JSON.Set_Field (Payload, "type", Integer'(4));
         GNATCOLL.JSON.Set_Field (Payload, "data", Data);

         Ignored := Request_With_Retry
           (Self,
            Post_Request,
            To_String (Self.API_Base)
            & "/interactions/"
            & Adacord.Types.Image (Interaction.ID)
            & "/"
            & To_String (Interaction.Token)
            & "/callback",
            GNATCOLL.JSON.Write (Payload),
            Authenticated => False);
      end;
   end Respond_To_Interaction;

end Adacord.REST;
