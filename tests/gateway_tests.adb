with Ada.Text_IO;
with AWS.Net.WebSocket.Buffered_Client_Fix.Regression;

procedure Gateway_Tests is
begin
   AWS.Net.WebSocket.Buffered_Client_Fix.Regression.Run;
   Ada.Text_IO.Put_Line ("PASS: WebSocket buffering regressions");
end Gateway_Tests;
