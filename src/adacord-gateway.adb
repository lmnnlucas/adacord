with Ada.Numerics.Float_Random;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with AWS.Net;
with AWS.Net.WebSocket;
with AWS.Net.WebSocket.Buffered_Client_Fix;
with GNATCOLL.JSON;

with Adacord.Events;

package body Adacord.Gateway is

   package JSON renames GNATCOLL.JSON;
   package Random renames Ada.Numerics.Float_Random;
   package Real_Time renames Ada.Real_Time;

   use Ada.Strings.Unbounded;
   use type Adacord.Intents.Intent_Set;
   use type AWS.Net.WebSocket.Kind_Type;
   use type JSON.JSON_Value_Type;
   use type Real_Time.Time;

   Gateway_Version : constant Positive := 10;
   Poll_Quantum    : constant Duration := 0.25;
   Maximum_Backoff : constant Duration := 30.0;

   type Gateway_Socket is new AWS.Net.WebSocket.Object with record
      Received_Message : Unbounded_String;
      Message_Ready    : Boolean := False;
      Closed           : Boolean := False;
      Failed           : Boolean := False;
      Close_Code       : Integer := 0;
   end record;

   overriding procedure On_Message
     (Socket  : in out Gateway_Socket;
      Message : Unbounded_String);

   overriding procedure On_Close
     (Socket  : in out Gateway_Socket;
      Message : String);

   overriding procedure On_Error
     (Socket  : in out Gateway_Socket;
      Message : String);

   function Gateway_URI (Base : String) return String;

   function Required_Field
     (Value         : JSON.JSON_Value;
      Name          : String;
      Expected_Kind : JSON.JSON_Value_Type) return JSON.JSON_Value;

   function Required_Integer
     (Value : JSON.JSON_Value;
      Name  : String) return Long_Long_Integer;

   function Required_String
     (Value : JSON.JSON_Value;
      Name  : String) return String;

   function Envelope
     (Opcode : Natural;
      Data   : JSON.JSON_Value) return String;

   function Identify_Payload
     (Token   : String;
      Intents : Adacord.Intents.Intent_Set) return String;

   function Resume_Payload
     (Token      : String;
      Session_ID : String;
      Sequence   : Long_Long_Integer) return String;

   function Heartbeat_Payload
     (Has_Sequence : Boolean;
      Sequence     : Long_Long_Integer) return String;

   function Is_Fatal_Close (Code : Integer) return Boolean;

   function Fatal_Close_Message (Code : Integer) return String;

   procedure Responsive_Delay
     (Length : Duration;
      Sink   : in out Event_Sink'Class);

   ----------------
   -- On_Message --
   ----------------

   overriding procedure On_Message
     (Socket  : in out Gateway_Socket;
      Message : Unbounded_String) is
   begin
      if Socket.Kind = AWS.Net.WebSocket.Text then
         Socket.Received_Message := Message;
         Socket.Message_Ready := True;
      else
         Socket.Failed := True;
      end if;
   end On_Message;

   --------------
   -- On_Close --
   --------------

   overriding procedure On_Close
     (Socket  : in out Gateway_Socket;
      Message : String)
   is
      pragma Unreferenced (Message);
   begin
      Socket.Close_Code := Socket.Errno;
      Socket.Closed := True;
   end On_Close;

   --------------
   -- On_Error --
   --------------

   overriding procedure On_Error
     (Socket  : in out Gateway_Socket;
      Message : String)
   is
      pragma Unreferenced (Message);
   begin
      Socket.Failed := True;
   end On_Error;

   -----------------
   -- Gateway_URI --
   -----------------

   function Gateway_URI (Base : String) return String is
      Separator : constant Character :=
        (if Ada.Strings.Fixed.Index (Base, "?") = 0 then '?' else '&');
   begin
      if Base'Length < 6
        or else Base (Base'First .. Base'First + 5) /= "wss://"
      then
         raise Adacord.Configuration_Error with
           "the Discord gateway URL must use wss://";
      end if;

      return
        Base & Separator & "v=" & Ada.Strings.Fixed.Trim
          (Gateway_Version'Image, Ada.Strings.Both)
        & "&encoding=json";
   end Gateway_URI;

   --------------------
   -- Required_Field --
   --------------------

   function Required_Field
     (Value         : JSON.JSON_Value;
      Name          : String;
      Expected_Kind : JSON.JSON_Value_Type) return JSON.JSON_Value
   is
   begin
      if JSON.Kind (Value) /= JSON.JSON_Object_Type
        or else not JSON.Has_Field (Value, Name)
      then
         raise Adacord.Protocol_Error with
           "missing Discord gateway field: " & Name;
      end if;

      declare
         Result : constant JSON.JSON_Value := JSON.Get (Value, Name);
      begin
         if JSON.Kind (Result) /= Expected_Kind then
            raise Adacord.Protocol_Error with
              "invalid Discord gateway field: " & Name;
         end if;

         return Result;
      end;
   end Required_Field;

   ----------------------
   -- Required_Integer --
   ----------------------

   function Required_Integer
     (Value : JSON.JSON_Value;
      Name  : String) return Long_Long_Integer
   is
      Field : constant JSON.JSON_Value :=
        Required_Field (Value, Name, JSON.JSON_Int_Type);
   begin
      return JSON.Get (Field);
   end Required_Integer;

   ---------------------
   -- Required_String --
   ---------------------

   function Required_String
     (Value : JSON.JSON_Value;
      Name  : String) return String
   is
      Field : constant JSON.JSON_Value :=
        Required_Field (Value, Name, JSON.JSON_String_Type);
   begin
      return JSON.Get (Field);
   end Required_String;

   --------------
   -- Envelope --
   --------------

   function Envelope
     (Opcode : Natural;
      Data   : JSON.JSON_Value) return String
   is
      Result : constant JSON.JSON_Value := JSON.Create_Object;
   begin
      JSON.Set_Field (Result, "op", Opcode);
      JSON.Set_Field (Result, "d", Data);
      return JSON.Write (Result);
   end Envelope;

   ----------------------
   -- Identify_Payload --
   ----------------------

   function Identify_Payload
     (Token   : String;
      Intents : Adacord.Intents.Intent_Set) return String
   is
      Data       : constant JSON.JSON_Value := JSON.Create_Object;
      Properties : constant JSON.JSON_Value := JSON.Create_Object;
   begin
      if Intents > Adacord.Intents.Intent_Set (Long_Long_Integer'Last) then
         raise Adacord.Configuration_Error with
           "the gateway intents value is outside Discord's integer range";
      end if;

      JSON.Set_Field (Properties, "os", "unknown");
      JSON.Set_Field (Properties, "browser", "adacord");
      JSON.Set_Field (Properties, "device", "adacord");

      JSON.Set_Field (Data, "token", Token);
      JSON.Set_Field
        (Data, "intents", JSON.Create (Long_Long_Integer (Intents)));
      JSON.Set_Field (Data, "properties", Properties);

      return Envelope (2, Data);
   end Identify_Payload;

   --------------------
   -- Resume_Payload --
   --------------------

   function Resume_Payload
     (Token      : String;
      Session_ID : String;
      Sequence   : Long_Long_Integer) return String
   is
      Data : constant JSON.JSON_Value := JSON.Create_Object;
   begin
      JSON.Set_Field (Data, "token", Token);
      JSON.Set_Field (Data, "session_id", Session_ID);
      JSON.Set_Field (Data, "seq", JSON.Create (Sequence));
      return Envelope (6, Data);
   end Resume_Payload;

   -----------------------
   -- Heartbeat_Payload --
   -----------------------

   function Heartbeat_Payload
     (Has_Sequence : Boolean;
      Sequence     : Long_Long_Integer) return String is
   begin
      if Has_Sequence then
         return Envelope (1, JSON.Create (Sequence));
      else
         return Envelope (1, JSON.JSON_Null);
      end if;
   end Heartbeat_Payload;

   --------------------
   -- Is_Fatal_Close --
   --------------------

   function Is_Fatal_Close (Code : Integer) return Boolean is
     (Code in 4_004 | 4_010 | 4_011 | 4_012 | 4_013 | 4_014);

   -------------------------
   -- Fatal_Close_Message --
   -------------------------

   function Fatal_Close_Message (Code : Integer) return String is
      Suffix : constant String :=
        " (Discord gateway close code"
        & Integer'Image (Code) & ")";
   begin
      case Code is
         when 4_004 =>
            return
              "Discord rejected the bot token. Check DISCORD_BOT_TOKEN and "
              & "regenerate the token if necessary" & Suffix;
         when 4_010 =>
            return "Discord rejected the shard configuration" & Suffix;
         when 4_011 =>
            return
              "Discord requires this bot to use gateway sharding" & Suffix;
         when 4_012 =>
            return
              "Discord rejected the requested gateway API version" & Suffix;
         when 4_013 =>
            return
              "Discord rejected the Gateway_Intents value because it is "
              & "invalid" & Suffix;
         when 4_014 =>
            return
              "Discord refused one or more privileged gateway intents. "
              & "Enable the requested intents in Discord Developer Portal "
              & "> Bot > Privileged Gateway Intents, or remove them from "
              & "Gateway_Intents" & Suffix;
         when others =>
            return "Discord rejected the gateway session" & Suffix;
      end case;
   end Fatal_Close_Message;

   ----------------------
   -- Responsive_Delay --
   ----------------------

   procedure Responsive_Delay
     (Length : Duration;
      Sink   : in out Event_Sink'Class)
   is
      Deadline : constant Real_Time.Time :=
        Real_Time.Clock + Real_Time.To_Time_Span (Length);
   begin
      while not Stop_Requested (Sink) loop
         declare
            Now : constant Real_Time.Time := Real_Time.Clock;
         begin
            exit when Now >= Deadline;
            delay Duration'Min
              (0.1, Real_Time.To_Duration (Deadline - Now));
         end;
      end loop;
   end Responsive_Delay;

   ---------
   -- Run --
   ---------

   procedure Run
     (Token       : String;
      Intents     : Adacord.Intents.Intent_Set;
      Initial_URL : String;
      Sink        : in out Event_Sink'Class)
   is
      Generator       : Random.Generator;
      Current_URL     : Unbounded_String :=
        To_Unbounded_String (Initial_URL);
      Session_ID      : Unbounded_String;
      Sequence        : Long_Long_Integer := 0;
      Has_Sequence    : Boolean := False;
      Backoff         : Duration := 1.0;
      Clear_Session   : Boolean;
   begin
      if Token'Length = 0 then
         raise Adacord.Configuration_Error with
           "the Discord bot token must not be empty";
      elsif Initial_URL'Length = 0 then
         raise Adacord.Configuration_Error with
           "the Discord gateway URL must not be empty";
      end if;

      Random.Reset (Generator);

      while not Stop_Requested (Sink) loop
         Clear_Session := False;

         declare
            Socket             : Gateway_Socket;
            Hello_Received     : Boolean := False;
            Awaiting_ACK       : Boolean := False;
            Reconnect          : Boolean := False;
            Fatal              : Boolean := False;
            Connected          : Boolean := False;
            Heartbeat_Interval : Duration := 0.0;
            Next_Heartbeat     : Real_Time.Time := Real_Time.Clock;
            Hello_Deadline     : Real_Time.Time := Real_Time.Clock;
         begin
            begin
               AWS.Net.WebSocket.Connect
                 (Socket, Gateway_URI (To_String (Current_URL)));
               Hello_Deadline :=
                 Real_Time.Clock + Real_Time.To_Time_Span (15.0);
               Connected := True;
            exception
               when others =>
                  Handle_Error
                    (Sink,
                     "could not connect to the Discord gateway",
                     Fatal => False);
                  Reconnect := True;
            end;

            while not Reconnect
              and then not Fatal
              and then not Stop_Requested (Sink)
            loop
               declare
                  Timeout : Duration := Poll_Quantum;
               begin
                  if Hello_Received then
                     declare
                        Now : constant Real_Time.Time := Real_Time.Clock;
                     begin
                        if Next_Heartbeat <= Now then
                           Timeout := 0.0;
                        else
                           Timeout := Duration'Min
                             (Poll_Quantum,
                              Real_Time.To_Duration
                                (Next_Heartbeat - Now));
                        end if;
                     end;
                  end if;

                  --  The HTTP upgrade may already have buffered one or more
                  --  frames. Consume those before polling the OS descriptor,
                  --  and never overwrite a message awaiting dispatch.
                  if not Socket.Message_Ready then
                     AWS.Net.WebSocket.Buffered_Client_Fix
                       .Recover_Buffered_Message (Socket);
                  end if;

                  if not Socket.Message_Ready
                    and then not Socket.Closed
                    and then not Socket.Failed
                    and then AWS.Net.WebSocket.Poll (Socket, Timeout)
                  then
                     null;
                  end if;
               exception
                  when others =>
                     Socket.Failed := True;
               end;

               if not Hello_Received
                 and then Real_Time.Clock >= Hello_Deadline
               then
                  Handle_Error
                    (Sink,
                     "Discord did not send HELLO within 15 seconds",
                     Fatal => False);
                  Reconnect := True;
               end if;

               if Socket.Message_Ready then
                  declare
                     Text   : constant String :=
                       To_String (Socket.Received_Message);
                     Parsed : constant JSON.Read_Result := JSON.Read (Text);
                  begin
                     Socket.Message_Ready := False;
                     Socket.Received_Message := Null_Unbounded_String;

                     if not Parsed.Success then
                        raise Adacord.Protocol_Error with
                          "invalid JSON received from the Discord gateway";
                     end if;

                     declare
                        Root   : constant JSON.JSON_Value := Parsed.Value;
                        Opcode : constant Long_Long_Integer :=
                          Required_Integer (Root, "op");
                        Data   : JSON.JSON_Value := JSON.JSON_Null;
                     begin
                        if JSON.Has_Field (Root, "s") then
                           declare
                              Sequence_Field : constant JSON.JSON_Value :=
                                JSON.Get (Root, "s");
                           begin
                              if JSON.Kind (Sequence_Field) =
                                JSON.JSON_Int_Type
                              then
                                 Sequence := JSON.Get (Sequence_Field);
                                 if Sequence < 0 then
                                    raise Adacord.Protocol_Error with
                                      "negative Discord gateway sequence";
                                 end if;
                                 Has_Sequence := True;
                              elsif JSON.Kind (Sequence_Field) /=
                                JSON.JSON_Null_Type
                              then
                                 raise Adacord.Protocol_Error with
                                   "invalid Discord gateway sequence";
                              end if;
                           end;
                        end if;

                        if JSON.Has_Field (Root, "d") then
                           Data := JSON.Get (Root, "d");
                        end if;

                        case Opcode is
                           when 0 =>
                              declare
                                 Event_Name : constant String :=
                                   Required_String (Root, "t");
                              begin
                                 if Event_Name = "READY" then
                                    declare
                                       Event : constant Adacord.Types.Ready :=
                                         Adacord.Events.Parse_Ready (Data);
                                    begin
                                       Session_ID := Event.Session_ID;
                                       Current_URL := Event.Resume_Gateway_URL;
                                       Backoff := 1.0;
                                       Handle_Ready (Sink, Event);
                                    end;
                                 elsif Event_Name = "RESUMED" then
                                    Backoff := 1.0;
                                 elsif Event_Name = "MESSAGE_CREATE" then
                                    Handle_Message_Create
                                      (Sink,
                                       Adacord.Events.Parse_Message_Create
                                         (Data));
                                 elsif Event_Name = "INTERACTION_CREATE" then
                                    Handle_Interaction_Create
                                      (Sink,
                                       Adacord.Events.Parse_Interaction_Create
                                         (Data));
                                 end if;
                              end;

                           when 1 =>
                              Socket.Send
                                (Heartbeat_Payload
                                   (Has_Sequence, Sequence));
                              --  A requested heartbeat supplements the regular
                              --  schedule. Only scheduled heartbeats start the
                              --  ACK deadline, so a request just before a tick
                              --  cannot cause a premature disconnect.

                           when 7 =>
                              Reconnect := True;

                           when 9 =>
                              if JSON.Kind (Data) /=
                                JSON.JSON_Boolean_Type
                              then
                                 raise Adacord.Protocol_Error with
                                   "invalid Discord session response";
                              end if;

                              if not JSON.Get (Data) then
                                 Clear_Session := True;
                              end if;
                              Backoff := 1.0 + 4.0 * Duration
                                (Random.Random (Generator));
                              Reconnect := True;

                           when 10 =>
                              if Hello_Received then
                                 raise Adacord.Protocol_Error with
                                   "duplicate Discord HELLO payload";
                              end if;

                              declare
                                 Milliseconds : constant Long_Long_Integer :=
                                   Required_Integer
                                     (Data, "heartbeat_interval");
                              begin
                                 if Milliseconds <= 0 then
                                    raise Adacord.Protocol_Error with
                                      "invalid Discord heartbeat interval";
                                 end if;

                                 Heartbeat_Interval :=
                                   Duration (Milliseconds) / 1_000.0;
                                 Next_Heartbeat :=
                                   Real_Time.Clock
                                   + Real_Time.To_Time_Span
                                     (Heartbeat_Interval
                                      * Duration (Random.Random (Generator)));
                                 Hello_Received := True;

                                 if Has_Sequence
                                   and then Length (Session_ID) > 0
                                 then
                                    Socket.Send
                                      (Resume_Payload
                                         (Token,
                                          To_String (Session_ID),
                                          Sequence));
                                 else
                                    Socket.Send
                                      (Identify_Payload (Token, Intents));
                                 end if;
                              end;

                           when 11 =>
                              Awaiting_ACK := False;

                           when others =>
                              null;
                        end case;
                     end;
                  exception
                     when Adacord.Invalid_Event =>
                        Handle_Error
                          (Sink,
                           "Discord sent an invalid supported event",
                           Fatal => False);
                     when others =>
                        Handle_Error
                          (Sink,
                           "Discord sent an invalid gateway payload",
                           Fatal => False);
                        Reconnect := True;
                  end;
               end if;

               if Hello_Received
                 and then Next_Heartbeat <= Real_Time.Clock
                 and then not Reconnect
               then
                  if Awaiting_ACK then
                     Handle_Error
                       (Sink,
                        "Discord did not acknowledge the last heartbeat",
                        Fatal => False);
                     Reconnect := True;
                  else
                     begin
                        Socket.Send
                          (Heartbeat_Payload (Has_Sequence, Sequence));
                        Awaiting_ACK := True;
                        Next_Heartbeat :=
                          Real_Time.Clock
                          + Real_Time.To_Time_Span (Heartbeat_Interval);
                     exception
                        when others =>
                           Reconnect := True;
                     end;
                  end if;
               end if;

               if Socket.Closed or else Socket.Failed
                 or else Socket.Get_FD = AWS.Net.No_Socket
               then
                  if Is_Fatal_Close (Socket.Close_Code) then
                     Fatal := True;
                     Handle_Error
                       (Sink,
                        Fatal_Close_Message (Socket.Close_Code),
                        Fatal => True);
                  else
                     if Socket.Close_Code in 4_007 | 4_009 then
                        Clear_Session := True;
                     end if;
                     Reconnect := True;
                  end if;
               end if;
            end loop;

            if Connected
              and then not Socket.Closed
              and then Socket.Get_FD /= AWS.Net.No_Socket
            then
               begin
                  if Stop_Requested (Sink) then
                     Socket.Close ("Adacord stopping");
                  else
                     --  Discord invalidates sessions closed with 1000/1001.
                     Socket.Close
                       ("Adacord reconnecting",
                        AWS.Net.WebSocket.Internal_Server_Error);
                  end if;
               exception
                  when others =>
                     null;
               end;
            end if;

            if Fatal then
               return;
            end if;
         end;

         if Clear_Session then
            Current_URL := To_Unbounded_String (Initial_URL);
            Session_ID := Null_Unbounded_String;
            Has_Sequence := False;
            Sequence := 0;
         end if;

         if not Stop_Requested (Sink) then
            Responsive_Delay (Backoff, Sink);
            Backoff := Duration'Min (Maximum_Backoff, Backoff * 2.0);
         end if;
      end loop;
   end Run;

end Adacord.Gateway;
