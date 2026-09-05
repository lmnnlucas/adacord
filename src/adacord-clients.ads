with Ada.Strings.Unbounded;

with Adacord.Intents;
with Adacord.REST;
with Adacord.Types;

package Adacord.Clients is
   --  High-level bot lifecycle, event callbacks and REST convenience operations.
   --  Handlers execute sequentially in the task calling `Run`. Keep them short:
   --  a slow callback delays later events and may miss interaction deadlines.
   --  Calls that send data share the validation and errors of `Adacord.REST`.

   type Client is limited private;
   --  Owns credentials, REST access and a synchronized running/stopping state.

   type Event_Handler is limited interface;
   --  Override only the callbacks your bot needs; all defaults do nothing.

   procedure On_Ready
     (Handler : in out Event_Handler;
      Bot     : in out Client;
      Event   : Adacord.Types.Ready) is null;
   --  Called after a new Gateway session becomes ready (not on RESUMED).
   --  @param Handler Application-defined callback state.
   --  @param Bot Running client, usable for REST operations or `Stop`.
   --  @param Event Bot identity, application ID and resumable session details.

   procedure On_Message_Create
     (Handler : in out Event_Handler;
      Bot     : in out Client;
      Event   : Adacord.Types.Message) is null;
   --  Called for a newly created message allowed by the configured intents.
   --  @param Handler Application-defined callback state.
   --  @param Bot Running client.
   --  @param Event Parsed message; check Author.Is_Bot to avoid bot reply loops.

   procedure On_Interaction_Create
     (Handler : in out Event_Handler;
      Bot     : in out Client;
      Event   : Adacord.Types.Interaction) is null;
   --  Called for an interaction, including supported application commands.
   --  Only application-command events populate command metadata in this version.
   --  @param Handler Application-defined callback state.
   --  @param Bot Running client, usable to respond to the interaction.
   --  @param Event Parsed interaction, including its confidential response token.

   procedure On_Error
     (Handler : in out Event_Handler;
      Bot     : in out Client;
      Details : String;
      Fatal   : Boolean) is null;
   --  Reports a Gateway error, queue overflow or callback exception.
   --  Exceptions raised here are ignored. Exceptions in other callbacks are
   --  reported here with a generic message and do not stop normal dispatch.
   --  @param Handler Application-defined callback state.
   --  @param Bot Client whose event loop is reporting the error.
   --  @param Details Diagnostic text supplied by the library, without tokens.
   --  @param Fatal True when the Gateway cannot continue or the queue overflowed.

   procedure Initialize
     (Self            : in out Client;
      Token           : String;
      Gateway_Intents : Adacord.Intents.Intent_Set :=
        Adacord.Intents.Guilds);
   --  Configure a bot without opening its Gateway connection.
   --  Call before sharing the client with other tasks. Serialize initialization
   --  and reinitialization with every other operation on the same client.
   --  HTTPS certificate configuration is process-wide in AWS.
   --  @param Self Client to configure; must not be running.
   --  @param Token Bot token without the "Bot " prefix; never log this value.
   --  @param Gateway_Intents Events to request; defaults to the Guilds intent.
   --  @exception Adacord.Configuration_Error Invalid token, TLS setup or lifecycle.

   procedure Run
     (Self    : in out Client;
      Handler : in out Event_Handler'Class);
   --  Connect to Discord and dispatch callbacks until shutdown.
   --  This call blocks. Gateway I/O and heartbeats run in a worker task, while
   --  callbacks run sequentially in the calling task. At most 1024 events wait
   --  for dispatch. Overflow stops the worker, drains accepted events and calls
   --  On_Error with Fatal=True. Is_Running stays True until completion.
   --  A fatal Gateway error is reported through On_Error. Failure of the initial
   --  REST gateway lookup raises the corresponding REST exception directly.
   --  @param Self Initialized client; one active Run is permitted per client.
   --  @param Handler Callback receiver, which must remain alive during this call.
   --  @exception Adacord.Configuration_Error Uninitialized or already running.
   --  @exception Adacord.Transport_Error Initial HTTP gateway lookup failed.
   --  @exception Adacord.Authentication_Error Initial lookup returned 401 or 403.
   --  @exception Adacord.Rate_Limit_Error Initial lookup rate limit could not clear.
   --  @exception Adacord.Protocol_Error Invalid initial gateway response.

   procedure Stop (Self : in out Client);
   --  Request cooperative shutdown; safe to call from a callback or another task.
   --  The request is idempotent. Queued events are drained before Run returns.
   --  Blocking AWS network calls and callbacks can delay shutdown; this procedure
   --  does not join the worker or guarantee an upper bound on the shutdown time.
   --  @param Self Client whose current Run should stop.

   function Is_Running (Self : Client) return Boolean;
   --  Read the synchronized lifecycle state.
   --  @param Self Client to inspect.
   --  @return True from successful Run entry until worker and callbacks finish;
   --  this does not imply that the Gateway is currently connected.

   function Send_Message
     (Self       : Client;
      Channel_ID : Adacord.Types.Snowflake;
      Content    : String) return Adacord.Types.Message;
   --  Send one text message, with automatic mentions disabled.
   --  @param Self Initialized client; Run need not be active.
   --  @param Channel_ID Destination channel identifier.
   --  @param Content Nonempty UTF-8 text of at most 2000 Unicode characters.
   --  @return The message object returned by Discord.
   --  @exception Adacord.Configuration_Error Invalid content or uninitialized client.
   --  @exception Adacord.Transport_Error HTTP transport failure.
   --  @exception Adacord.Authentication_Error Authentication or permissions rejected.
   --  @exception Adacord.Rate_Limit_Error Rate limit retry budget exhausted or invalid.
   --  @exception Adacord.Protocol_Error Unexpected status or malformed response.

   procedure Send_Message
     (Self       : Client;
      Channel_ID : Adacord.Types.Snowflake;
      Content    : String);
   --  Send text and discard the returned message object.
   --  Uses the same validation, mention policy and exceptions as the function.
   --  @param Self Initialized client.
   --  @param Channel_ID Destination channel identifier.
   --  @param Content Nonempty UTF-8 text, at most 2000 Unicode characters.

   function Register_Global_Command
     (Self           : Client;
      Application_ID : Adacord.Types.Snowflake;
      Name           : String;
      Description    : String) return Adacord.Types.Application_Command;
   --  Create or update a global chat-input command without options.
   --  Uses the same validation and exceptions as the REST operation.
   --  @param Self Initialized client.
   --  @param Application_ID Application identifier from READY, not a guild ID.
   --  @param Name Command name, 1 to 32 Unicode characters; Discord checks syntax.
   --  @param Description UTF-8 command description, 1 to 100 Unicode characters.
   --  @return The command object returned by Discord.

   procedure Register_Global_Command
     (Self           : Client;
      Application_ID : Adacord.Types.Snowflake;
      Name           : String;
      Description    : String);
   --  Create or update a global command and discard its returned object.
   --  Uses the same validation and exceptions as the function overload.
   --  @param Self Initialized client.
   --  @param Application_ID Application identifier, typically from READY.
   --  @param Name Command name, 1 to 32 Unicode characters.
   --  @param Description Command description, 1 to 100 Unicode characters.

   procedure Respond_To_Interaction
     (Self        : Client;
      Interaction : Adacord.Types.Interaction;
      Content     : String;
      Ephemeral   : Boolean := False);
   --  Send the initial text response to a message-capable interaction.
   --  Uses REST callback type 4; deferred replies and follow-ups are not supported.
   --  Uses the same validation and exceptions as the REST operation. The caller
   --  must ensure the interaction has not already been acknowledged.
   --  @param Self Initialized client.
   --  @param Interaction Received interaction, with its original ID and token.
   --  @param Content Nonempty UTF-8 response, at most 2000 Unicode characters.
   --  @param Ephemeral True to make the response visible only to the invoker.

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
