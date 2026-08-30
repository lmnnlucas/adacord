with Adacord.Intents;
with Adacord.Types;

private package Adacord.Gateway is

   type Event_Sink is limited interface;

   procedure Handle_Ready
     (Sink  : in out Event_Sink;
      Event : Adacord.Types.Ready) is abstract;

   procedure Handle_Message_Create
     (Sink  : in out Event_Sink;
      Event : Adacord.Types.Message) is abstract;

   procedure Handle_Interaction_Create
     (Sink  : in out Event_Sink;
      Event : Adacord.Types.Interaction) is abstract;

   procedure Handle_Error
     (Sink    : in out Event_Sink;
      Details : String;
      Fatal   : Boolean) is abstract;

   function Stop_Requested (Sink : Event_Sink) return Boolean is abstract;

   procedure Run
     (Token       : String;
      Intents     : Adacord.Intents.Intent_Set;
      Initial_URL : String;
      Sink        : in out Event_Sink'Class);

end Adacord.Gateway;
