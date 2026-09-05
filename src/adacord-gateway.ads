with Adacord.Intents;
with Adacord.Types;

private package Adacord.Gateway is
   --  Internal Gateway connection and session state machine.
   --  Handles identification, heartbeats, reconnects and resuming. Sink callbacks
   --  execute on the network task and must not perform blocking application work;
   --  Adacord.Clients supplies a nonblocking queue adapter.

   type Event_Sink is limited interface;
   --  Internal receiver for decoded events and cooperative shutdown checks.

   procedure Handle_Ready
     (Sink  : in out Event_Sink;
      Event : Adacord.Types.Ready) is abstract;
   --  Accept a decoded Ready without blocking the Gateway worker.
   --  @param Sink Nonblocking event receiver.
   --  @param Event Parsed event value to deliver.

   procedure Handle_Message_Create
     (Sink  : in out Event_Sink;
      Event : Adacord.Types.Message) is abstract;
   --  Accept a decoded Message without blocking the Gateway worker.
   --  @param Sink Nonblocking event receiver.
   --  @param Event Parsed event value to deliver.

   procedure Handle_Interaction_Create
     (Sink  : in out Event_Sink;
      Event : Adacord.Types.Interaction) is abstract;
   --  Accept a decoded Interaction without blocking the Gateway worker.
   --  @param Sink Nonblocking event receiver.
   --  @param Event Parsed event value to deliver.

   procedure Handle_Error
     (Sink    : in out Event_Sink;
      Details : String;
      Fatal   : Boolean) is abstract;
   --  Report an internal Gateway diagnostic without exposing credentials.
   --  @param Sink Nonblocking event receiver.
   --  @param Details Library-generated diagnostic.
   --  @param Fatal True when the connection loop cannot continue.

   function Stop_Requested (Sink : Event_Sink) return Boolean is abstract;
   --  Poll the cooperative shutdown flag.
   --  @param Sink Event receiver owning the shutdown state.
   --  @return True when the Gateway should leave its loop.

   procedure Run
     (Token       : String;
      Intents     : Adacord.Intents.Intent_Set;
      Initial_URL : String;
      Sink        : in out Event_Sink'Class);
   --  Run the reconnecting Gateway state machine in the current task.
   --  Returns after Stop_Requested or a fatal Gateway close; network calls may
   --  block, so no maximum shutdown delay is guaranteed.
   --  @param Token Nonempty bot credential, used for IDENTIFY and RESUME.
   --  @param Intents Requested event mask.
   --  @param Initial_URL Secure wss:// endpoint from the REST gateway lookup.
   --  @param Sink Nonblocking callbacks and shutdown flag.
   --  @exception Adacord.Configuration_Error Empty credentials or endpoint.

end Adacord.Gateway;
