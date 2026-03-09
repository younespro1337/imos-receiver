@echo off
echo [%date% %time%] Starting IMOS Receiver... >> "C:\imos-receiver\server.log"
set PORT=3500
set IMOS_INBOX=C:\imos-receiver\imos_inbox
set API_TOKEN=M4V8yOHFUsw1Q6ahtBR5WYwKVu7C0PDpAfVEhKW9zkKjePN7OfPrXV3G8IS7onCaD6TJJ1hfyf74lLN4ZZkS6np2OGtafZZclkY1k34ZQJ0tS4bMAtmIxZD8BqFtkCwCP1HkEtj93LXOpNlx9LLTNsZOe4uWJDMimOXvbAx6rNa7cAzXBlKyeuvxszqKiwOFh6muiVe5d70oqQUCdRgenv1geb52qpRblkhXdrjNiQsJ7WKtIzRZIbZkrX6ChnF0
set ALLOWED_IPS=192.168.11.121
cd /d "C:\imos-receiver"
"C:\Program Files\nodejs\node.exe" server.js >> "C:\imos-receiver\server.log" 2>&1
