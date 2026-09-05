package body Adacord.Bounded_Queues is

   protected body Queue is

      procedure Push (Item : Element_Type; Accepted : out Boolean) is
      begin
         Accepted := False;
         if Finished or else Overflow then
            return;
         elsif Count = Capacity then
            Overflow := True;
            return;
         end if;

         Items (Tail) := Item;
         Tail := (if Tail = Capacity then 1 else Tail + 1);
         Count := Count + 1;
         Accepted := True;
      end Push;

      entry Pop (Item : out Element_Type; Available : out Boolean)
        when Count > 0 or else Finished
      is
      begin
         Available := Count > 0;
         Item := Empty_Element;
         if Available then
            Item := Items (Head);
            --  Release strings and containers as soon as they are consumed.
            Items (Head) := Empty_Element;
            Head := (if Head = Capacity then 1 else Head + 1);
            Count := Count - 1;
         end if;
      end Pop;

      procedure Finish is
      begin
         Finished := True;
      end Finish;

      function Overflowed return Boolean is (Overflow);

   end Queue;

end Adacord.Bounded_Queues;
