with Ada.Text_IO;
with Adacord.Bounded_Queues;

package body Adacord.Clients.Tests is

   procedure Run is
      package Queues is new Adacord.Bounded_Queues (Integer, 0, 3);
      Queue : Queues.Queue;
      Accepted, Available : Boolean;
      Item : Integer;
      Bot : Client;
      type Handler_Type is new Event_Handler with null record;
      Handler : Handler_Type;
      Checks : Natural := 0;

      procedure Check (Condition : Boolean; Message : String) is
      begin
         if not Condition then
            raise Program_Error with Message;
         end if;
         Checks := Checks + 1;
      end Check;
   begin
      for N in 1 .. 3 loop
         Queue.Push (N, Accepted);
         Check (Accepted, "queue accepts capacity items");
      end loop;
      Queue.Pop (Item, Available);
      Check (Available and Item = 1, "FIFO first item");
      Queue.Push (4, Accepted);
      Check (Accepted, "queue reuses consumed slot");
      Queue.Push (5, Accepted);
      Check (not Accepted and Queue.Overflowed, "overflow is explicit");
      Queue.Pop (Item, Available);
      Check (Available and Item = 2, "overflow retains pending events");
      Queue.Push (5, Accepted);
      Check (not Accepted and Queue.Overflowed,
             "overflow rejects new work even after a slot is freed");
      Queue.Finish;
      for N in 3 .. 4 loop
         Queue.Pop (Item, Available);
         Check (Available and Item = N, "wrapped FIFO drains after finish");
      end loop;
      Queue.Pop (Item, Available);
      Check (not Available, "finished empty queue does not block");
      Queue.Push (6, Accepted);
      Check (not Accepted, "finished queue rejects new work");

      declare
         Empty_Queue : Queues.Queue;
      begin
         Empty_Queue.Finish;
         Empty_Queue.Pop (Item, Available);
         Check (not Available and not Empty_Queue.Overflowed,
                "normal completion releases an empty consumer");
      end;

      declare
         Waiting_Queue : Queues.Queue;
         Released : Boolean;
         task Consumer is
            entry Started;
            entry Result (Success : out Boolean);
         end Consumer;
         task body Consumer is
            Value : Integer;
            Present : Boolean;
            Passed : Boolean := False;
         begin
            accept Started;
            select
               Waiting_Queue.Pop (Value, Present);
               Passed := not Present;
            or
               delay 2.0;
            end select;
            accept Result (Success : out Boolean) do
               Success := Passed;
            end Result;
         end Consumer;
      begin
         Consumer.Started;
         --  Allow the consumer to wait on an empty, unfinished queue.
         delay 0.05;
         Waiting_Queue.Finish;
         Consumer.Result (Released);
         Check (Released, "Finish wakes a waiting consumer");
      end;

      --  Simulate an active owner without opening a network connection.
      Bot.Initialized := True;
      Bot.Life.Start;
      begin
         Adacord.Clients.Run (Bot, Handler);
         raise Program_Error with "concurrent Run was accepted";
      exception
         when Adacord.Configuration_Error =>
            Check (Is_Running (Bot) and not Bot.Life.Stopping,
                   "rejected Run preserves active owner");
      end;
      Stop (Bot);
      Check (Is_Running (Bot) and Bot.Life.Stopping,
             "Stop keeps ownership until Run finishes");
      Bot.Life.Finish;
      Check (not Is_Running (Bot), "finished client is idle");
      Bot.Life.Start;
      Check (Is_Running (Bot) and not Bot.Life.Stopping,
             "completed client can restart");
      Bot.Life.Finish;
      Ada.Text_IO.Put_Line ("PASS:" & Checks'Image & " client assertions");
   end Run;

end Adacord.Clients.Tests;
