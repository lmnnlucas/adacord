with Adacord_Config;

package Adacord is
   --  Discord bot library: version information and shared exceptions.
   --  Start with `Adacord.Clients` for callbacks and `Adacord.Config` for secrets.
   --  All network operations are synchronous at the REST layer; the high-level
   --  client runs Gateway I/O in a separate Ada task.

   Version : constant String := Adacord_Config.Crate_Version;
   --  Version of this library, supplied by the Alire crate configuration.

   Configuration_Error : exception;
   --  Invalid local configuration, input or client lifecycle operation.
   Transport_Error     : exception;
   --  HTTP transport failure; details omit tokens and request headers.
   Protocol_Error      : exception;
   --  Unexpected HTTP status or malformed Discord protocol response.
   Authentication_Error : exception;
   --  HTTP 401 or 403: rejected authentication or insufficient permissions.
   Rate_Limit_Error    : exception;
   --  HTTP 429 retries exhausted, or retry_after outside the accepted range.
   Invalid_Event       : exception;
   --  Missing, incorrectly typed or out-of-range event data or snowflake.

end Adacord;
