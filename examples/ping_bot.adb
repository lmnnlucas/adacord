with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Adacord;
with Adacord.Clients;
with Adacord.Config;
with Adacord.Intents;
with Adacord.Types;

procedure Ping_Bot is

   use Ada.Strings.Unbounded;

   type Handler is new Adacord.Clients.Event_Handler with record
      Command_Registered : Boolean := False;
   end record;

   overriding procedure On_Ready
     (Self  : in out Handler;
      Bot   : in out Adacord.Clients.Client;
      Event : Adacord.Types.Ready);

   overriding procedure On_Interaction_Create
     (Self  : in out Handler;
      Bot   : in out Adacord.Clients.Client;
      Event : Adacord.Types.Interaction);

   overriding procedure On_Error
     (Self    : in out Handler;
      Bot     : in out Adacord.Clients.Client;
      Details : String;
      Fatal   : Boolean);

   overriding procedure On_Ready
     (Self  : in out Handler;
      Bot   : in out Adacord.Clients.Client;
      Event : Adacord.Types.Ready)
   is
   begin
      Ada.Text_IO.Put_Line
        ("Connected as " & To_String (Event.Current_User.Username));

      if not Self.Command_Registered then
         Adacord.Clients.Register_Global_Command
           (Bot,
            Application_ID => Event.Application_ID,
            Name           => "ping",
            Description    => "Repond avec pong");
         Self.Command_Registered := True;
         Ada.Text_IO.Put_Line ("Slash command /ping registered.");
      end if;
   end On_Ready;

   overriding procedure On_Interaction_Create
     (Self  : in out Handler;
      Bot   : in out Adacord.Clients.Client;
      Event : Adacord.Types.Interaction)
   is
      pragma Unreferenced (Self);
      use type Adacord.Types.Interaction_Kind;
   begin
      if Event.Kind = Adacord.Types.Application_Command_Interaction
        and then Event.Command_Name.Present
        and then To_String (Event.Command_Name.Value) = "ping"
      then
         Adacord.Clients.Respond_To_Interaction
           (Bot,
            Interaction => Event,
            Content     => "pong");
      end if;
   end On_Interaction_Create;

   overriding procedure On_Error
     (Self    : in out Handler;
      Bot     : in out Adacord.Clients.Client;
      Details : String;
      Fatal   : Boolean)
   is
      pragma Unreferenced (Self, Bot);
      Prefix : constant String :=
        (if Fatal then "fatal: " else "warning: ");
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Prefix & Details);
   end On_Error;

   Bot       : Adacord.Clients.Client;
   Callbacks : Handler;
   Token     : Unbounded_String;

begin
   begin
      Token := To_Unbounded_String
        (Adacord.Config.Required_Value ("DISCORD_BOT_TOKEN"));
   exception
      when Adacord.Configuration_Error =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "Add DISCORD_BOT_TOKEN to .env or to the environment.");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
   end;

   Adacord.Clients.Initialize
     (Bot,
      Token           => To_String (Token),
      Gateway_Intents => Adacord.Intents.Guilds);

   Adacord.Clients.Run (Bot, Callbacks);
end Ping_Bot;
