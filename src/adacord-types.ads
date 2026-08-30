with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Interfaces;

package Adacord.Types is

   subtype Text is Ada.Strings.Unbounded.Unbounded_String;

   type Snowflake is private;

   function Parse_Snowflake (Value : String) return Snowflake;
   --  Parse the canonical, unsigned decimal representation used by Discord.
   --  Invalid or zero values raise Adacord.Invalid_Event.

   function Is_Valid (Value : String) return Boolean;
   --  Return whether Value is accepted by Parse_Snowflake.

   function Image (Value : Snowflake) return String;
   --  Return a canonical decimal representation without leading whitespace.

   function To_Unsigned_64
     (Value : Snowflake) return Interfaces.Unsigned_64;

   type Optional_Snowflake (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : Snowflake;
         when False =>
            null;
      end case;
   end record;

   type Optional_Text (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : Text;
         when False =>
            null;
      end case;
   end record;

   type User is record
      ID            : Snowflake;
      Username      : Text;
      Discriminator : Text;
      Global_Name   : Optional_Text;
      Avatar        : Optional_Text;
      Is_Bot        : Boolean := False;
      Is_System     : Boolean := False;
   end record;

   type Snowflake_List is private;

   function Length (List : Snowflake_List) return Natural;

   function Element
     (List  : Snowflake_List;
      Index : Positive) return Snowflake
   with Pre => Index <= Length (List);

   procedure Append
     (List  : in out Snowflake_List;
      Value : Snowflake);

   type Message is record
      ID                : Snowflake;
      Channel_ID        : Snowflake;
      Guild_ID          : Optional_Snowflake;
      Author            : User;
      Content           : Text;
      Timestamp         : Text;
      Edited_Timestamp  : Optional_Text;
      Is_TTS            : Boolean := False;
      Mentions_Everyone : Boolean := False;
      Is_Pinned         : Boolean := False;
   end record;

   type Interaction_Kind is
     (Ping_Interaction,
      Application_Command_Interaction,
      Message_Component_Interaction,
      Application_Command_Autocomplete_Interaction,
      Modal_Submit_Interaction,
      Unknown_Interaction);

   type Interaction is record
      ID             : Snowflake;
      Application_ID : Snowflake;
      Kind           : Interaction_Kind := Unknown_Interaction;
      Type_Code      : Natural := 0;
      Token          : Text;
      Version        : Natural := 1;
      Guild_ID       : Optional_Snowflake;
      Channel_ID     : Optional_Snowflake;
      Command_ID     : Optional_Snowflake;
      Command_Name   : Optional_Text;
      Command_Type   : Natural := 0;
   end record;

   type Application_Command is record
      ID             : Snowflake;
      Application_ID : Snowflake;
      Guild_ID       : Optional_Snowflake;
      Name           : Text;
      Description    : Text;
      Command_Type   : Natural := 1;
   end record;

   type Ready is record
      Version            : Natural;
      Current_User       : User;
      Application_ID     : Snowflake;
      Session_ID         : Text;
      Resume_Gateway_URL : Text;
      Guilds             : Snowflake_List;
   end record;

private

   type Snowflake is new Interfaces.Unsigned_64;

   package Snowflake_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Snowflake);

   type Snowflake_List is record
      Values : Snowflake_Vectors.Vector;
   end record;

end Adacord.Types;
