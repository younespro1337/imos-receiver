@echo off
set PORT=3500
set IMOS_INBOX=C:\imos_inbox
cd /d "C:\imos-receiver"
"C:\Program Files\nodejs\node.exe" server.js
