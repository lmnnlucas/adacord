with Ada.Streams;
with Ada.Strings.Unbounded;

with AWS.Client;
with AWS.Net.Buffered;
with AWS.Net.Memory;

package body AWS.Net.WebSocket.Buffered_Client_Fix is

   use type AWS.Client.HTTP_Connection_Access;

   procedure Recover_Buffered_Message (Socket : in out Object'Class) is

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

      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 4_096);
      Last      : Ada.Streams.Stream_Element_Offset;
      Message   : Ada.Strings.Unbounded.Unbounded_String;
      Original  : AWS.Net.Socket_Access;
      Transport : AWS.Net.Socket_Access;
   begin
      if Socket.Connection = null then
         return;
      end if;

      Transport := AWS.Client.Get_Socket (Socket.Connection.all);
      AWS.Net.Buffered.Read_Buffer (Transport.all, Buffer, Last);

      if Last < Buffer'First then
         return;
      end if;

      --  AWS.Client reads beyond the HTTP 101 header. Temporarily make those
      --  bytes the WebSocket transport so RFC6455 decoding sees them first.
      Original := Socket.Socket;
      Socket.Mem_Sock := new AWS.Net.Memory.Socket_Type;
      Socket.Mem_Sock.Send (Buffer (Buffer'First .. Last), Last);
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
         end if;
         AWS.Net.Free (Socket.Mem_Sock);
         raise;
   end Recover_Buffered_Message;

end AWS.Net.WebSocket.Buffered_Client_Fix;
