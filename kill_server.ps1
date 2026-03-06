Stop-ScheduledTask -TaskName "IMOS-Receiver-Server" -ErrorAction SilentlyContinue
Get-NetTCPConnection -LocalPort 3500 -ErrorAction SilentlyContinue | ForEach-Object {
    taskkill /F /PID $_.OwningProcess
}
Write-Host "IMOS Receiver Service stopped."
Start-Sleep -Seconds 2
