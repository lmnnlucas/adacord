with Adacord_Config;

package Adacord is

   Version : constant String := Adacord_Config.Crate_Version;

   Configuration_Error : exception;
   Transport_Error     : exception;
   Protocol_Error      : exception;
   Authentication_Error : exception;
   Rate_Limit_Error    : exception;
   Invalid_Event       : exception;

end Adacord;
