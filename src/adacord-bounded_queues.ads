private generic
   type Element_Type is private;
   Empty_Element : Element_Type;
   Capacity : Positive;
package Adacord.Bounded_Queues is
   --  Internal bounded FIFO with nonblocking producers and a blocking consumer.
   --  Capacity fixes the number of entries. Empty_Element releases references in
   --  consumed slots. Overflow is sticky: after saturation, subsequent pushes
   --  are rejected until the queue is destroyed; the owner must call Finish to
   --  release a consumer after draining accepted items.

   type Element_Array is array (Positive range <>) of Element_Type;
   --  Storage for the fixed-capacity ring.

   protected type Queue is
      --  Synchronized producer/consumer queue; no reset or reopen operation.
      procedure Push (Item : Element_Type; Accepted : out Boolean);
      --  Attempt to enqueue without waiting for free space.
      --  @param Item Value to append.
      --  @param Accepted False when full, overflowed or finished; True on success.
      entry Pop (Item : out Element_Type; Available : out Boolean);
      --  Wait for an item or completion, then consume the oldest item.
      --  @param Item Consumed value, or Empty_Element after draining a finished queue.
      --  @param Available False only when finished and empty.
      procedure Finish;
      --  Close the producer side and wake a waiting consumer.
      --  Pending items remain available; calls are idempotent.
      function Overflowed return Boolean;
      --  Inspect persistent saturation state.
      --  @return True if any Push attempted to exceed Capacity before Finish.
   private
      Items : Element_Array (1 .. Capacity) := (others => Empty_Element);
      Head : Positive := 1;
      Tail : Positive := 1;
      Count : Natural := 0;
      Finished : Boolean := False;
      Overflow : Boolean := False;
   end Queue;

end Adacord.Bounded_Queues;
