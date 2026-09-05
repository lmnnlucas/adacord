with AWS.Net.Buffered;
with AWS.Net.Memory;
with AWS.Status;

package body AWS.Net.WebSocket.Buffered_Client_Fix.Regression is
   type Test_Socket is new Object with record
      Message : Unbounded_String;
      Count : Natural := 0;
   end record;
   overriding procedure On_Message
     (Socket : in out Test_Socket; Message : Unbounded_String);
   overriding procedure On_Message
     (Socket : in out Test_Socket; Message : Unbounded_String) is
   begin
      Socket.Message := Message;
      Socket.Count := Socket.Count + 1;
   end On_Message;

   type Test_Transport is new AWS.Net.Memory.Socket_Type with record
      Read_Limit : Stream_Element_Offset := 4_096;
      Output : AWS.Net.Socket_Access := new AWS.Net.Memory.Socket_Type;
   end record;
   overriding procedure Receive
     (Socket : Test_Transport; Data : out Stream_Element_Array;
      Last : out Stream_Element_Offset);
   overriding procedure Send
     (Socket : Test_Transport; Data : Stream_Element_Array;
      Last : out Stream_Element_Offset);
   overriding procedure Free (Socket : in out Test_Transport);
   overriding procedure Receive
     (Socket : Test_Transport; Data : out Stream_Element_Array;
      Last : out Stream_Element_Offset) is
   begin
      AWS.Net.Memory.Receive
        (AWS.Net.Memory.Socket_Type (Socket),
         Data (Data'First .. Stream_Element_Offset'Min
           (Data'Last, Data'First + Socket.Read_Limit - 1)), Last);
   end Receive;
   overriding procedure Send
     (Socket : Test_Transport; Data : Stream_Element_Array;
      Last : out Stream_Element_Offset) is
   begin
      Socket.Output.Send (Data, Last);
   end Send;
   overriding procedure Free (Socket : in out Test_Transport) is
   begin
      AWS.Net.Free (Socket.Output);
      AWS.Net.Memory.Free (AWS.Net.Memory.Socket_Type (Socket));
   end Free;

   procedure Check (Condition : Boolean; Details : String) is
   begin
      if not Condition then
         raise Program_Error with Details;
      end if;
   end Check;

   procedure Run is
   begin
      for Scenario in 1 .. 4 loop
         declare
            Transport : constant AWS.Net.Socket_Access := new Test_Transport;
            Request : AWS.Status.Data;
            Socket : Test_Socket :=
              (Object (AWS.Net.WebSocket.Create (Transport, Request)) with
               Message => Null_Unbounded_String, Count => 0);
            Last : Stream_Element_Offset;
            procedure Seed (Data : Stream_Element_Array) is
               Sentinel : Character;
            begin
               --  Preload once: memory streams cannot append after EOF.
               --  Input and output are separate, as on a real TCP socket.
               AWS.Net.Memory.Send
                 (AWS.Net.Memory.Socket_Type (Transport.all),
                  Stream_Element_Array'[0] & Data, Last);
               Sentinel := AWS.Net.Buffered.Get_Char (Transport.all);
               Check (Sentinel = Character'Val (0), "buffer sentinel");
            end Seed;
         begin
            case Scenario is
               when 1 =>
                  Seed ([16#81#, 1, Character'Pos ('a'),
                         16#81#, 1, Character'Pos ('b')]);
                  Recover_Buffered_Message (Socket, Transport);
                  Check (Socket.Count = 1
                         and then To_String (Socket.Message) = "a",
                         "first buffered message");
                  Recover_Buffered_Message (Socket, Transport);
                  Check (Socket.Count = 2
                         and then To_String (Socket.Message) = "b",
                         "second buffered message preserved");
                  Recover_Buffered_Message (Socket, Transport);
                  Check (Socket.Count = 2, "empty cache produces no message");
               when 2 =>
                  Test_Transport (Transport.all).Read_Limit := 2;
                  Seed ([16#81#, 1, Character'Pos ('c')]);
                  Recover_Buffered_Message (Socket, Transport);
                  Check (Socket.Count = 1
                         and then To_String (Socket.Message) = "c",
                         "split frame completed from transport");
               when 3 =>
                  declare
                     Payload : constant Stream_Element_Array (1 .. 5_000) :=
                       [others => Character'Pos ('x')];
                  begin
                     Seed (Stream_Element_Array'[16#81#, 126, 19, 136]
                           & Payload);
                     Recover_Buffered_Message (Socket, Transport);
                     Check (Socket.Count = 1
                            and then Length (Socket.Message) = 5_000,
                            "message larger than the HTTP read buffer");
                  end;
               when 4 =>
                  Seed ([16#89#, 1, Character'Pos ('p')]);
                  Recover_Buffered_Message (Socket, Transport);
                  declare
                     Reply : Stream_Element_Array (1 .. 32);
                  begin
                     Test_Transport (Transport.all).Output.Receive
                       (Reply, Last);
                     Check (Last >= 3 and then Reply (1) = 16#8A#,
                            "buffered Ping sends Pong to real transport");
                  end;
            end case;
         end;
      end loop;
   end Run;
end AWS.Net.WebSocket.Buffered_Client_Fix.Regression;
