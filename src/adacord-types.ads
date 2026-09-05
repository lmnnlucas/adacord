with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Interfaces;

package Adacord.Types is
   --  Value types for Discord identifiers, users, messages and interactions.
   --  Text values contain UTF-8 bytes. Timestamps are preserved as received.
   --  Optional values distinguish absent/null fields from present empty strings.
   --  Construct snowflakes with Parse_Snowflake before reading or sending them;
   --  default-initialized identifier components are not valid IDs.

   subtype Text is Ada.Strings.Unbounded.Unbounded_String;
   --  UTF-8 bytes stored in an unbounded Ada string.

   type Snowflake is private;
   --  Opaque unsigned 64-bit Discord ID. Use Parse_Snowflake to construct it.

   function Parse_Snowflake (Value : String) return Snowflake;
   --  Parse a canonical unsigned decimal ID in the range 1 .. 2**64-1.
   --  Reject signs, whitespace, non-digits, leading zeroes, zero and overflow.
   --  @param Value Decimal string, including strings with non-1 lower bounds.
   --  @return Validated Discord snowflake.
   --  @exception Adacord.Invalid_Event Value is not a valid canonical snowflake.

   function Is_Valid (Value : String) return Boolean;
   --  Check a decimal representation without propagating Invalid_Event.
   --  @param Value Candidate snowflake text.
   --  @return True exactly when Parse_Snowflake accepts Value.

   function Image (Value : Snowflake) return String;
   --  Format an initialized identifier in canonical decimal notation.
   --  @param Value Snowflake previously constructed by Parse_Snowflake.
   --  @return Decimal digits without leading whitespace or zero padding.

   function To_Unsigned_64
     (Value : Snowflake) return Interfaces.Unsigned_64;
   --  Expose the numeric representation for interoperability.
   --  @param Value Initialized snowflake.
   --  @return Unsigned 64-bit identifier, with no truncation to a signed integer.

   type Optional_Snowflake (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : Snowflake;
         when False =>
            null;
      end case;
   end record;
   --  Optional identifier from an absent or nullable JSON field.
   --  @field Present True when Value may be accessed.
   --  @field Value Identifier, available only when Present=True.

   type Optional_Text (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : Text;
         when False =>
            null;
      end case;
   end record;
   --  Optional text; a present empty string differs from an absent field.
   --  @field Present True when Value may be accessed.
   --  @field Value UTF-8 text, available only when Present=True.

   type User is record
      ID            : Snowflake;
      Username      : Text;
      Discriminator : Text;
      Global_Name   : Optional_Text;
      Avatar        : Optional_Text;
      Is_Bot        : Boolean := False;
      Is_System     : Boolean := False;
   end record;
   --  Supported subset of a Discord user object.
   --  @field ID User snowflake.
   --  @field Username Account username, which is not a stable identifier.
   --  @field Discriminator Legacy discriminator; empty when absent, often "0".
   --  @field Global_Name Optional display name.
   --  @field Avatar Optional avatar hash; not a complete CDN URL.
   --  @field Is_Bot True for a bot account; defaults to False when omitted.
   --  @field Is_System True for a Discord system user; False when omitted.

   type Snowflake_List is private;
   --  Ordered, growable collection of snowflakes; initially empty.

   function Length (List : Snowflake_List) return Natural;
   --  Count the identifiers in a list.
   --  @param List Collection to inspect.
   --  @return Number of elements; zero for a newly created list.

   function Element
     (List  : Snowflake_List;
      Index : Positive) return Snowflake
   with Pre => Index <= Length (List);
   --  Read an element by its one-based position.
   --  @param List Collection to inspect.
   --  @param Index Position in 1 .. Length(List); checked by a precondition
   --  when assertions are enabled and by the underlying vector otherwise.
   --  @return Identifier at Index.
   --  @exception Ada.Assertions.Assertion_Error Precondition violated when enabled.
   --  @exception Constraint_Error Index is outside the vector bounds.

   procedure Append
     (List  : in out Snowflake_List;
      Value : Snowflake);
   --  Append an identifier while preserving insertion order; duplicates remain.
   --  @param List Collection to extend.
   --  @param Value Initialized snowflake to append.

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
   --  Supported subset of a Discord message, from REST or the Gateway.
   --  @field ID Message snowflake.
   --  @field Channel_ID Channel containing the message.
   --  @field Guild_ID Optional guild identifier; generally absent in direct messages.
   --  @field Author Parsed author identity.
   --  @field Content UTF-8 body; may be empty when content is unavailable.
   --  @field Timestamp Creation timestamp string, as sent by Discord.
   --  @field Edited_Timestamp Optional last-edit timestamp string.
   --  @field Is_TTS Whether text-to-speech was requested; False when omitted.
   --  @field Mentions_Everyone Whether the message mentions everyone/here.
   --  @field Is_Pinned Whether the message is pinned; False when omitted.

   type Interaction_Kind is
     (Ping_Interaction,
      Application_Command_Interaction,
      Message_Component_Interaction,
      Application_Command_Autocomplete_Interaction,
      Modal_Submit_Interaction,
      Unknown_Interaction);
   --  Recognized values of the interaction JSON type field.
   --  @enum Ping_Interaction Type 1, protocol ping.
   --  @enum Application_Command_Interaction Type 2, application command invocation.
   --  @enum Message_Component_Interaction Type 3, message component interaction.
   --  @enum Application_Command_Autocomplete_Interaction Type 4, autocomplete.
   --  @enum Modal_Submit_Interaction Type 5, modal submission.
   --  @enum Unknown_Interaction Any other nonnegative numeric type code.

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
   --  Supported interaction metadata and confidential callback credentials.
   --  Command fields are extracted only for Application_Command_Interaction.
   --  @field ID Interaction snowflake.
   --  @field Application_ID Application receiving this interaction.
   --  @field Kind Recognized interaction category, or Unknown_Interaction.
   --  @field Type_Code Original numeric type code, preserved for unknown kinds.
   --  @field Token Confidential callback token; never include it in logs.
   --  @field Version Interaction payload version from Discord.
   --  @field Guild_ID Optional guild in which the interaction was invoked.
   --  @field Channel_ID Optional channel in which the interaction was invoked.
   --  @field Command_ID Optional invoked command identifier.
   --  @field Command_Name Optional invoked command name.
   --  @field Command_Type Numeric command type; zero when not extracted.

   type Application_Command is record
      ID             : Snowflake;
      Application_ID : Snowflake;
      Guild_ID       : Optional_Snowflake;
      Name           : Text;
      Description    : Text;
      Command_Type   : Natural := 1;
   end record;
   --  Metadata returned when registering an application command.
   --  @field ID Command snowflake.
   --  @field Application_ID Owning application identifier.
   --  @field Guild_ID Absent for the global commands supported by this version.
   --  @field Name Registered command name.
   --  @field Description Registered command description.
   --  @field Command_Type Discord command type; registration requests type 1.

   type Ready is record
      Version            : Natural;
      Current_User       : User;
      Application_ID     : Snowflake;
      Session_ID         : Text;
      Resume_Gateway_URL : Text;
      Guilds             : Snowflake_List;
   end record;
   --  Initial Gateway READY payload for a newly identified session.
   --  @field Version Gateway API version reported by Discord.
   --  @field Current_User Bot account identity.
   --  @field Application_ID Application identifier for command registration.
   --  @field Session_ID Resumable session identifier; treat as confidential.
   --  @field Resume_Gateway_URL Secure endpoint used when resuming this session.
   --  @field Guilds Ordered initial guild identifiers; no guild details are stored.

private

   type Snowflake is new Interfaces.Unsigned_64;

   package Snowflake_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Snowflake);

   type Snowflake_List is record
      Values : Snowflake_Vectors.Vector;
   end record;

end Adacord.Types;
