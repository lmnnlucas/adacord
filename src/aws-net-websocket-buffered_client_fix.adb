with Ada.Streams;
with Ada.Strings.Unbounded;

with AWS.Client;
with AWS.Net.Buffered;
with AWS.Net.Memory;

package body AWS.Net.WebSocket.Buffered_Client_Fix is

   use type AWS.Client.HTTP_Connection_Access;

   --  Keep protocol reads on one byte stream even when the upgrade buffered
   --  only part of a frame. Writes (including automatic Pong/Close responses)
   --  must always reach the real transport.
   type Buffered_Transport is new AWS.Net.Memory.Socket_Type with record
      Transport : AWS.Net.Socket_Access;
   end record;

   overriding procedure Receive
     (Socket : Buffered_Transport;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset);

   overriding procedure Send
     (Socket : Buffered_Transport;
      Data   : Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset);

   overriding function Get_FD (Socket : Buffered_Transport) return Integer;

   overriding procedure Shutdown
     (Socket : Buffered_Transport;
      How    : Shutmode_Type := Shut_Read_Write);

   overriding procedure Receive
     (Socket : Buffered_Transport;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset) is
   begin
      if AWS.Net.Memory.Pending (AWS.Net.Memory.Socket_Type (Socket)) > 0 then
         AWS.Net.Memory.Receive
           (AWS.Net.Memory.Socket_Type (Socket), Data, Last);
      else
         AWS.Net.Buffered.Read (Socket.Transport.all, Data, Last);
      end if;
   end Receive;

   overriding procedure Send
     (Socket : Buffered_Transport;
      Data   : Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset) is
   begin
      Socket.Transport.Send (Data, Last);
   end Send;

   overriding function Get_FD (Socket : Buffered_Transport) return Integer is
     (Socket.Transport.Get_FD);

   overriding procedure Shutdown
     (Socket : Buffered_Transport;
      How    : Shutmode_Type := Shut_Read_Write) is
   begin
      Socket.Transport.Shutdown (How);
   end Shutdown;

   procedure Recover_Buffered_Message (Socket : in out Object'Class) is
   begin
      if Socket.Connection /= null then
         Recover_Buffered_Message
           (Socket, AWS.Client.Get_Socket (Socket.Connection.all));
      end if;
   end Recover_Buffered_Message;

   procedure Recover_Buffered_Message
     (Socket    : in out Object'Class;
      Transport : AWS.Net.Socket_Access) is

      procedure Receive
        (Source : Object'Class;
         Data   : out Ada.Streams.Stream_Element_Array;
         Last   : out Ada.Streams.Stream_Element_Offset);

      procedure Receive
        (Source : Object'Class;
         Data   : out Ada.Streams.Stream_Element_Array;
         Last   : out Ada.Streams.Stream_Element_Offset) is
      begin
         Source.Receive (Data, Last);
      end Receive;

      function Read_Message is new AWS.Net.WebSocket.Read_Message
        (Receive => Receive);

      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 1);
      Last      : Ada.Streams.Stream_Element_Offset;
      Message   : Ada.Strings.Unbounded.Unbounded_String;
      Original  : AWS.Net.Socket_Access := null;
   begin
      AWS.Net.Buffered.Read_Buffer (Transport.all, Buffer, Last);

      if Last < Buffer'First then
         return;
      end if;

      --  Read one complete message, leaving subsequent frames in the HTTP
      --  cache for the next call. An incomplete buffered frame continues on
      --  the real transport rather than spinning on an empty memory socket.
      Original := Socket.Socket;
      Socket.Mem_Sock := new Buffered_Transport;
      Buffered_Transport (Socket.Mem_Sock.all).Transport := Transport;
      AWS.Net.Memory.Send
        (AWS.Net.Memory.Socket_Type (Socket.Mem_Sock.all), Buffer, Last);
      Socket.Socket := Socket.Mem_Sock;

      loop
         exit when Read_Message (Socket, Message);
      end loop;

      Socket.Socket := Original;
      AWS.Net.Free (Socket.Mem_Sock);
   exception
      when others =>
         if Original /= null then
            Socket.Socket := Original;
            AWS.Net.Free (Socket.Mem_Sock);
         end if;
         raise;
   end Recover_Buffered_Message;

end AWS.Net.WebSocket.Buffered_Client_Fix;
