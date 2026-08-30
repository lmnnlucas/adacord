package Adacord.Intents is

   type Intent_Set is mod 2 ** 64;
   for Intent_Set'Size use 64;

   None                          : constant Intent_Set := 0;
   Guilds                        : constant Intent_Set := 2 ** 0;
   Guild_Members                 : constant Intent_Set := 2 ** 1;
   Guild_Moderation              : constant Intent_Set := 2 ** 2;
   Guild_Expressions             : constant Intent_Set := 2 ** 3;
   Guild_Integrations            : constant Intent_Set := 2 ** 4;
   Guild_Webhooks                : constant Intent_Set := 2 ** 5;
   Guild_Invites                 : constant Intent_Set := 2 ** 6;
   Guild_Voice_States            : constant Intent_Set := 2 ** 7;
   Guild_Presences               : constant Intent_Set := 2 ** 8;
   Guild_Messages                : constant Intent_Set := 2 ** 9;
   Guild_Message_Reactions       : constant Intent_Set := 2 ** 10;
   Guild_Message_Typing          : constant Intent_Set := 2 ** 11;
   Direct_Messages               : constant Intent_Set := 2 ** 12;
   Direct_Message_Reactions      : constant Intent_Set := 2 ** 13;
   Direct_Message_Typing         : constant Intent_Set := 2 ** 14;
   Message_Content               : constant Intent_Set := 2 ** 15;
   Guild_Scheduled_Events        : constant Intent_Set := 2 ** 16;
   Auto_Moderation_Configuration : constant Intent_Set := 2 ** 20;
   Auto_Moderation_Execution     : constant Intent_Set := 2 ** 21;
   Guild_Message_Polls           : constant Intent_Set := 2 ** 24;
   Direct_Message_Polls          : constant Intent_Set := 2 ** 25;

   Privileged : constant Intent_Set :=
     Guild_Members or Guild_Presences or Message_Content;

   All_Non_Privileged : constant Intent_Set :=
     Guilds
     or Guild_Moderation
     or Guild_Expressions
     or Guild_Integrations
     or Guild_Webhooks
     or Guild_Invites
     or Guild_Voice_States
     or Guild_Messages
     or Guild_Message_Reactions
     or Guild_Message_Typing
     or Direct_Messages
     or Direct_Message_Reactions
     or Direct_Message_Typing
     or Guild_Scheduled_Events
     or Auto_Moderation_Configuration
     or Auto_Moderation_Execution
     or Guild_Message_Polls
     or Direct_Message_Polls;

   All_Intents : constant Intent_Set := All_Non_Privileged or Privileged;

   Message_Bot : constant Intent_Set :=
     Guilds or Guild_Messages or Direct_Messages or Message_Content;
   --  Convenient set for bots that read message text in guilds and DMs.
   --  Message_Content is privileged and must also be enabled in Discord's
   --  developer portal.

   function Contains
     (Values   : Intent_Set;
      Required : Intent_Set) return Boolean is
     ((Values and Required) = Required);

end Adacord.Intents;
