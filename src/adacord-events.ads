with GNATCOLL.JSON;

with Adacord.Types;

package Adacord.Events is
   --  Decode Discord JSON objects into the supported Ada event records.
   --  Pass the Gateway envelope's `d` field, never the whole envelope. Unknown
   --  JSON fields are ignored. Known fields enforce their documented JSON types;
   --  invalid snowflakes, missing required fields and numeric range failures
   --  raise Adacord.Invalid_Event. Optional null and absent values are equivalent.
   --  Timestamp strings are preserved without calendar validation.

   function Parse_Ready
     (Value : GNATCOLL.JSON.JSON_Value) return Adacord.Types.Ready;
   --  Decode initial session and bot metadata.
   --  @param Value READY event data object, including user, application and guilds.
   --  @return Session ID, resume URL, bot identity and initial guild identifiers.
   --  @exception Adacord.Invalid_Event Missing or incorrectly typed required data.

   function Parse_Message
     (Value : GNATCOLL.JSON.JSON_Value) return Adacord.Types.Message;
   --  Decode a Message object from REST or a Gateway dispatch.
   --  @param Value Raw message JSON with required author, content and timestamp.
   --  @return Typed message; optional guild and edit timestamp may be absent.
   --  @exception Adacord.Invalid_Event Invalid required or optional message fields.

   function Parse_Message_Create
     (Value : GNATCOLL.JSON.JSON_Value) return Adacord.Types.Message;
   --  Decode MESSAGE_CREATE using the same parser as Parse_Message.
   --  @param Value MESSAGE_CREATE data object, without the Gateway envelope.
   --  @return Typed newly created message.
   --  @exception Adacord.Invalid_Event Missing or malformed message data.

   function Parse_Interaction_Create
     (Value : GNATCOLL.JSON.JSON_Value) return Adacord.Types.Interaction;
   --  Decode an interaction while retaining unknown future type codes.
   --  Command_ID, Command_Name and Command_Type are populated only for an
   --  Application_Command_Interaction. Unknown kinds retain the common fields.
   --  @param Value INTERACTION_CREATE data object, without its Gateway envelope.
   --  @return Typed interaction, including confidential callback credentials.
   --  @exception Adacord.Invalid_Event Invalid common or required command fields.

end Adacord.Events;
