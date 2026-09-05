with Adacord.Bounded_Queues;

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

   package Event_Queues is new Adacord.Bounded_Queues
     (Element_Type  => Queue_Item,
      Empty_Element => (Kind => Finished_Item),
      Capacity      => 1_024);

   subtype Event_Queue is Event_Queues.Queue;

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

   procedure Enqueue (Sink : in out Queue_Sink; Item : Queue_Item) is
      Accepted : Boolean;
   begin
      Sink.Queue.Push (Item, Accepted);
      if not Accepted then
         Sink.Life.Request_Stop;
      end if;
   end Enqueue;

   ------------------
   -- Handle_Ready --
   ------------------

   overriding procedure Handle_Ready
     (Sink  : in out Queue_Sink;
      Event : Adacord.Types.Ready) is
   begin
      Enqueue (Sink, (Kind => Ready_Item, Ready_Event => Event));
   end Handle_Ready;

   ---------------------------
   -- Handle_Message_Create --
   ---------------------------

   overriding procedure Handle_Message_Create
     (Sink  : in out Queue_Sink;
      Event : Adacord.Types.Message) is
   begin
      Enqueue
        (Sink, (Kind => Message_Create_Item, Message_Event => Event));
   end Handle_Message_Create;

   -------------------------------
   -- Handle_Interaction_Create --
   -------------------------------

   overriding procedure Handle_Interaction_Create
     (Sink  : in out Queue_Sink;
      Event : Adacord.Types.Interaction) is
   begin
      Enqueue
        (Sink, (Kind              => Interaction_Create_Item,
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
      Enqueue
        (Sink, (Kind    => Error_Item,
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
      Started : Boolean := False;

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
      Started := True;

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

            Queue.Finish;
         exception
            when others =>
               --  Always release the consumer, even if error reporting fails.
               Queue.Finish;
         end Worker;

         Item : Queue_Item;
         Available : Boolean;
      begin
         loop
            Queue.Pop (Item, Available);
            exit when not Available;

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
         if Queue.Overflowed then
            begin
               Handler.On_Error
                 (Self, "Discord event queue exceeded 1024 pending events; "
                  & "the client stopped because callbacks are too slow",
                  Fatal => True);
            exception
               when others =>
                  null;
            end;
         end if;
      exception
         when others =>
            --  Request shutdown before waiting for the dependent task.
            Self.Life.Request_Stop;
            raise;
      end;
      Self.Life.Finish;
   exception
      when others =>
         --  A rejected concurrent Run must not stop the existing owner.
         if Started then
            Self.Life.Finish;
         end if;
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
