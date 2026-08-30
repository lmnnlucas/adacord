with GNATCOLL.JSON;

with Adacord.Types;

package Adacord.Events is

   function Parse_Ready
     (Value : GNATCOLL.JSON.JSON_Value) return Adacord.Types.Ready;
   --  Value is the READY event data object (the gateway envelope's `d`
   --  field), not the complete gateway envelope.

   function Parse_Message
     (Value : GNATCOLL.JSON.JSON_Value) return Adacord.Types.Message;
   --  Value is a raw Discord Message object. This accepts both a REST
   --  response object and the `d` field of MESSAGE_CREATE.

   function Parse_Message_Create
     (Value : GNATCOLL.JSON.JSON_Value) return Adacord.Types.Message;
   --  Value is the MESSAGE_CREATE event data object. This is the same shape
   --  as Parse_Message and never expects the complete gateway envelope.

   function Parse_Interaction_Create
     (Value : GNATCOLL.JSON.JSON_Value) return Adacord.Types.Interaction;
   --  Value is the INTERACTION_CREATE event data object. Application command
   --  interactions expose Command_ID, Command_Name, and Command_Type.

end Adacord.Events;
