@echo off
echo [%date% %time%] Starting IMOS Receiver... >> "C:\imos-receiver\server.log"
set PORT=3500
set IMOS_INBOX=C:\imos-receiver\imos_inbox
set API_TOKEN=
cd /d "C:\imos-receiver"
"C:\Program Files\nodejs\node.exe" server.js >> "C:\imos-receiver\server.log" 2>&1
