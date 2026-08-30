with Ada.Strings.Unbounded;

package body Adacord.Events is

   package JSON renames GNATCOLL.JSON;
   package Discord_Types renames Adacord.Types;

   use type JSON.JSON_Value_Type;
   use type Discord_Types.Interaction_Kind;

   procedure Require_Object
     (Value   : JSON.JSON_Value;
      Context : String)
   is
   begin
      if JSON.Kind (Value) /= JSON.JSON_Object_Type then
         raise Adacord.Invalid_Event with Context & " must be an object";
      end if;
   end Require_Object;

   function Required_Field
     (Value         : JSON.JSON_Value;
      Name          : String;
      Expected_Kind : JSON.JSON_Value_Type;
      Context       : String) return JSON.JSON_Value
   is
      Result : JSON.JSON_Value;
   begin
      Require_Object (Value, Context);

      if not JSON.Has_Field (Value, Name) then
         raise Adacord.Invalid_Event with
           Context & "." & Name & " is required";
      end if;

      Result := JSON.Get (Value, Name);

      if JSON.Kind (Result) /= Expected_Kind then
         raise Adacord.Invalid_Event with
           Context & "." & Name & " has the wrong JSON type";
      end if;

      return Result;
   end Required_Field;

   function Required_Text
     (Value   : JSON.JSON_Value;
      Name    : String;
      Context : String) return Discord_Types.Text
   is
      Field : constant JSON.JSON_Value :=
        Required_Field
          (Value, Name, JSON.JSON_String_Type, Context);
   begin
      return JSON.Get (Field);
   end Required_Text;

   function Text_Or_Empty
     (Value   : JSON.JSON_Value;
      Name    : String;
      Context : String) return Discord_Types.Text
   is
      Field : JSON.JSON_Value;
   begin
      Require_Object (Value, Context);

      if not JSON.Has_Field (Value, Name) then
         return Ada.Strings.Unbounded.Null_Unbounded_String;
      end if;

      Field := JSON.Get (Value, Name);

      case JSON.Kind (Field) is
         when JSON.JSON_Null_Type =>
            return Ada.Strings.Unbounded.Null_Unbounded_String;
         when JSON.JSON_String_Type =>
            return JSON.Get (Field);
         when others =>
            raise Adacord.Invalid_Event with
              Context & "." & Name & " has the wrong JSON type";
      end case;
   end Text_Or_Empty;

   function Optional_Text_Field
     (Value   : JSON.JSON_Value;
      Name    : String;
      Context : String) return Discord_Types.Optional_Text
   is
      Field : JSON.JSON_Value;
   begin
      Require_Object (Value, Context);

      if not JSON.Has_Field (Value, Name) then
         return (Present => False);
      end if;

      Field := JSON.Get (Value, Name);

      case JSON.Kind (Field) is
         when JSON.JSON_Null_Type =>
            return (Present => False);
         when JSON.JSON_String_Type =>
            return (Present => True, Value => JSON.Get (Field));
         when others =>
            raise Adacord.Invalid_Event with
              Context & "." & Name & " has the wrong JSON type";
      end case;
   end Optional_Text_Field;

   function Optional_Boolean
     (Value         : JSON.JSON_Value;
      Name          : String;
      Default_Value : Boolean;
      Context       : String) return Boolean
   is
      Field : JSON.JSON_Value;
   begin
      Require_Object (Value, Context);

      if not JSON.Has_Field (Value, Name) then
         return Default_Value;
      end if;

      Field := JSON.Get (Value, Name);

      if JSON.Kind (Field) /= JSON.JSON_Boolean_Type then
         raise Adacord.Invalid_Event with
           Context & "." & Name & " has the wrong JSON type";
      end if;

      return JSON.Get (Field);
   end Optional_Boolean;

   function Required_Snowflake
     (Value   : JSON.JSON_Value;
      Name    : String;
      Context : String) return Discord_Types.Snowflake
   is
      Field : constant JSON.JSON_Value :=
        Required_Field
          (Value, Name, JSON.JSON_String_Type, Context);
      Text  : constant String := JSON.Get (Field);
   begin
      return Discord_Types.Parse_Snowflake (Text);
   exception
      when Adacord.Invalid_Event =>
         raise Adacord.Invalid_Event with
           Context & "." & Name & " is not a valid snowflake";
   end Required_Snowflake;

   function Optional_Snowflake_Field
     (Value   : JSON.JSON_Value;
      Name    : String;
      Context : String) return Discord_Types.Optional_Snowflake
   is
      Field : JSON.JSON_Value;
   begin
      Require_Object (Value, Context);

      if not JSON.Has_Field (Value, Name) then
         return (Present => False);
      end if;

      Field := JSON.Get (Value, Name);

      case JSON.Kind (Field) is
         when JSON.JSON_Null_Type =>
            return (Present => False);
         when JSON.JSON_String_Type =>
            declare
               Text : constant String := JSON.Get (Field);
            begin
               return
                 (Present => True,
                  Value   => Discord_Types.Parse_Snowflake (Text));
            exception
               when Adacord.Invalid_Event =>
                  raise Adacord.Invalid_Event with
                    Context & "." & Name
                    & " is not a valid snowflake";
            end;
         when others =>
            raise Adacord.Invalid_Event with
              Context & "." & Name & " has the wrong JSON type";
      end case;
   end Optional_Snowflake_Field;

   function Required_Natural
     (Value   : JSON.JSON_Value;
      Name    : String;
      Context : String) return Natural
   is
      Field : constant JSON.JSON_Value :=
        Required_Field (Value, Name, JSON.JSON_Int_Type, Context);
      Number : constant Long_Long_Integer := JSON.Get (Field);
   begin
      if Number < 0
        or else Number > Long_Long_Integer (Natural'Last)
      then
         raise Adacord.Invalid_Event with
           Context & "." & Name & " is outside the Natural range";
      end if;

      return Natural (Number);
   end Required_Natural;

   function Parse_User
     (Value   : JSON.JSON_Value;
      Context : String) return Discord_Types.User
   is
   begin
      Require_Object (Value, Context);

      return
        (ID            => Required_Snowflake (Value, "id", Context),
         Username      => Required_Text (Value, "username", Context),
         Discriminator => Text_Or_Empty
           (Value, "discriminator", Context),
         Global_Name   => Optional_Text_Field
           (Value, "global_name", Context),
         Avatar        => Optional_Text_Field
           (Value, "avatar", Context),
         Is_Bot        => Optional_Boolean
           (Value, "bot", False, Context),
         Is_System     => Optional_Boolean
           (Value, "system", False, Context));
   end Parse_User;

   function Parse_Guilds
     (Value : JSON.JSON_Value) return Discord_Types.Snowflake_List
   is
      Field  : constant JSON.JSON_Value :=
        Required_Field
          (Value, "guilds", JSON.JSON_Array_Type, "ready");
      Guilds : constant JSON.JSON_Array := JSON.Get (Field);
      Result : Discord_Types.Snowflake_List;
   begin
      for Index in 1 .. JSON.Length (Guilds) loop
         declare
            Guild : constant JSON.JSON_Value := JSON.Get (Guilds, Index);
         begin
            Require_Object (Guild, "ready.guilds element");
            Discord_Types.Append
              (Result,
               Required_Snowflake
                 (Guild, "id", "ready.guilds element"));
         end;
      end loop;

      return Result;
   end Parse_Guilds;

   function Parse_Ready
     (Value : JSON.JSON_Value) return Discord_Types.Ready
   is
      User_Field        : JSON.JSON_Value;
      Application_Field : JSON.JSON_Value;
   begin
      Require_Object (Value, "ready");
      User_Field := Required_Field
        (Value, "user", JSON.JSON_Object_Type, "ready");
      Application_Field := Required_Field
        (Value, "application", JSON.JSON_Object_Type, "ready");

      return
        (Version            => Required_Natural (Value, "v", "ready"),
         Current_User       => Parse_User (User_Field, "ready.user"),
         Application_ID     => Required_Snowflake
           (Application_Field, "id", "ready.application"),
         Session_ID         => Required_Text
           (Value, "session_id", "ready"),
         Resume_Gateway_URL => Required_Text
           (Value, "resume_gateway_url", "ready"),
         Guilds             => Parse_Guilds (Value));
   exception
      when Constraint_Error =>
         raise Adacord.Invalid_Event with "invalid READY event data";
   end Parse_Ready;

   function Parse_Message
     (Value : JSON.JSON_Value) return Discord_Types.Message
   is
      Author_Field : JSON.JSON_Value;
   begin
      Require_Object (Value, "message");
      Author_Field := Required_Field
        (Value, "author", JSON.JSON_Object_Type, "message");

      return
        (ID                => Required_Snowflake
           (Value, "id", "message"),
         Channel_ID        => Required_Snowflake
           (Value, "channel_id", "message"),
         Guild_ID          => Optional_Snowflake_Field
           (Value, "guild_id", "message"),
         Author            => Parse_User (Author_Field, "message.author"),
         Content           => Required_Text
           (Value, "content", "message"),
         Timestamp         => Required_Text
           (Value, "timestamp", "message"),
         Edited_Timestamp  => Optional_Text_Field
           (Value, "edited_timestamp", "message"),
         Is_TTS            => Optional_Boolean
           (Value, "tts", False, "message"),
         Mentions_Everyone => Optional_Boolean
           (Value, "mention_everyone", False, "message"),
         Is_Pinned         => Optional_Boolean
           (Value, "pinned", False, "message"));
   exception
      when Constraint_Error =>
         raise Adacord.Invalid_Event with "invalid Message object";
   end Parse_Message;

   function Parse_Message_Create
     (Value : JSON.JSON_Value) return Discord_Types.Message is
   begin
      return Parse_Message (Value);
   end Parse_Message_Create;

   ------------------------------
   -- Parse_Interaction_Create --
   ------------------------------

   function Parse_Interaction_Create
     (Value : JSON.JSON_Value) return Discord_Types.Interaction
   is
      Type_Code    : constant Natural :=
        Required_Natural (Value, "type", "interaction");
      Kind         : Discord_Types.Interaction_Kind;
      Command_ID   : Discord_Types.Optional_Snowflake :=
        (Present => False);
      Command_Name : Discord_Types.Optional_Text := (Present => False);
      Command_Type : Natural := 0;
   begin
      Require_Object (Value, "interaction");

      Kind :=
        (case Type_Code is
            when 1 => Discord_Types.Ping_Interaction,
            when 2 => Discord_Types.Application_Command_Interaction,
            when 3 => Discord_Types.Message_Component_Interaction,
            when 4 =>
              Discord_Types.Application_Command_Autocomplete_Interaction,
            when 5 => Discord_Types.Modal_Submit_Interaction,
            when others => Discord_Types.Unknown_Interaction);

      if Kind = Discord_Types.Application_Command_Interaction then
         declare
            Data : constant JSON.JSON_Value :=
              Required_Field
                (Value, "data", JSON.JSON_Object_Type, "interaction");
         begin
            Command_ID :=
              (Present => True,
               Value   => Required_Snowflake
                 (Data, "id", "interaction.data"));
            Command_Name :=
              (Present => True,
               Value   => Required_Text
                 (Data, "name", "interaction.data"));
            Command_Type :=
              Required_Natural (Data, "type", "interaction.data");
         end;
      end if;

      return
        (ID             => Required_Snowflake
           (Value, "id", "interaction"),
         Application_ID => Required_Snowflake
           (Value, "application_id", "interaction"),
         Kind           => Kind,
         Type_Code      => Type_Code,
         Token          => Required_Text (Value, "token", "interaction"),
         Version        => Required_Natural
           (Value, "version", "interaction"),
         Guild_ID       => Optional_Snowflake_Field
           (Value, "guild_id", "interaction"),
         Channel_ID     => Optional_Snowflake_Field
           (Value, "channel_id", "interaction"),
         Command_ID     => Command_ID,
         Command_Name   => Command_Name,
         Command_Type   => Command_Type);
   exception
      when Constraint_Error =>
         raise Adacord.Invalid_Event with
           "invalid INTERACTION_CREATE event data";
   end Parse_Interaction_Create;

end Adacord.Events;
