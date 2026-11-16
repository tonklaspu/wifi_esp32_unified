# Windows PowerShell 5.1 / PowerShell 7
# Connect to a SAVED Wi-Fi profile, detect captive portal, open its login page,
# and monitor internet connectivity. Does NOT submit a login form or enable hotspot.
# Example: .\wifi_portal_monitor.ps1 -Ssid "CampusWiFi" -OpenHotspotSettings
param(
    [string]$Ssid = "",
    [ValidateRange(5, 3600)]
    [int]$IntervalSeconds = 20,
    [ValidateRange(30, 3600)]
    [int]$BrowserCooldownSeconds = 120,
    [switch]$OpenHotspotSettings
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$probeUrl = 'http://www.msftconnecttest.com/connecttest.txt'
$expectedBody = 'Microsoft Connect Test'
if ($env:PORTAL_TEST_URL) { $probeUrl = $env:PORTAL_TEST_URL }
if ($env:PORTAL_TEST_EXPECTED) { $expectedBody = $env:PORTAL_TEST_EXPECTED }
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$http = [System.Net.Http.HttpClient]::new($handler)
$http.Timeout = [TimeSpan]::FromSeconds(8)

function Get-Connectivity {
    try {
        $response = $http.GetAsync($probeUrl).GetAwaiter().GetResult()
        try {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $online = ([int]$response.StatusCode -eq 200) -and ($body.Trim() -eq $expectedBody)
            $redirectUrl = $null
            if ($null -ne $response.Headers.Location) {
                $redirectUrl = ([Uri]::new([Uri]$probeUrl, $response.Headers.Location)).AbsoluteUri
            }
            return [pscustomobject]@{
                Online = $online
                RedirectUrl = $redirectUrl
                StatusCode = [int]$response.StatusCode
                Error = $null
            }
        }
        finally {
            $response.Dispose()
        }
    }
    catch {
        return [pscustomobject]@{
            Online = $false
            RedirectUrl = $null
            StatusCode = $null
            Error = $_.Exception.Message
        }
    }
}

try {
    if (-not [string]::IsNullOrWhiteSpace($Ssid)) {
        Write-Host "Connecting to saved Wi-Fi profile: $Ssid" -ForegroundColor Cyan
        & netsh.exe wlan connect "name=$Ssid"
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'No usable saved Wi-Fi profile. Connect once in Windows Settings and select Connect automatically.'
        }
        Start-Sleep -Seconds 5
    }
    else {
        Write-Host 'Using the existing Windows Wi-Fi connection.' -ForegroundColor Cyan
    }

    if ($OpenHotspotSettings) {
        Start-Process 'ms-settings:network-mobilehotspot'
        Write-Host 'Enable Mobile Hotspot in Settings. The script does not toggle it automatically.'
    }

    Write-Host 'Monitoring captive portal. Press Ctrl+C to stop.' -ForegroundColor Cyan
    $wasOnline = $false
    $lastBrowserOpen = [DateTime]::MinValue

    while ($true) {
        $status = Get-Connectivity
        if ($status.Online) {
            if (-not $wasOnline) {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Internet ready. Hotspot clients may now use this connection." -ForegroundColor Green
            }
            $wasOnline = $true
        }
        else {
            if ($wasOnline) {
                Write-Warning 'Internet authentication may have expired.'
            }
            $wasOnline = $false

            if (((Get-Date) - $lastBrowserOpen).TotalSeconds -ge $BrowserCooldownSeconds) {
                $loginUrl = 'http://neverssl.com/'
                if ($env:PORTAL_URL -match '^https?://') { $loginUrl = $env:PORTAL_URL }
                if ($status.RedirectUrl -match '^https?://') {
                    $loginUrl = $status.RedirectUrl
                }
                Write-Warning "Not authenticated, blocked probe, or disconnected. Opening: $loginUrl"
                if ($status.Error) { Write-Host "Connectivity detail: $($status.Error)" }
                Start-Process $loginUrl
                $lastBrowserOpen = Get-Date
            }
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
}
finally {
    $http.Dispose()
    $handler.Dispose()
}
