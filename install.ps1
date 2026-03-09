# ============================================================================
# IMOS Receiver Server - Full Installer
# ============================================================================
#
# Run as Administrator on the IMOS machine (192.168.30.41):
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# What this script does:
#   1. Checks / installs Node.js (via winget or manual download)
#   2. Creates the IMOS inbox folder (C:\imos_inbox)
#   3. Installs npm dependencies (Express)
#   4. Opens firewall port 3500 for inbound TCP
#   5. Creates a Windows Scheduled Task to auto-start the server on boot
#   6. Starts the server immediately
#
# ============================================================================

param(
    [int]$Port = 0,
    [string]$InboxPath = "",
    [string]$InstallDir = "",
    [string]$Token = "",
    [string]$AllowedIps = ""
)

$ErrorActionPreference = "Stop"

# ── Load .env defaults (values in .env are used only when param was not passed) ──
$envFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ".env"
$envDefaults = @{
    PORT        = "3500"
    IMOS_INBOX  = "C:\imos_inbox"
    INSTALL_DIR = "C:\imos-receiver"
    API_TOKEN   = ""
    ALLOWED_IPS = ""
}
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $envDefaults[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
}
if ($Port -eq 0)        { $Port      = [int]($envDefaults["PORT"]) }
if ($InboxPath -eq "")  { $InboxPath = $envDefaults["IMOS_INBOX"] }
if ($InstallDir -eq "") { $InstallDir = $envDefaults["INSTALL_DIR"] }
if ($Token -eq "")      { $Token     = $envDefaults["API_TOKEN"] }
if ($AllowedIps -eq "") { $AllowedIps = $envDefaults["ALLOWED_IPS"] }

function Write-Step($msg) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Ok($msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-Warn($msg) {
    Write-Host "  [WARN] $msg" -ForegroundColor Yellow
}

function Write-Fail($msg) {
    Write-Host "  [FAIL] $msg" -ForegroundColor Red
}

# -- Check Admin --
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Fail "This script must be run as Administrator!"
    Write-Host "  Right-click PowerShell -> Run as Administrator" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "         IMOS Receiver Server - Installer                   " -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  Port       : $Port" -ForegroundColor White
Write-Host "  Inbox      : $InboxPath" -ForegroundColor White
Write-Host "  Install Dir: $InstallDir" -ForegroundColor White
Write-Host "  Token      : $(if ($Token) { '*** (set)' } else { 'NOT SET (open)' })" -ForegroundColor White
Write-Host "  Allowed IPs: $(if ($AllowedIps) { $AllowedIps } else { 'ALL (no restriction)' })" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Magenta

# ============================================================================
# STEP 1: Check / Install Node.js
# ============================================================================
Write-Step "Step 1: Checking Node.js"

$nodeExists = $false
try {
    $nodeVersion = & node --version 2>$null
    if ($nodeVersion) {
        Write-Ok "Node.js found: $nodeVersion"
        $nodeExists = $true
    }
} catch {}

if (-not $nodeExists) {
    Write-Warn "Node.js not found. Installing via winget..."
    try {
        & winget install OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
        # Refresh PATH
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = $machinePath + ";" + $userPath
        $nodeVersion = & node --version 2>$null
        if ($nodeVersion) {
            Write-Ok "Node.js installed: $nodeVersion"
        } else {
            Write-Fail "Node.js installed but not in PATH. Please restart this script after rebooting."
            exit 1
        }
    } catch {
        Write-Warn "winget failed. Trying direct download..."
        $nodeUrl = "https://nodejs.org/dist/v20.11.1/node-v20.11.1-x64.msi"
        $msiPath = Join-Path $env:TEMP "node-install.msi"
        Write-Host "  Downloading Node.js LTS..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $nodeUrl -OutFile $msiPath -UseBasicParsing
        Write-Host "  Installing (this may take a minute)..." -ForegroundColor Yellow
        Start-Process msiexec.exe -ArgumentList "/i", "`"$msiPath`"", "/quiet", "/norestart" -Wait
        Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
        # Refresh PATH
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = $machinePath + ";" + $userPath
        $nodeVersion = & node --version 2>$null
        if ($nodeVersion) {
            Write-Ok "Node.js installed: $nodeVersion"
        } else {
            Write-Fail "Node.js install failed. Please install manually from https://nodejs.org and re-run."
            exit 1
        }
    }
}

$npmVersion = & npm --version 2>$null
Write-Ok "npm: $npmVersion"

# ============================================================================
# STEP 2: Create IMOS inbox folder
# ============================================================================
Write-Step "Step 2: Creating IMOS inbox folder"

if (-not (Test-Path $InboxPath)) {
    New-Item -ItemType Directory -Path $InboxPath -Force | Out-Null
    Write-Ok "Created: $InboxPath"
} else {
    Write-Ok "Already exists: $InboxPath"
}

# Full permissions for Everyone (so the server can write)
$acl = Get-Acl $InboxPath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Everyone", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
)
$acl.SetAccessRule($rule)
Set-Acl $InboxPath $acl
Write-Ok "Full permissions set on $InboxPath"

# ============================================================================
# STEP 3: Copy server files to install directory
# ============================================================================
Write-Step "Step 3: Setting up server files"

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Copy server.js and package.json from this directory (skip if source == destination)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$filesToCopy = @("server.js", "package.json")
foreach ($file in $filesToCopy) {
    $src = Join-Path $scriptDir $file
    $dst = Join-Path $InstallDir $file
    if ((Resolve-Path $src).Path -eq (Resolve-Path $dst -ErrorAction SilentlyContinue).Path) {
        Write-Ok "Already in place (skipped copy): $file"
    } else {
        Copy-Item $src $dst -Force
        Write-Ok "Copied: $file"
    }
}

# ============================================================================
# STEP 4: Install npm dependencies
# ============================================================================
Write-Step "Step 4: Installing dependencies"

$nodeModulesPath = Join-Path $InstallDir "node_modules"
if (Test-Path $nodeModulesPath) {
    Write-Ok "node_modules already exists, skipping npm install"
} else {
    Push-Location $InstallDir
    try {
        Write-Host "  Running npm install... (this may take a minute)" -ForegroundColor Yellow
        cmd.exe /c "npm install --omit=dev"
        if ($LASTEXITCODE -ne 0) {
            throw "npm install exited with code $LASTEXITCODE"
        }
        Write-Ok "npm dependencies installed"
    } catch {
        Write-Fail "npm install failed: $_"
        exit 1
    } finally {
        Pop-Location
    }
}

# ============================================================================
# STEP 5: Firewall rule
# ============================================================================
Write-Step "Step 5: Configuring firewall"

$ruleName = "IMOS Receiver Port $Port"
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

if ($existingRule) {
    Write-Ok "Firewall rule already exists: $ruleName"
} else {
    New-NetFirewallRule -DisplayName $ruleName `
        -Description "Allow inbound TCP on port $Port for IMOS XML Receiver" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $Port `
        -Action Allow `
        -Profile Any | Out-Null
    Write-Ok "Firewall rule created: $ruleName (TCP $Port inbound ALLOW)"
}

# ============================================================================
# STEP 6: Create Windows Scheduled Task (auto-start on boot)
# ============================================================================
Write-Step "Step 6: Creating auto-start task"

$taskName = "IMOS-Receiver-Server"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

$recreateTask = $true
if ($existingTask) {
    # Check if the existing batch file already matches current config
    $batchFile = Join-Path $InstallDir "start.bat"
    if (Test-Path $batchFile) {
        $batchContent = Get-Content $batchFile -Raw
        if ($batchContent -match "set PORT=$Port" -and
            $batchContent -match [regex]::Escape("set IMOS_INBOX=$InboxPath") -and
            $batchContent -match [regex]::Escape("set API_TOKEN=$Token") -and
            $batchContent -match [regex]::Escape("set ALLOWED_IPS=$AllowedIps")) {
            Write-Ok "Scheduled task already up to date, skipping recreation"
            $recreateTask = $false
        }
    }
    if ($recreateTask) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Warn "Removed old scheduled task (config changed): $taskName"
    }
}

if ($recreateTask) {
    # Write a batch launcher with env vars and logging baked in
    $logFile = Join-Path $InstallDir "server.log"
    $nodePath = (Get-Command node).Source
    $batchLines = @(
        "@echo off",
        "echo [%date% %time%] Starting IMOS Receiver... >> `"$logFile`"",
        "set PORT=$Port",
        "set IMOS_INBOX=$InboxPath",
        "set API_TOKEN=$Token",
        "set ALLOWED_IPS=$AllowedIps",
        "cd /d `"$InstallDir`"",
        "`"$nodePath`" server.js >> `"$logFile`" 2>&1"
    )
    $batchFile = Join-Path $InstallDir "start.bat"
    $batchLines | Out-File -FilePath $batchFile -Encoding ASCII
    Write-Ok "Launcher batch created: $batchFile"
    Write-Ok "Server logs will be written to: $logFile"

    $action = New-ScheduledTaskAction -Execute $batchFile -WorkingDirectory $InstallDir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 999 `
        -RestartInterval (New-TimeSpan -Minutes 1)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "IMOS XML Receiver Server - auto-starts on boot, listens on port $Port" | Out-Null

    Write-Ok "Scheduled task created: $taskName (runs at system startup)"
} else {
    $batchFile = Join-Path $InstallDir "start.bat"
    $logFile = Join-Path $InstallDir "server.log"
}

# ============================================================================
# STEP 7: Start the server NOW
# ============================================================================
Write-Step "Step 7: Starting IMOS Receiver Server"

# Kill any existing instance on the port
$existingProcess = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique
if ($existingProcess) {
    foreach ($procId in $existingProcess) {
        if ($procId -gt 0) {
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            Write-Warn "Killed existing process on port $Port - PID $procId"
        }
    }
    Start-Sleep -Seconds 1
}

# Start via scheduled task
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 3

# ============================================================================
# STEP 8: Verify
# ============================================================================
Write-Step "Step 8: Verifying"

try {
    $response = Invoke-RestMethod -Uri "http://localhost:$Port/health" -Method GET -TimeoutSec 5
    if ($response.status -eq "ok") {
        Write-Ok "Server is running and healthy!"
    } else {
        Write-Warn "Server responded but health check unclear"
    }
} catch {
    Write-Warn "Could not reach server yet. It may still be starting up."
    Write-Host "  Try manually: Invoke-RestMethod http://localhost:${Port}/health" -ForegroundColor Yellow
}

# Get this machine's IPs
$ips = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -ne "WellKnown" } |
    Select-Object -ExpandProperty IPAddress

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "         INSTALLATION COMPLETE!                             " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Server    : http://localhost:$Port" -ForegroundColor White
foreach ($ip in $ips) {
    Write-Host "  Network   : http://${ip}:$Port" -ForegroundColor White
}
Write-Host "  Inbox     : $InboxPath" -ForegroundColor White
Write-Host "  Install   : $InstallDir" -ForegroundColor White
Write-Host "  Auto-start: Yes (Windows Scheduled Task)" -ForegroundColor White
if ($Token) {
    Write-Host "  API Token : REQUIRED (Set successfully)" -ForegroundColor Yellow
} else {
    Write-Host "  API Token : NOT SET (Open endpoint)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  Endpoints:" -ForegroundColor Green
Write-Host "    GET  /              - status + stats" -ForegroundColor White
Write-Host "    GET  /health        - health check" -ForegroundColor White
Write-Host "    POST /imos/receive  - receive XML" -ForegroundColor White
Write-Host "    GET  /imos/files    - list received files" -ForegroundColor White
Write-Host ""
Write-Host "  Send from createSubSo:" -ForegroundColor Green
Write-Host "    POST http://192.168.30.41:$Port/imos/receive" -ForegroundColor Yellow
Write-Host "    Content-Type: application/xml" -ForegroundColor Yellow
if ($Token) {
    Write-Host "    x-api-token: $Token" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
