with Ada.Strings.Unbounded;

with Adacord.Intents;
with Adacord.REST;
with Adacord.Types;

package Adacord.Clients is

   type Client is limited private;

   type Event_Handler is limited interface;

   procedure On_Ready
     (Handler : in out Event_Handler;
      Bot     : in out Client;
      Event   : Adacord.Types.Ready) is null;

   procedure On_Message_Create
     (Handler : in out Event_Handler;
      Bot     : in out Client;
      Event   : Adacord.Types.Message) is null;

   procedure On_Interaction_Create
     (Handler : in out Event_Handler;
      Bot     : in out Client;
      Event   : Adacord.Types.Interaction) is null;

   procedure On_Error
     (Handler : in out Event_Handler;
      Bot     : in out Client;
      Details : String;
      Fatal   : Boolean) is null;

   procedure Initialize
     (Self            : in out Client;
      Token           : String;
      Gateway_Intents : Adacord.Intents.Intent_Set :=
        Adacord.Intents.Guilds);
   --  Initialize before sharing the client with other tasks. Initialization
   --  and reinitialization must be externally serialized with all operations.

   procedure Run
     (Self    : in out Client;
      Handler : in out Event_Handler'Class);
   --  Connect to Discord and dispatch callbacks until Stop is called or a
   --  fatal Gateway error occurs. Gateway I/O and heartbeats run in a worker
   --  task, so callback latency does not delay heartbeats.
   --  At most 1024 events wait for callbacks. Overflow stops the Gateway,
   --  drains accepted events and reports a fatal On_Error before returning.
   --  Is_Running remains True until callbacks and the worker have finished.

   procedure Stop (Self : in out Client);

   function Is_Running (Self : Client) return Boolean;

   function Send_Message
     (Self       : Client;
      Channel_ID : Adacord.Types.Snowflake;
      Content    : String) return Adacord.Types.Message;

   procedure Send_Message
     (Self       : Client;
      Channel_ID : Adacord.Types.Snowflake;
      Content    : String);

   function Register_Global_Command
     (Self           : Client;
      Application_ID : Adacord.Types.Snowflake;
      Name           : String;
      Description    : String) return Adacord.Types.Application_Command;

   procedure Register_Global_Command
     (Self           : Client;
      Application_ID : Adacord.Types.Snowflake;
      Name           : String;
      Description    : String);

   procedure Respond_To_Interaction
     (Self        : Client;
      Interaction : Adacord.Types.Interaction;
      Content     : String;
      Ephemeral   : Boolean := False);

private

   protected type Lifecycle is
      procedure Start;
      procedure Request_Stop;
      procedure Finish;
      function Running return Boolean;
      function Stopping return Boolean;
   private
      Is_Active : Boolean := False;
      Must_Stop : Boolean := False;
   end Lifecycle;

   type Client is limited record
      HTTP              : Adacord.REST.Client;
      Token             : Ada.Strings.Unbounded.Unbounded_String;
      Gateway_Intents   : Adacord.Intents.Intent_Set :=
        Adacord.Intents.Guilds;
      Life              : aliased Lifecycle;
      Initialized       : Boolean := False;
   end record;

end Adacord.Clients;
