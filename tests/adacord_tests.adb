with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Characters.Latin_1;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNATCOLL.JSON;

with Adacord;
with Adacord.Clients;
with Adacord.Config;
with Adacord.Events;
with Adacord.Intents;
with Adacord.REST;
with Adacord.Types;

procedure Adacord_Tests is

   package JSON renames GNATCOLL.JSON;

   use Ada.Strings.Unbounded;
   use type Adacord.Intents.Intent_Set;
   use type Adacord.Types.Interaction_Kind;

   Tests_Run : Natural := 0;

   procedure Run_Test (Name : String; Action : not null access procedure);

   procedure Assert (Condition : Boolean; Description : String);

   procedure Assert (Condition : Boolean; Description : String) is
   begin
      if not Condition then
         raise Program_Error with "assertion failed: " & Description;
      end if;

      Tests_Run := Tests_Run + 1;
   end Assert;

   procedure Run_Test (Name : String; Action : not null access procedure) is
   begin
      Ada.Text_IO.Put_Line ("[test] " & Name);
      Action.all;
   end Run_Test;

   procedure Expect_Invalid_Snowflake (Value : String);

   procedure Expect_Invalid_Snowflake (Value : String) is
      Ignored : Adacord.Types.Snowflake;
   begin
      Ignored := Adacord.Types.Parse_Snowflake (Value);
      raise Program_Error with
        "snowflake should have been rejected: " & Value;
   exception
      when Adacord.Invalid_Event =>
         Tests_Run := Tests_Run + 1;
   end Expect_Invalid_Snowflake;

   procedure Test_Snowflakes is
   begin
      declare
         Small : constant Adacord.Types.Snowflake :=
           Adacord.Types.Parse_Snowflake ("123456789012345678");
      begin
         Assert
           (Adacord.Types.Image (Small) = "123456789012345678",
            "snowflake round trip");
      end;

      declare
         Large : constant Adacord.Types.Snowflake :=
           Adacord.Types.Parse_Snowflake ("18446744073709551615");
      begin
         Assert
           (Adacord.Types.Image (Large) = "18446744073709551615",
            "maximum unsigned snowflake");
      end;
      Assert
        (Adacord.Types.Is_Valid ("42"),
         "valid snowflake predicate");
      Assert
        (not Adacord.Types.Is_Valid ("nope"),
         "invalid snowflake predicate");

      Expect_Invalid_Snowflake ("");
      Expect_Invalid_Snowflake ("0");
      Expect_Invalid_Snowflake ("01");
      Expect_Invalid_Snowflake ("-1");
      Expect_Invalid_Snowflake ("+1");
      Expect_Invalid_Snowflake (" 1");
      Expect_Invalid_Snowflake ("1 ");
      Expect_Invalid_Snowflake ("1_000");
      Expect_Invalid_Snowflake ("16#FF#");
      Expect_Invalid_Snowflake ("18446744073709551616");
   end Test_Snowflakes;

   procedure Test_Intents is
   begin
      Assert
        (Adacord.Intents.Message_Bot = 37_377,
         "message bot intent mask");
      Assert
        (Adacord.Intents.Contains
           (Adacord.Intents.Message_Bot,
            Adacord.Intents.Message_Content),
         "message bot includes privileged content intent");
      Assert
        (not Adacord.Intents.Contains
           (Adacord.Intents.All_Non_Privileged,
            Adacord.Intents.Message_Content),
         "non-privileged intents exclude message content");
   end Test_Intents;

   procedure Test_Ready_Event is
      Value : constant JSON.JSON_Value := JSON.Read
        ("{""v"":10,"
         & """user"":{"
         & """id"":""42"","
         & """username"":""AdaBot"","
         & """discriminator"":""0"","
         & """global_name"":null,"
         & """avatar"":null,"
         & """bot"":true},"
         & """application"":{""id"":""43""},"
         & """session_id"":""session"","
         & """resume_gateway_url"":""wss://gateway.discord.gg"","
         & """guilds"":[{""id"":""99""}]}");
      Event : constant Adacord.Types.Ready :=
        Adacord.Events.Parse_Ready (Value);
   begin
      Assert (Event.Version = 10, "READY version");
      Assert
        (To_String (Event.Current_User.Username) = "AdaBot",
         "READY user");
      Assert
        (Adacord.Types.Image (Event.Application_ID) = "43",
         "READY application id");
      Assert
        (Adacord.Types.Length (Event.Guilds) = 1,
         "READY guild count");
      Assert
        (Adacord.Types.Image
           (Adacord.Types.Element (Event.Guilds, 1)) = "99",
         "READY guild id");
   end Test_Ready_Event;

   procedure Test_Message_Event is
      Value : constant JSON.JSON_Value := JSON.Read
        ("{""id"":""100"","
         & """channel_id"":""200"","
         & """guild_id"":null,"
         & """author"":{"
         & """id"":""42"","
         & """username"":""AdaBot"","
         & """discriminator"":""0"","
         & """global_name"":""Ada"","
         & """avatar"":null,"
         & """bot"":false,"
         & """system"":false},"
         & """content"":""!ping"","
         & """timestamp"":""2026-08-29T12:00:00Z"","
         & """edited_timestamp"":null,"
         & """tts"":false,"
         & """mention_everyone"":false,"
         & """pinned"":false}");
      Event : constant Adacord.Types.Message :=
        Adacord.Events.Parse_Message_Create (Value);
   begin
      Assert (To_String (Event.Content) = "!ping", "message content");
      Assert
        (Adacord.Types.Image (Event.Channel_ID) = "200",
         "message channel");
      Assert (not Event.Guild_ID.Present, "DM has no guild id");
      Assert
        (Event.Author.Global_Name.Present
         and then To_String (Event.Author.Global_Name.Value) = "Ada",
         "optional global name");
   end Test_Message_Event;

   procedure Test_Interaction_Event is
      Value : constant JSON.JSON_Value := JSON.Read
        ("{""id"":""1000"","
         & """application_id"":""43"","
         & """type"":2,"
         & """data"":{""id"":""500"","
         & """name"":""ping"","
         & """type"":1},"
         & """guild_id"":""99"","
         & """channel_id"":""200"","
         & """token"":""interaction-token"","
         & """version"":1}");
      Event : constant Adacord.Types.Interaction :=
        Adacord.Events.Parse_Interaction_Create (Value);
   begin
      Assert
        (Event.Kind = Adacord.Types.Application_Command_Interaction,
         "interaction kind");
      Assert (Event.Type_Code = 2, "interaction type code");
      Assert
        (Adacord.Types.Image (Event.Application_ID) = "43",
         "interaction application id");
      Assert
        (Event.Command_ID.Present
         and then Adacord.Types.Image (Event.Command_ID.Value) = "500",
         "interaction command id");
      Assert
        (Event.Command_Name.Present
         and then To_String (Event.Command_Name.Value) = "ping",
         "interaction command name");
      Assert (Event.Command_Type = 1, "interaction command type");
      Assert
        (Event.Guild_ID.Present
         and then Adacord.Types.Image (Event.Guild_ID.Value) = "99",
         "interaction guild id");
      Assert
        (Event.Channel_ID.Present
         and then Adacord.Types.Image (Event.Channel_ID.Value) = "200",
         "interaction channel id");
      Assert
        (To_String (Event.Token) = "interaction-token",
         "interaction token");
   end Test_Interaction_Event;

   procedure Test_Invalid_Event is
      Value : constant JSON.JSON_Value := JSON.Read ("{""id"":""1""}");
      Ignored : Adacord.Types.Message;
   begin
      Ignored := Adacord.Events.Parse_Message (Value);
      raise Program_Error with "incomplete Message should be rejected";
   exception
      when Adacord.Invalid_Event =>
         Tests_Run := Tests_Run + 1;
   end Test_Invalid_Event;

   procedure Test_Parser_Boundaries is
      Message : constant JSON.JSON_Value := JSON.Read
        ("{""id"":""1"",""channel_id"":""2"","
         & """author"":{""id"":""3"",""username"":""test""},"
         & """content"":"""",""timestamp"":""now""}");
      Interaction : constant JSON.JSON_Value := JSON.Read
        ("{""id"":""1"",""application_id"":""2"","
         & """type"":99,""token"":""synthetic"",""version"":1}");

      procedure Reject_Message (Value : JSON.JSON_Value) is
         Ignored : Adacord.Types.Message;
      begin
         Ignored := Adacord.Events.Parse_Message (Value);
         raise Program_Error with "invalid message should be rejected";
      exception
         when Adacord.Invalid_Event =>
            Tests_Run := Tests_Run + 1;
      end Reject_Message;

      procedure Reject_Interaction (Value : JSON.JSON_Value) is
         Ignored : Adacord.Types.Interaction;
      begin
         Ignored := Adacord.Events.Parse_Interaction_Create (Value);
         raise Program_Error with "invalid interaction should be rejected";
      exception
         when Adacord.Invalid_Event =>
            Tests_Run := Tests_Run + 1;
      end Reject_Interaction;
   begin
      declare
         Parsed : constant Adacord.Types.Message :=
           Adacord.Events.Parse_Message (Message);
         Future : constant Adacord.Types.Interaction :=
           Adacord.Events.Parse_Interaction_Create (Interaction);
      begin
         Assert (not Parsed.Guild_ID.Present, "absent optional snowflake");
         Assert (not Parsed.Is_TTS, "absent boolean defaults to false");
         Assert (Future.Kind = Adacord.Types.Unknown_Interaction
                 and then Future.Type_Code = 99,
                 "future interaction type is preserved");
      end;
      Reject_Message (JSON.Read ("null"));
      Reject_Message (JSON.Read ("[]"));
      declare
         Value : constant JSON.JSON_Value := JSON.Clone (Message);
      begin
         JSON.Set_Field (Value, "guild_id", JSON.JSON_Null);
         Assert (not Adacord.Events.Parse_Message (Value).Guild_ID.Present,
                 "null optional snowflake");
         JSON.Set_Field (Value, "guild_id", Integer'(2));
         Reject_Message (Value);
      end;
      declare
         Value : constant JSON.JSON_Value := JSON.Clone (Message);
      begin
         JSON.Set_Field (Value, "tts", JSON.JSON_Null);
         Reject_Message (Value);
         JSON.Set_Field (Value, "tts", "false");
         Reject_Message (Value);
      end;
      declare
         Value : constant JSON.JSON_Value := JSON.Clone (Message);
      begin
         JSON.Set_Field (Value, "content", JSON.JSON_Null);
         Reject_Message (Value);
      end;
      declare
         Value : constant JSON.JSON_Value := JSON.Clone (Interaction);
      begin
         JSON.Set_Field (Value, "type", Integer'(-1));
         Reject_Interaction (Value);
         JSON.Set_Field
           (Value, "type", JSON.Read
              (Long_Long_Integer'Image (Long_Long_Integer (Natural'Last) + 1)));
         Reject_Interaction (Value);
         JSON.Set_Field (Value, "type", "2");
         Reject_Interaction (Value);
         JSON.Set_Field (Value, "type", Integer'(2));
         Reject_Interaction (Value);
      end;
   end Test_Parser_Boundaries;

   procedure Test_Configuration_Guards is
      HTTP : Adacord.REST.Client;
      Bot  : Adacord.Clients.Client;
   begin
      begin
         Adacord.REST.Initialize (HTTP, "");
         raise Program_Error with "empty REST token should be rejected";
      exception
         when Adacord.Configuration_Error =>
            Tests_Run := Tests_Run + 1;
      end;

      begin
         Adacord.Clients.Initialize (Bot, "");
         raise Program_Error with "empty bot token should be rejected";
      exception
         when Adacord.Configuration_Error =>
            Tests_Run := Tests_Run + 1;
      end;
   end Test_Configuration_Guards;

   procedure Test_Dotenv is
      Directory : constant String := "obj/tests";
      Path      : constant String := Directory & "/adacord_tests.env";
      Name      : constant String := "ADACORD_TEST_DOTENV";
      File      : Ada.Text_IO.File_Type;

      procedure Check_Value (Line : String; Expected : String) is
      begin
         declare
            Raw_File : Ada.Streams.Stream_IO.File_Type;
            Bytes : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Line'Length + 1));
         begin
            for I in Line'Range loop
               Bytes (Ada.Streams.Stream_Element_Offset
                 (I - Line'First + 1)) := Character'Pos (Line (I));
            end loop;
            Bytes (Bytes'Last) := 10;
            Ada.Streams.Stream_IO.Create
              (Raw_File, Ada.Streams.Stream_IO.Out_File, Path);
            Ada.Streams.Stream_IO.Write (Raw_File, Bytes);
            Ada.Streams.Stream_IO.Close (Raw_File);
         end;
         Adacord.Config.Load_Dotenv (Path, Override => True);
         Assert (Ada.Environment_Variables.Value (Name, "") = Expected,
                 "dotenv syntax value");
      end Check_Value;

      procedure Check_Invalid (Line : String) is
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
         Ada.Text_IO.Put_Line (File, Line);
         Ada.Text_IO.Close (File);
         Adacord.Config.Load_Dotenv (Path, Override => True);
         raise Program_Error with "invalid dotenv should be rejected";
      exception
         when Error : Adacord.Configuration_Error =>
            Assert (Ada.Strings.Fixed.Index
                      (Ada.Exceptions.Exception_Message (Error),
                       "synthetic-secret") = 0,
                    "dotenv errors do not disclose values");
      end Check_Invalid;

      procedure Cleanup;

      procedure Cleanup is
      begin
         if Ada.Environment_Variables.Exists (Name) then
            Ada.Environment_Variables.Clear (Name);
         end if;

         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
      end Cleanup;
   begin
      Cleanup;
      Ada.Directories.Create_Path (Directory);
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, "# test configuration");
      Ada.Text_IO.Put_Line (File, Name & " = ""from dotenv""");
      Ada.Text_IO.Close (File);

      Adacord.Config.Load_Dotenv (Path);
      Assert
        (Ada.Environment_Variables.Value (Name) = "from dotenv",
         "dotenv value is loaded");

      Ada.Environment_Variables.Set (Name, "from environment");
      Adacord.Config.Load_Dotenv (Path);
      Assert
        (Ada.Environment_Variables.Value (Name) = "from environment",
         "environment takes precedence over dotenv");

      Adacord.Config.Load_Dotenv (Path, Override => True);
      Assert
        (Ada.Environment_Variables.Value (Name) = "from dotenv",
         "dotenv can explicitly override the environment");
      Assert
        (Adacord.Config.Required_Value (Name, Path) = "from dotenv",
         "required dotenv value is returned");

      Check_Value
        (Character'Val (16#EF#) & Character'Val (16#BB#)
         & Character'Val (16#BF#) & Ada.Characters.Latin_1.HT
         & "export" & Ada.Characters.Latin_1.HT & Name
         & Ada.Characters.Latin_1.HT & "=" & Ada.Characters.Latin_1.HT
         & "bom and tabs" & Ada.Characters.Latin_1.HT, "bom and tabs");
      Check_Value (Name & "=plain # comment", "plain");
      Check_Value (Name & "=word#literal", "word#literal");
      Check_Value (Name & "=""quoted # literal"" # comment",
                   "quoted # literal");
      Check_Value (Name & "='single # literal' # comment",
                   "single # literal");
      Check_Value (Name & "=""""", "");
      Check_Value (Name & "= # comment", "");
      Check_Invalid (Name & "=""synthetic-secret");
      Check_Invalid (Name & "=""synthetic-secret""garbage");
      Check_Invalid ("1INVALID=synthetic-secret");

      Cleanup;

      begin
         declare
            Ignored : constant String :=
              Adacord.Config.Required_Value (Name, "missing.env");
         begin
            raise Program_Error with
              "missing required value should be rejected: " & Ignored;
         end;
      exception
         when Adacord.Configuration_Error =>
            Tests_Run := Tests_Run + 1;
      end;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Cleanup;
         raise;
   end Test_Dotenv;

begin
   Run_Test ("snowflakes", Test_Snowflakes'Access);
   Run_Test ("intents", Test_Intents'Access);
   Run_Test ("READY parser", Test_Ready_Event'Access);
   Run_Test ("MESSAGE_CREATE parser", Test_Message_Event'Access);
   Run_Test
     ("INTERACTION_CREATE parser", Test_Interaction_Event'Access);
   Run_Test ("invalid event", Test_Invalid_Event'Access);
   Run_Test ("parser boundaries", Test_Parser_Boundaries'Access);
   Run_Test
     ("configuration guards", Test_Configuration_Guards'Access);
   Run_Test ("dotenv configuration", Test_Dotenv'Access);

   Assert (Adacord.Version = "0.1.0-dev", "library version");
   Ada.Text_IO.Put_Line
     ("PASS:" & Natural'Image (Tests_Run) & " assertions");
end Adacord_Tests;
