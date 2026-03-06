# ============================================================
# IMOS Receiver — Test Script
# ============================================================
# Sends the test XML file to the server and shows the response.
#
# Usage:
#   .\test\send_test.ps1                     (defaults to localhost:3500)
#   .\test\send_test.ps1 -Url http://192.168.30.41:3500
# ============================================================
# powershell -ExecutionPolicy Bypass -File "C:\imos-receiver\test\send_test.ps1" 


param(
    [string]$Url = "http://localhost:3500"
)

$xmlFile = Join-Path $PSScriptRoot "test.xml"




if (-not (Test-Path $xmlFile)) {
    Write-Host "[FAIL] test.xml not found at: $xmlFile" -ForegroundColor Red
    exit 1
}


Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  IMOS Receiver - Test Runner" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Server : $Url" -ForegroundColor White
Write-Host "  File   : $xmlFile" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ── Test 1: Health check ──────────────────────────────────────────────────────
Write-Host "[TEST 1] GET /health" -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "$Url/health" -Method GET -TimeoutSec 5
    Write-Host "  [PASS] Status: $($health.status), Uptime: $($health.uptime)s" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Server not reachable at $Url" -ForegroundColor Red
    Write-Host "         Make sure the server is running first!" -ForegroundColor Yellow
    exit 1
}

# ── Test 2: Send XML ─────────────────────────────────────────────────────────
Write-Host "[TEST 2] POST /imos/receive (test.xml)" -ForegroundColor Yellow
try {
    $xml = Get-Content -Path $xmlFile -Raw -Encoding UTF8
    $response = Invoke-RestMethod -Uri "$Url/imos/receive" -Method POST -ContentType "application/xml" -Body $xml -TimeoutSec 10

    if ($response.success -eq $true) {
        Write-Host "  [PASS] XML received and saved!" -ForegroundColor Green
        Write-Host "         File     : $($response.file)" -ForegroundColor White
        Write-Host "         Order No : $($response.order_no)" -ForegroundColor White
        Write-Host "         Size     : $($response.size) bytes" -ForegroundColor White
        Write-Host "         Time     : $($response.elapsed_ms) ms" -ForegroundColor White
    } else {
        Write-Host "  [FAIL] Unexpected response:" -ForegroundColor Red
        $response | ConvertTo-Json | Write-Host
    }
} catch {
    Write-Host "  [FAIL] POST failed: $_" -ForegroundColor Red
    exit 1
}

# ── Test 3: List files ────────────────────────────────────────────────────────
Write-Host "[TEST 3] GET /imos/files" -ForegroundColor Yellow
try {
    $files = Invoke-RestMethod -Uri "$Url/imos/files" -Method GET -TimeoutSec 5
    Write-Host "  [PASS] $($files.count) file(s) in inbox" -ForegroundColor Green
    $files.files | Select-Object -First 3 | ForEach-Object {
        Write-Host "         - $($_.name) ($($_.size) bytes)" -ForegroundColor White
    }
} catch {
    Write-Host "  [FAIL] Could not list files: $_" -ForegroundColor Red
}

# ── Test 4: Send empty body (should fail with 400) ───────────────────────────
Write-Host "[TEST 4] POST /imos/receive (empty body, expect 400)" -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri "$Url/imos/receive" -Method POST -ContentType "application/xml" -Body "" -TimeoutSec 5
    Write-Host "  [FAIL] Expected 400 but got 200" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.Value__
    if ($statusCode -eq 400) {
        Write-Host "  [PASS] Correctly rejected empty XML (HTTP 400)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Expected 400 but got $statusCode" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  All tests complete!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
