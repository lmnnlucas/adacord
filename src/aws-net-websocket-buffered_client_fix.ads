package AWS.Net.WebSocket.Buffered_Client_Fix is
   --  Compatibility adapter for AWS 25.2 HTTP-upgrade read-ahead.
   --  Reads bytes already buffered by AWS.Client before polling the OS socket.
   --  A temporary proxy joins buffered and network data while routing replies
   --  to the real transport. Subsequent complete messages stay buffered.

   procedure Recover_Buffered_Message (Socket : in out Object'Class);
   --  Process at most one message starting in AWS.Client's HTTP upgrade
   --  buffer, completing partial frames from the network if necessary.
   --  Call before each Poll; further buffered frames remain for later calls.
   --  Must not run concurrently with another read or write on this socket.
   --  @param Socket Connected WebSocket whose On_Message callback receives
   --  recovered text or binary data; control frames use AWS handling.
   --  @exception AWS.Net.Socket_Error Underlying transport failure.

private

   procedure Recover_Buffered_Message
     (Socket    : in out Object'Class;
      Transport : AWS.Net.Socket_Access);

end AWS.Net.WebSocket.Buffered_Client_Fix;
