package AWS.Net.WebSocket.Buffered_Client_Fix is

   procedure Recover_Buffered_Message (Socket : in out Object'Class);
   --  Process at most one message starting in AWS.Client's HTTP upgrade
   --  buffer, completing partial frames from the network if necessary.
   --  Call before each Poll; further buffered frames remain for later calls.

private

   procedure Recover_Buffered_Message
     (Socket    : in out Object'Class;
      Transport : AWS.Net.Socket_Access);

end AWS.Net.WebSocket.Buffered_Client_Fix;
