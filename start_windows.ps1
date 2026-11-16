# Run one connectivity monitor at a time. This launcher does not change sharing/firewall settings.
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Manual')]
    [string]$Mode = 'Auto',
    [string]$Ssid = '',
    [string]$ConfigPath = '',
    [string]$PythonExe = '',
    [switch]$OpenHotspotSettings
)
$ErrorActionPreference = 'Stop'

if ($ConfigPath) {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $allowedKeys = @('PORTAL_URL', 'PORTAL_ALLOWED_HOSTS', 'PORTAL_TEST_URL',
        'PORTAL_TEST_EXPECTED', 'PORTAL_USER_SELECTOR', 'PORTAL_PASS_SELECTOR', 'PORTAL_SUBMIT_SELECTOR')
    foreach ($property in $config.PSObject.Properties) {
        if ($property.Name -notin $allowedKeys -or $property.Value -isnot [string] -or
            [string]::IsNullOrWhiteSpace($property.Value)) {
            throw "Unsupported or empty configuration entry: $($property.Name). Do not put credentials in this file."
        }
    }
    foreach ($property in $config.PSObject.Properties) {
        [Environment]::SetEnvironmentVariable($property.Name, $property.Value, 'Process')
    }
}

if ($Mode -eq 'Manual') {
    & (Join-Path $PSScriptRoot 'windows\wifi_portal_monitor.ps1') -Ssid $Ssid -OpenHotspotSettings:$OpenHotspotSettings
    return
}

if (-not $PythonExe) {
    $venvPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $venvPython) { $PythonExe = $venvPython }
    elseif (Get-Command py.exe -ErrorAction SilentlyContinue) { $PythonExe = 'py.exe' }
    elseif (Get-Command python.exe -ErrorAction SilentlyContinue) { $PythonExe = 'python.exe' }
    else { throw 'Python 3 is required for Auto mode. See README_TH.md or use -Mode Manual.' }
}
& $PythonExe -c 'import playwright.sync_api'
if ($LASTEXITCODE -ne 0) { throw 'Python/Playwright is not ready. Follow the installation steps in README_TH.md.' }

if (-not [string]::IsNullOrWhiteSpace($Ssid)) {
    & netsh.exe wlan connect "name=$Ssid"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot connect to saved Wi-Fi profile. Connect once in Windows Settings first.' }
    Start-Sleep -Seconds 5
}
if ($OpenHotspotSettings) { Start-Process 'ms-settings:network-mobilehotspot' }
& $PythonExe (Join-Path $PSScriptRoot 'windows\auto_login.py')
if ($LASTEXITCODE -ne 0) { throw 'Auto login stopped with an error. Check the message above.' }
