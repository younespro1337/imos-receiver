# IMOS XML Receiver Server

HTTP server that receives XML orders from RoomPlanner/createSubSo and saves them to a folder where IMOS NetShop picks them up.

## Architecture

```
RoomPlanner UI → createSubSo API → POST XML → [this server] → saves to IMOS_INBOX folder → IMOS NetShop reads it
```

## Quick Install

**On the IMOS machine** (e.g. `192.168.30.41`), open PowerShell **as Administrator**:

```powershell
# 1. Clone this repo
git clone https://github.com/younespro1337/imos-receiver.git
cd imos-receiver

# 2. Run the installer (default: port 3500, inbox C:\imos_inbox)
powershell -ExecutionPolicy Bypass -File install.ps1
```

### Custom paths

If IMOS NetShop reads from a specific folder, pass it as `-InboxPath`:

```powershell
# Example: IMOS reads from D:\iMOS\NetShop\Import
powershell -ExecutionPolicy Bypass -File install.ps1 -InboxPath "D:\iMOS\NetShop\Import"

# Custom port + inbox
powershell -ExecutionPolicy Bypass -File install.ps1 -Port 4000 -InboxPath "E:\imos_data"
```

### All parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Port` | `3500` | HTTP listen port |
| `-InboxPath` | `C:\imos_inbox` | Folder where XML files are saved |
| `-InstallDir` | `C:\imos-receiver` | Where server files are copied to |

## What the installer does

1. ✅ Checks / installs **Node.js** (via winget or direct download)
2. ✅ Creates the **inbox folder** with full permissions
3. ✅ Copies `server.js` + `package.json` to the install directory
4. ✅ Runs `npm install` (Express dependency)
5. ✅ Opens **firewall** port for inbound TCP
6. ✅ Creates a **Windows Scheduled Task** (auto-starts on boot, runs as SYSTEM)
7. ✅ Starts the server immediately
8. ✅ Verifies with a `/health` check

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Status + stats (files count, uptime) |
| `GET` | `/health` | Simple health check `{ status: "ok" }` |
| `POST` | `/imos/receive` | Receive XML body, save to inbox |
| `GET` | `/imos/files` | List all received XML files |

### Receive XML

```bash
curl -X POST http://192.168.30.41:3500/imos/receive \
  -H "Content-Type: application/xml" \
  -d @order.xml
```

Response:
```json
{
  "success": true,
  "file": "IMOS-3317-1772580914667_2026-03-03T23-35-14-667Z.xml",
  "size": 4523,
  "order_no": "IMOS-3317-1772580914667",
  "elapsed_ms": 3
}
```

## Management

```powershell
# Check if running
Invoke-RestMethod http://localhost:3500/health

# List received files
Invoke-RestMethod http://localhost:3500/imos/files

# Stop the server
Stop-ScheduledTask -TaskName "IMOS-Receiver-Server"

# Start the server
Start-ScheduledTask -TaskName "IMOS-Receiver-Server"

# Reinstall (e.g. after updating server.js)
powershell -ExecutionPolicy Bypass -File install.ps1 -InboxPath "C:\imos_inbox"
```

## Environment Variables

The server reads these at runtime (set by `start.bat` from install params):

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3500` | Listen port |
| `IMOS_INBOX` | `C:\imos_inbox` | Where to save XML files |
| `ALLOWED_IPS` | *(all)* | Comma-separated IPs to allow (optional) |

## Files

```
imos-receiver/
├── server.js      ← Express HTTP server (receives XML, saves to inbox)
├── package.json   ← Node.js dependencies (express)
├── install.ps1    ← One-click Windows installer (run as Admin)
└── README.md
```