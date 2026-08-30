package AWS.Net.WebSocket.Buffered_Client_Fix is

   procedure Recover_Buffered_Message (Socket : in out Object'Class);
   --  Feed bytes buffered by AWS.Client during the HTTP 101 upgrade back
   --  through the WebSocket protocol parser.

end AWS.Net.WebSocket.Buffered_Client_Fix;
