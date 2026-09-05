with Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Streams;
with Ada.Text_IO;

with AWS.Headers;
with AWS.Messages;
with AWS.Net.Log;
with AWS.Translator;
with AWS.Response;
with AWS.Server;
with AWS.Server.Status;
with AWS.Status;
with GNATCOLL.JSON;

with Adacord;
with Adacord.REST;
with Adacord.Types;

procedure REST_Tests is
   use Ada.Strings.Unbounded;
   package JSON renames GNATCOLL.JSON;

   Web_Server : AWS.Server.HTTP;
   Bot : Adacord.REST.Client;
   Started : Boolean := False;
   Assertions : Natural := 0;

   type Scenario is
     (Message_OK, Interaction_OK, Gateway_OK, Retry_Once, Retry_Forever,
      Retry_Negative, Retry_Too_Long, Retry_Invalid, Unauthorized,
      Forbidden, Bad_JSON, Bad_Fields, Server_Error, Redirect);

   protected Fixture is
      procedure Select_Scenario (Value : Scenario);
      procedure Record_Request
        (Request : AWS.Status.Data; Value : out Scenario; Number : out Natural);
      function Count return Natural;
      function Body_Text return String;
      function Authorization return String;
      function URI return String;
      procedure Record_Wire (Value : String);
      function Wire return String;
   private
      Current : Scenario := Gateway_OK;
      Requests : Natural := 0;
      Last_Body, Last_Auth, Last_URI, Wire_Data : Unbounded_String;
   end Fixture;

   protected body Fixture is
      procedure Select_Scenario (Value : Scenario) is
      begin
         Current := Value;
         Requests := 0;
      end Select_Scenario;

      procedure Record_Request
        (Request : AWS.Status.Data; Value : out Scenario; Number : out Natural)
      is
      begin
         Requests := Requests + 1;
         Number := Requests;
         Value := Current;
         Last_Body := AWS.Status.Binary_Data (Request);
         Last_Auth := To_Unbounded_String
           (AWS.Headers.Get_Values
              (AWS.Status.Header (Request), "Authorization"));
         Last_URI := To_Unbounded_String (AWS.Status.URI (Request));
      end Record_Request;

      function Count return Natural is (Requests);
      function Body_Text return String is (To_String (Last_Body));
      function Authorization return String is (To_String (Last_Auth));
      function URI return String is (To_String (Last_URI));
      procedure Record_Wire (Value : String) is
      begin
         Append (Wire_Data, Value);
      end Record_Wire;
      function Wire return String is (To_String (Wire_Data));
   end Fixture;

   procedure Capture_Wire
     (Direction : AWS.Net.Log.Data_Direction;
      Socket : AWS.Net.Socket_Type'Class;
      Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset)
   is
      pragma Unreferenced (Socket);
      use type AWS.Net.Log.Data_Direction;
   begin
      if Direction = AWS.Net.Log.Sent then
         Fixture.Record_Wire
           (AWS.Translator.To_String (Data (Data'First .. Last)));
      end if;
   end Capture_Wire;

   function Callback (Request : AWS.Status.Data) return AWS.Response.Data is
      Value : Scenario;
      Number : Natural;
      Gateway_JSON : constant String :=
        "{""url"":""wss://gateway.invalid"",""shards"":2,"
        & """session_start_limit"":{""remaining"":10,"
        & """reset_after"":1000,""max_concurrency"":1}}";
   begin
      Fixture.Record_Request (Request, Value, Number);
      case Value is
         when Message_OK =>
            return AWS.Response.Build
              ("application/json",
               "{""id"":""3"",""channel_id"":""2"",""content"":""ok"","
               & """timestamp"":""2026-01-01T00:00:00Z"","
               & """author"":{""id"":""1"",""username"":""test"","
               & """discriminator"":""0""}}");
         when Interaction_OK =>
            return AWS.Response.Build ("application/json", "", AWS.Messages.S204);
         when Gateway_OK =>
            return AWS.Response.Build ("application/json", Gateway_JSON);
         when Retry_Once | Retry_Forever =>
            if Value = Retry_Once and then Number = 2 then
               return AWS.Response.Build ("application/json", Gateway_JSON);
            end if;
            return AWS.Response.Build
              ("application/json", "{""retry_after"":0}", AWS.Messages.S429);
         when Retry_Negative =>
            return AWS.Response.Build
              ("application/json", "{""retry_after"":-1}", AWS.Messages.S429);
         when Retry_Too_Long =>
            return AWS.Response.Build
              ("application/json", "{""retry_after"":61}", AWS.Messages.S429);
         when Retry_Invalid =>
            return AWS.Response.Build
              ("application/json", "{""retry_after"":""bad""}", AWS.Messages.S429);
         when Unauthorized =>
            return AWS.Response.Build ("application/json", "{}", AWS.Messages.S401);
         when Forbidden =>
            return AWS.Response.Build ("application/json", "{}", AWS.Messages.S403);
         when Bad_JSON =>
            return AWS.Response.Build ("application/json", "not JSON");
         when Bad_Fields =>
            return AWS.Response.Build ("application/json", "{}");
         when Server_Error =>
            return AWS.Response.Build ("application/json", "{}", AWS.Messages.S500);
         when Redirect =>
            return AWS.Response.URL ("http://127.0.0.1:1/forbidden");
      end case;
   end Callback;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
      Assertions := Assertions + 1;
   end Assert;

   procedure Reject_Initialization
     (Base : String := "http://127.0.0.1:1";
      Token : String := "test";
      Agent : String := "test agent")
   is
      Invalid : Adacord.REST.Client;
   begin
      Invalid.Initialize (Token, Base, Agent);
      raise Program_Error with "invalid REST initialization accepted";
   exception
      when Adacord.Configuration_Error =>
         Assertions := Assertions + 1;
   end Reject_Initialization;

   procedure Reject_Content (Content : String) is
      Ignored : Adacord.Types.Message;
      Interaction : Adacord.Types.Interaction;
   begin
      begin
         Ignored := Bot.Send_Message
           (Adacord.Types.Parse_Snowflake ("2"), Content);
         raise Program_Error with "invalid message content accepted";
      exception
         when Adacord.Configuration_Error =>
            Assertions := Assertions + 1;
      end;
      Interaction.ID := Adacord.Types.Parse_Snowflake ("3");
      Interaction.Token := To_Unbounded_String ("interaction-token");
      begin
         Bot.Respond_To_Interaction (Interaction, Content);
         raise Program_Error with "invalid interaction content accepted";
      exception
         when Adacord.Configuration_Error =>
            Assertions := Assertions + 1;
      end;
   end Reject_Content;

   procedure Test_HTTP is
      Ignored : Adacord.REST.Gateway_Info;
      Message : Adacord.Types.Message;
      Interaction : Adacord.Types.Interaction;
      Unicode_Content : Unbounded_String;
   begin
      Fixture.Select_Scenario (Gateway_OK);
      Ignored := Bot.Get_Gateway_Info;
      Assert (Ignored.Recommended_Shards = 2, "gateway JSON decoding");
      Assert (Fixture.Authorization = "Bot test-token", "bot authorization");
      Assert (Fixture.URI = "/api/v10/gateway/bot", "base trailing slashes removed");

      --  Exactly 2000 Unicode characters, encoded as 4000 UTF-8 bytes.
      for I in 1 .. 2_000 loop
         Append (Unicode_Content, Character'Val (16#C3#));
         Append (Unicode_Content, Character'Val (16#A9#));
      end loop;
      Fixture.Select_Scenario (Message_OK);
      Message := Bot.Send_Message
        (Adacord.Types.Parse_Snowflake ("2"), To_String (Unicode_Content));
      Assert (To_String (Message.Content) = "ok", "message response decoded");
      declare
         Payload : constant JSON.JSON_Value := JSON.Read (Fixture.Body_Text);
         Content : constant String := JSON.Get (JSON.Get (Payload, "content"));
         Allowed : constant JSON.JSON_Value := JSON.Get (Payload, "allowed_mentions");
         Mentions : constant JSON.JSON_Array := JSON.Get (JSON.Get (Allowed, "parse"));
      begin
         Assert (Content = To_String (Unicode_Content), "Unicode payload preserved");
         Assert (JSON.Length (Mentions) = 0, "message mentions disabled");
      end;

      Fixture.Select_Scenario (Bad_Fields);
      begin
         Message := Bot.Send_Message (Adacord.Types.Parse_Snowflake ("2"), "test");
         raise Program_Error with "malformed message response accepted";
      exception
         when Adacord.Protocol_Error =>
            Assertions := Assertions + 1;
      end;

      Fixture.Select_Scenario (Interaction_OK);
      Interaction.ID := Adacord.Types.Parse_Snowflake ("3");
      Interaction.Token := To_Unbounded_String ("interaction-token");
      Bot.Respond_To_Interaction (Interaction, To_String (Unicode_Content), True);
      Assert (Fixture.Authorization = "", "interaction does not send bot token");
      Assert (Fixture.URI = "/api/v10/interactions/3/interaction-token/callback",
              "interaction callback path");
      declare
         Payload : constant JSON.JSON_Value := JSON.Read (Fixture.Body_Text);
         Data : constant JSON.JSON_Value := JSON.Get (Payload, "data");
         Flags : constant Integer := JSON.Get (JSON.Get (Data, "flags"));
         Content : constant String := JSON.Get (JSON.Get (Data, "content"));
      begin
         Assert (Flags = 64, "ephemeral flag");
         Assert (Content = To_String (Unicode_Content), "Unicode interaction payload");
      end;

      --  Inspect bytes on the wire: AWS server URL normalization can
      --  reinterpret decoded reserved characters before invoking Callback.
      Interaction.Token := To_Unbounded_String ("token?query#fragment");
      AWS.Net.Log.Start (Capture_Wire'Unrestricted_Access);
      Bot.Respond_To_Interaction (Interaction, "test");
      AWS.Net.Log.Stop;
      Assert (Ada.Strings.Fixed.Index
                (Fixture.Wire,
                 "/api/v10/interactions/3/token%3Fquery%23fragment/callback") > 0,
              "reserved interaction token bytes escaped on the wire");

      Fixture.Select_Scenario (Gateway_OK);
      Reject_Content ("");
      Reject_Content ((1 .. 2_001 => 'a'));
      Reject_Content (To_String (Unicode_Content) & "a");
      Reject_Content ((1 => Character'Val (16#FF#)));
      Assert (Fixture.Count = 0, "invalid content rejected before transport");
      Interaction.Token := Null_Unbounded_String;
      begin
         Bot.Respond_To_Interaction (Interaction, "test");
         raise Program_Error with "empty interaction token accepted";
      exception
         when Adacord.Configuration_Error =>
            Assert (Fixture.Count = 0, "empty token rejected before transport");
      end;

      Fixture.Select_Scenario (Retry_Once);
      Ignored := Bot.Get_Gateway_Info;
      Assert (Fixture.Count = 2, "429 response retried");
      for Mode in Retry_Forever .. Retry_Invalid loop
         Fixture.Select_Scenario (Mode);
         begin
            Ignored := Bot.Get_Gateway_Info;
            raise Program_Error with "invalid rate limit accepted";
         exception
            when Adacord.Rate_Limit_Error =>
               Assert (Fixture.Count = (if Mode = Retry_Forever then 3 else 1),
                       "rate limit attempts bounded");
         end;
      end loop;
      for Mode in Unauthorized .. Redirect loop
         Fixture.Select_Scenario (Mode);
         begin
            Ignored := Bot.Get_Gateway_Info;
            raise Program_Error with "invalid HTTP response accepted";
         exception
            when Adacord.Authentication_Error =>
               Assert (Mode in Unauthorized | Forbidden, "authentication exception");
            when Adacord.Protocol_Error =>
               Assert (Mode in Bad_JSON .. Redirect, "protocol exception");
         end;
         Assert (Fixture.Count = 1, "error not retried or redirected");
      end loop;
   end Test_HTTP;
begin
   Reject_Initialization (Base => "");
   Reject_Initialization (Base => "discord.com/api/v10");
   Reject_Initialization (Base => "ftp://discord.com/api");
   Reject_Initialization (Base => "https://");
   Reject_Initialization (Base => "http:///api");
   Reject_Initialization (Base => "http://localhost:70000/api");
   Reject_Initialization (Base => "http://user:pass@localhost/api");
   Reject_Initialization (Base => "http://localhost/api?query=1");
   Reject_Initialization (Base => "http://localhost/api#fragment");
   Reject_Initialization (Base => "http://local host/api");
   Reject_Initialization (Token => "token" & ASCII.CR & ASCII.LF & "X-Test: yes");
   Reject_Initialization (Token => "token with space");
   Reject_Initialization (Agent => "agent" & ASCII.LF & "X-Test: yes");

   AWS.Server.Start
     (Web_Server, "REST tests", Callback'Unrestricted_Access,
      Host => "127.0.0.1", Port => 0, Max_Connection => 1);
   Started := True;
   Bot.Initialize
     ("test-token", AWS.Server.Status.Local_URL (Web_Server) & "/api/v10///");
   Test_HTTP;
   AWS.Server.Shutdown (Web_Server);
   Started := False;
   Ada.Text_IO.Put_Line ("PASS REST:" & Assertions'Image);
exception
   when others =>
      AWS.Net.Log.Stop;
      if Started then
         AWS.Server.Shutdown (Web_Server);
      end if;
      raise;
end REST_Tests;
