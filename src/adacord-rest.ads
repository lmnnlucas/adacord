with Ada.Strings.Unbounded;

with Adacord.Types;

package Adacord.REST is

   type Client is tagged limited private;

   procedure Initialize
     (Self       : in out Client;
      Token      : String;
      API_Base   : String := "https://discord.com/api/v10";
      User_Agent : String :=
        "DiscordBot (https://github.com/adacord/adacord, 0.1.0)");

   type Gateway_Info is record
      URL                      : Ada.Strings.Unbounded.Unbounded_String;
      Recommended_Shards       : Positive := 1;
      Remaining_Sessions       : Natural := 0;
      Reset_After_Milliseconds : Natural := 0;
      Max_Concurrency          : Natural := 0;
   end record;

   function Get_Gateway_Info (Self : Client) return Gateway_Info;

   function Send_Message
     (Self       : Client;
      Channel_ID : Adacord.Types.Snowflake;
      Content    : String) return Adacord.Types.Message;

   function Register_Global_Command
     (Self           : Client;
      Application_ID : Adacord.Types.Snowflake;
      Name           : String;
      Description    : String) return Adacord.Types.Application_Command;

   procedure Respond_To_Interaction
     (Self        : Client;
      Interaction : Adacord.Types.Interaction;
      Content     : String;
      Ephemeral   : Boolean := False);

private

   type Client is tagged limited record
      Token       : Ada.Strings.Unbounded.Unbounded_String;
      API_Base    : Ada.Strings.Unbounded.Unbounded_String;
      User_Agent  : Ada.Strings.Unbounded.Unbounded_String;
      Initialized : Boolean := False;
   end record;

end Adacord.REST;
