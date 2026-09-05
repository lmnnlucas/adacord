with Ada.Strings.Unbounded;

with Adacord.Types;

package Adacord.REST is
   --  Synchronous Discord API v10 HTTP operations.
   --  HTTP 429 is retried at most twice, using retry_after up to 60 seconds per
   --  wait. Longer, negative or malformed delays raise Rate_Limit_Error. HTTP
   --  401/403 raise Authentication_Error; other unexpected statuses and invalid
   --  response objects raise Protocol_Error. Transport exception text is hidden.
   --  POSTs are not automatically replayed after an ambiguous transport failure.
   --  Automatic mentions are disabled for all outgoing message content.

   type Client is tagged limited private;
   --  Stores credentials and endpoint configuration. Initialize before use.
   --  Serialize initialization with all operations using this instance.

   procedure Initialize
     (Self       : in out Client;
      Token      : String;
      API_Base   : String := "https://discord.com/api/v10";
      User_Agent : String :=
        "DiscordBot (https://github.com/adacord/adacord, 0.1.0)");
   --  Set credentials and configure certificate verification for HTTPS.
   --  This does not send a request. Set ADACORD_CA_BUNDLE before the first HTTPS
   --  initialization when using a custom CA file; AWS TLS configuration is global.
   --  @param Self Client to configure.
   --  @param Token Nonempty printable ASCII token, without spaces or "Bot ".
   --  @param API_Base Absolute HTTP(S) URL without credentials, query or fragment.
   --  Use HTTPS in production; HTTP permits local test servers.
   --  @param User_Agent Nonempty printable ASCII User-Agent; spaces are accepted.
   --  @exception Adacord.Configuration_Error Invalid input or TLS configuration.

   type Gateway_Info is record
      URL                      : Ada.Strings.Unbounded.Unbounded_String;
      Recommended_Shards       : Positive := 1;
      Remaining_Sessions       : Natural := 0;
      Reset_After_Milliseconds : Natural := 0;
      Max_Concurrency          : Natural := 0;
   end record;
   --  Snapshot returned by /gateway/bot; not a live quota tracker.
   --  @field URL Secure Gateway WebSocket endpoint.
   --  @field Recommended_Shards Recommended number of shards; minimum one.
   --  @field Remaining_Sessions Remaining new identification attempts.
   --  @field Reset_After_Milliseconds Time until the identification quota resets.
   --  @field Max_Concurrency Permitted concurrent identification buckets.

   function Get_Gateway_Info (Self : Client) return Gateway_Info;
   --  Fetch /gateway/bot using the bot Authorization header.
   --  @param Self Initialized REST client.
   --  @return Gateway URL, shard recommendation and identification quota snapshot.
   --  @exception Adacord.Configuration_Error Client is not initialized.
   --  @exception Adacord.Transport_Error HTTP transport failure.
   --  @exception Adacord.Authentication_Error HTTP 401 or 403.
   --  @exception Adacord.Rate_Limit_Error Rate limit could not be retried safely.
   --  @exception Adacord.Protocol_Error Unexpected status or malformed JSON fields.

   function Send_Message
     (Self       : Client;
      Channel_ID : Adacord.Types.Snowflake;
      Content    : String) return Adacord.Types.Message;
   --  Create a channel message with an empty allowed_mentions.parse list.
   --  The operation does not require an active Gateway connection.
   --  @param Self Initialized REST client.
   --  @param Channel_ID Destination channel snowflake.
   --  @param Content Nonempty UTF-8 text of at most 2000 Unicode characters.
   --  @return Parsed Discord message response.
   --  @exception Adacord.Configuration_Error Invalid content or uninitialized client.
   --  @exception Adacord.Transport_Error HTTP transport failure.
   --  @exception Adacord.Authentication_Error Authentication or permissions rejected.
   --  @exception Adacord.Rate_Limit_Error Rate limit retry budget exhausted or invalid.
   --  @exception Adacord.Protocol_Error Unexpected status or malformed response.

   function Register_Global_Command
     (Self           : Client;
      Application_ID : Adacord.Types.Snowflake;
      Name           : String;
      Description    : String) return Adacord.Types.Application_Command;
   --  Create or update a global chat-input command (type 1), without options.
   --  Discord validates command-name syntax; local checks cover UTF-8 and length.
   --  @param Self Initialized REST client.
   --  @param Application_ID Application snowflake, typically obtained from READY.
   --  @param Name Command name, 1 to 32 Unicode characters.
   --  @param Description Command description, 1 to 100 Unicode characters.
   --  @return Command metadata returned by Discord; Guild_ID is absent.
   --  @exception Adacord.Configuration_Error Invalid lengths, UTF-8 or client state.
   --  @exception Adacord.Transport_Error HTTP transport failure.
   --  @exception Adacord.Authentication_Error Authentication or permissions rejected.
   --  @exception Adacord.Rate_Limit_Error Rate limit retry budget exhausted or invalid.
   --  @exception Adacord.Protocol_Error Unexpected status or malformed response.

   procedure Respond_To_Interaction
     (Self        : Client;
      Interaction : Adacord.Types.Interaction;
      Content     : String;
      Ephemeral   : Boolean := False);
   --  Send a type-4 initial callback with automatic mentions disabled.
   --  The interaction token is encoded as one URL segment; no bot Authorization
   --  header is sent. Call only for an interaction supporting a text response,
   --  within Discord's initial-response deadline and before acknowledging it.
   --  Deferred responses and follow-ups are not implemented.
   --  @param Self Initialized REST client.
   --  @param Interaction Received ID and nonempty confidential response token.
   --  @param Content Nonempty UTF-8 text, at most 2000 Unicode characters.
   --  @param Ephemeral True to set the ephemeral response flag (64).
   --  @exception Adacord.Configuration_Error Invalid content, token or client state.
   --  @exception Adacord.Transport_Error HTTP transport failure.
   --  @exception Adacord.Authentication_Error HTTP 401 or 403.
   --  @exception Adacord.Rate_Limit_Error Rate limit retry budget exhausted or invalid.
   --  @exception Adacord.Protocol_Error Unexpected HTTP response status.

private

   type Client is tagged limited record
      Token       : Ada.Strings.Unbounded.Unbounded_String;
      API_Base    : Ada.Strings.Unbounded.Unbounded_String;
      User_Agent  : Ada.Strings.Unbounded.Unbounded_String;
      Initialized : Boolean := False;
   end record;

end Adacord.REST;
