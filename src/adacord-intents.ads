package Adacord.Intents is
   --  Gateway event subscriptions represented as a 64-bit bitmask.
   --  Combine flags with Ada's `or` operator and inspect subsets with Contains.
   --  Privileged intents also require configuration in the Discord developer
   --  portal. Selecting an intent does not add a corresponding event parser:
   --  Adacord currently dispatches READY, MESSAGE_CREATE and INTERACTION_CREATE.

   type Intent_Set is mod 2 ** 64;
   for Intent_Set'Size use 64;
   --  Bitmask of Gateway intents; use the named flags instead of raw values.

   None                          : constant Intent_Set := 0;
   --  No optional event subscriptions.
   Guilds                        : constant Intent_Set := 2 ** 0;
   --  Guild, channel, thread and role lifecycle events.
   Guild_Members                 : constant Intent_Set := 2 ** 1;
   --  Guild member events; privileged.
   Guild_Moderation              : constant Intent_Set := 2 ** 2;
   --  Guild moderation and ban events.
   Guild_Expressions             : constant Intent_Set := 2 ** 3;
   --  Guild emoji, sticker and soundboard changes.
   Guild_Integrations            : constant Intent_Set := 2 ** 4;
   --  Guild integration changes.
   Guild_Webhooks                : constant Intent_Set := 2 ** 5;
   --  Guild webhook changes.
   Guild_Invites                 : constant Intent_Set := 2 ** 6;
   --  Guild invitation changes.
   Guild_Voice_States            : constant Intent_Set := 2 ** 7;
   --  Voice state updates; does not implement voice transport.
   Guild_Presences               : constant Intent_Set := 2 ** 8;
   --  Guild presence updates; privileged.
   Guild_Messages                : constant Intent_Set := 2 ** 9;
   --  Message events in guild channels.
   Guild_Message_Reactions       : constant Intent_Set := 2 ** 10;
   --  Reaction events in guild channels.
   Guild_Message_Typing          : constant Intent_Set := 2 ** 11;
   --  Typing events in guild channels.
   Direct_Messages               : constant Intent_Set := 2 ** 12;
   --  Message events in direct messages.
   Direct_Message_Reactions      : constant Intent_Set := 2 ** 13;
   --  Reaction events in direct messages.
   Direct_Message_Typing         : constant Intent_Set := 2 ** 14;
   --  Typing events in direct messages.
   Message_Content               : constant Intent_Set := 2 ** 15;
   --  Access to restricted message-content fields; privileged.
   Guild_Scheduled_Events        : constant Intent_Set := 2 ** 16;
   --  Guild scheduled-event lifecycle and subscriptions.
   Auto_Moderation_Configuration : constant Intent_Set := 2 ** 20;
   --  Auto-moderation rule configuration changes.
   Auto_Moderation_Execution     : constant Intent_Set := 2 ** 21;
   --  Auto-moderation action execution events.
   Guild_Message_Polls           : constant Intent_Set := 2 ** 24;
   --  Poll vote events in guild channels.
   Direct_Message_Polls          : constant Intent_Set := 2 ** 25;
   --  Poll vote events in direct messages.

   Privileged : constant Intent_Set :=
     Guild_Members or Guild_Presences or Message_Content;
   --  All privileged flags known to this version.

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
   --  All non-privileged flags defined in this package.

   All_Intents : constant Intent_Set := All_Non_Privileged or Privileged;
   --  Union of privileged and non-privileged flags defined here.

   Message_Bot : constant Intent_Set :=
     Guilds or Guild_Messages or Direct_Messages or Message_Content;
   --  Convenient set for bots that read message text in guilds and DMs.
   --  Message_Content is privileged and must also be enabled in Discord's
   --  developer portal.

   function Contains
     (Values   : Intent_Set;
      Required : Intent_Set) return Boolean is
     ((Values and Required) = Required);
   --  Test whether every required flag is present.
   --  @param Values Available intent flags.
   --  @param Required Subset to test; None is contained in every mask.
   --  @return True when (Values and Required) equals Required.

end Adacord.Intents;
