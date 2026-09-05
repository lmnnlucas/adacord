private generic
   type Element_Type is private;
   Empty_Element : Element_Type;
   Capacity : Positive;
package Adacord.Bounded_Queues is

   type Element_Array is array (Positive range <>) of Element_Type;

   protected type Queue is
      procedure Push (Item : Element_Type; Accepted : out Boolean);
      entry Pop (Item : out Element_Type; Available : out Boolean);
      procedure Finish;
      function Overflowed return Boolean;
   private
      Items : Element_Array (1 .. Capacity) := (others => Empty_Element);
      Head : Positive := 1;
      Tail : Positive := 1;
      Count : Natural := 0;
      Finished : Boolean := False;
      Overflow : Boolean := False;
   end Queue;

end Adacord.Bounded_Queues;
