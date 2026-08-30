with Ada.Containers.Vectors;

with Adacord.Gateway;

package body Adacord.Clients is

   use Ada.Strings.Unbounded;

   type Queue_Item_Kind is
     (Ready_Item,
      Message_Create_Item,
      Interaction_Create_Item,
      Error_Item,
      Finished_Item);

   type Queue_Item (Kind : Queue_Item_Kind := Finished_Item) is record
      case Kind is
         when Ready_Item =>
            Ready_Event : Adacord.Types.Ready;
         when Message_Create_Item =>
            Message_Event : Adacord.Types.Message;
         when Interaction_Create_Item =>
            Interaction_Event : Adacord.Types.Interaction;
         when Error_Item =>
            Details : Unbounded_String;
            Fatal   : Boolean := False;
         when Finished_Item =>
            null;
      end case;
   end record;

   package Item_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Queue_Item);

   protected type Event_Queue is
      procedure Push (Item : Queue_Item);
      entry Pop (Item : out Queue_Item);
   private
      Items : Item_Vectors.Vector;
      Count : Natural := 0;
   end Event_Queue;

   type Queue_Sink
     (Queue : not null access Event_Queue;
      Life  : not null access Lifecycle)
   is new Adacord.Gateway.Event_Sink with null record;

   overriding procedure Handle_Ready
     (Sink  : in out Queue_Sink;
      Event : Adacord.Types.Ready);

   overriding procedure Handle_Message_Create
     (Sink  : in out Queue_Sink;
      Event : Adacord.Types.Message);

   overriding procedure Handle_Interaction_Create
     (Sink  : in out Queue_Sink;
      Event : Adacord.Types.Interaction);

   overriding procedure Handle_Error
     (Sink    : in out Queue_Sink;
      Details : String;
      Fatal   : Boolean);

   overriding function Stop_Requested
     (Sink : Queue_Sink) return Boolean;

   ----------------
   -- Lifecycle --
   ----------------

   protected body Lifecycle is

      procedure Start is
      begin
         if Is_Active then
            raise Adacord.Configuration_Error with
              "the Discord client is already running";
         end if;

         Is_Active := True;
         Must_Stop := False;
      end Start;

      procedure Request_Stop is
      begin
         Must_Stop := True;
      end Request_Stop;

      procedure Finish is
      begin
         Is_Active := False;
         Must_Stop := True;
      end Finish;

      function Running return Boolean is
      begin
         return Is_Active;
      end Running;

      function Stopping return Boolean is
      begin
         return Must_Stop;
      end Stopping;

   end Lifecycle;

   -----------------
   -- Event_Queue --
   -----------------

   protected body Event_Queue is

      procedure Push (Item : Queue_Item) is
      begin
         Items.Append (Item);
         Count := Count + 1;
      end Push;

      entry Pop (Item : out Queue_Item) when Count > 0 is
      begin
         Item := Items.First_Element;
         Items.Delete_First;
         Count := Count - 1;
      end Pop;

   end Event_Queue;

   ------------------
   -- Handle_Ready --
   ------------------

   overriding procedure Handle_Ready
     (Sink  : in out Queue_Sink;
      Event : Adacord.Types.Ready) is
   begin
      Sink.Queue.Push ((Kind => Ready_Item, Ready_Event => Event));
   end Handle_Ready;

   ---------------------------
   -- Handle_Message_Create --
   ---------------------------

   overriding procedure Handle_Message_Create
     (Sink  : in out Queue_Sink;
      Event : Adacord.Types.Message) is
   begin
      Sink.Queue.Push
        ((Kind => Message_Create_Item, Message_Event => Event));
   end Handle_Message_Create;

   -------------------------------
   -- Handle_Interaction_Create --
   -------------------------------

   overriding procedure Handle_Interaction_Create
     (Sink  : in out Queue_Sink;
      Event : Adacord.Types.Interaction) is
   begin
      Sink.Queue.Push
        ((Kind              => Interaction_Create_Item,
          Interaction_Event => Event));
   end Handle_Interaction_Create;

   ------------------
   -- Handle_Error --
   ------------------

   overriding procedure Handle_Error
     (Sink    : in out Queue_Sink;
      Details : String;
      Fatal   : Boolean) is
   begin
      Sink.Queue.Push
        ((Kind    => Error_Item,
          Details => To_Unbounded_String (Details),
          Fatal   => Fatal));
   end Handle_Error;

   --------------------
   -- Stop_Requested --
   --------------------

   overriding function Stop_Requested
     (Sink : Queue_Sink) return Boolean is
   begin
      return Sink.Life.Stopping;
   end Stop_Requested;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (Self            : in out Client;
      Token           : String;
      Gateway_Intents : Adacord.Intents.Intent_Set :=
        Adacord.Intents.Guilds) is
   begin
      if Self.Life.Running then
         raise Adacord.Configuration_Error with
           "a running Discord client cannot be reinitialized";
      end if;

      Adacord.REST.Initialize (Self.HTTP, Token);
      Self.Token := To_Unbounded_String (Token);
      Self.Gateway_Intents := Gateway_Intents;
      Self.Initialized := True;
   end Initialize;

   ---------
   -- Run --
   ---------

   procedure Run
     (Self    : in out Client;
      Handler : in out Event_Handler'Class)
   is

      procedure Report_Callback_Failure;

      procedure Report_Callback_Failure is
      begin
         begin
            Handler.On_Error
              (Self,
               "an Adacord event callback raised an exception",
               Fatal => False);
         exception
            when others =>
               null;
         end;
      end Report_Callback_Failure;

   begin
      if not Self.Initialized then
         raise Adacord.Configuration_Error with
           "the Discord client must be initialized before Run";
      end if;

      Self.Life.Start;

      declare
         Gateway_Info : constant Adacord.REST.Gateway_Info :=
           Self.HTTP.Get_Gateway_Info;
         Queue : aliased Event_Queue;
         Sink  : aliased Queue_Sink
           (Queue => Queue'Access,
            Life  => Self.Life'Access);

         task Worker;

         task body Worker is
         begin
            if Gateway_Info.Remaining_Sessions = 0 then
               Sink.Handle_Error
                 ("Discord has no remaining session starts; retry after"
                  & Natural'Image
                    (Gateway_Info.Reset_After_Milliseconds)
                  & " milliseconds",
                  Fatal => True);
            else
               begin
                  Adacord.Gateway.Run
                    (Token       => To_String (Self.Token),
                     Intents     => Self.Gateway_Intents,
                     Initial_URL => To_String (Gateway_Info.URL),
                     Sink        => Sink);
               exception
                  when others =>
                     Sink.Handle_Error
                       ("the Discord gateway worker stopped unexpectedly",
                        Fatal => True);
               end;
            end if;

            Self.Life.Finish;
            Queue.Push ((Kind => Finished_Item));
         end Worker;

         Item : Queue_Item;
      begin
         loop
            Queue.Pop (Item);

            case Item.Kind is
               when Ready_Item =>
                  begin
                     Handler.On_Ready (Self, Item.Ready_Event);
                  exception
                     when others =>
                        Report_Callback_Failure;
                  end;

               when Message_Create_Item =>
                  begin
                     Handler.On_Message_Create
                       (Self, Item.Message_Event);
                  exception
                     when others =>
                        Report_Callback_Failure;
                  end;

               when Interaction_Create_Item =>
                  begin
                     Handler.On_Interaction_Create
                       (Self, Item.Interaction_Event);
                  exception
                     when others =>
                        Report_Callback_Failure;
                  end;

               when Error_Item =>
                  begin
                     Handler.On_Error
                       (Self,
                        To_String (Item.Details),
                        Item.Fatal);
                  exception
                     when others =>
                        null;
                  end;

               when Finished_Item =>
                  exit;
            end case;
         end loop;
      end;
   exception
      when others =>
         Self.Life.Finish;
         raise;
   end Run;

   ----------
   -- Stop --
   ----------

   procedure Stop (Self : in out Client) is
   begin
      Self.Life.Request_Stop;
   end Stop;

   ----------------
   -- Is_Running --
   ----------------

   function Is_Running (Self : Client) return Boolean is
   begin
      return Self.Life.Running;
   end Is_Running;

   ------------------
   -- Send_Message --
   ------------------

   function Send_Message
     (Self       : Client;
      Channel_ID : Adacord.Types.Snowflake;
      Content    : String) return Adacord.Types.Message is
   begin
      if not Self.Initialized then
         raise Adacord.Configuration_Error with
           "the Discord client must be initialized before sending";
      end if;

      return Self.HTTP.Send_Message (Channel_ID, Content);
   end Send_Message;

   ------------------
   -- Send_Message --
   ------------------

   procedure Send_Message
     (Self       : Client;
      Channel_ID : Adacord.Types.Snowflake;
      Content    : String)
   is
      Ignored : constant Adacord.Types.Message :=
        Send_Message (Self, Channel_ID, Content);
      pragma Unreferenced (Ignored);
   begin
      null;
   end Send_Message;

   -----------------------------
   -- Register_Global_Command --
   -----------------------------

   function Register_Global_Command
     (Self           : Client;
      Application_ID : Adacord.Types.Snowflake;
      Name           : String;
      Description    : String) return Adacord.Types.Application_Command is
   begin
      if not Self.Initialized then
         raise Adacord.Configuration_Error with
           "the Discord client must be initialized before registering "
           & "commands";
      end if;

      return Self.HTTP.Register_Global_Command
        (Application_ID, Name, Description);
   end Register_Global_Command;

   -----------------------------
   -- Register_Global_Command --
   -----------------------------

   procedure Register_Global_Command
     (Self           : Client;
      Application_ID : Adacord.Types.Snowflake;
      Name           : String;
      Description    : String)
   is
      Ignored : constant Adacord.Types.Application_Command :=
        Register_Global_Command
          (Self, Application_ID, Name, Description);
      pragma Unreferenced (Ignored);
   begin
      null;
   end Register_Global_Command;

   ----------------------------
   -- Respond_To_Interaction --
   ----------------------------

   procedure Respond_To_Interaction
     (Self        : Client;
      Interaction : Adacord.Types.Interaction;
      Content     : String;
      Ephemeral   : Boolean := False) is
   begin
      if not Self.Initialized then
         raise Adacord.Configuration_Error with
           "the Discord client must be initialized before responding";
      end if;

      Self.HTTP.Respond_To_Interaction
        (Interaction, Content, Ephemeral);
   end Respond_To_Interaction;

end Adacord.Clients;
