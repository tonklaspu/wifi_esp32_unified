#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'WiFiESP32'),
    [ValidateSet('Auto','Manual','Server')][string]$Mode = 'Auto',
    [string]$Ref = 'main',
    [string]$Ssid = '',
    [string]$PortalUrl = '',
    [switch]$Repair,
    [switch]$Run,
    # For offline file recovery/testing; dependencies still need internet unless skipped.
    [string]$SourceDirectory = '',
    [switch]$SkipDependencies
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repository = 'tonklaspu/wifi_esp32_unified'
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
$null = New-Item -ItemType Directory -Path $InstallDir -Force
$downloadDir = Join-Path $InstallDir '.downloads'
$null = New-Item -ItemType Directory -Path $downloadDir -Force

function Get-Download([string]$Url, [string]$Destination) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination -TimeoutSec 120
            return
        } catch {
            if ($attempt -eq 3) { throw "Download failed: $Url. Internet access is needed for first installation. $($_.Exception.Message)" }
            Start-Sleep -Seconds 2
        }
    }
}
function Invoke-Python([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Python command failed (exit $LASTEXITCODE): $($Arguments -join ' ')" }
}

if ($SourceDirectory) {
    $SourceDirectory = (Resolve-Path -LiteralPath $SourceDirectory).Path
    $manifest = Get-Content -LiteralPath (Join-Path $SourceDirectory 'files.sha256.json') -Raw | ConvertFrom-Json
} else {
    # Resolve main once: all downloads in this run come from the same commit.
    if ($Ref -match '^[a-fA-F0-9]{40}$') { $revision = $Ref }
    else {
        $commit = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/commits/$([Uri]::EscapeDataString($Ref))" -Headers @{ 'User-Agent' = 'WiFiESP32-Installer' }
        $revision = $commit.sha
    }
    if ($revision -notmatch '^[a-fA-F0-9]{40}$') { throw 'Invalid GitHub revision.' }
    $baseUrl = "https://raw.githubusercontent.com/$repository/$revision"
    $manifestPath = Join-Path $downloadDir 'files.sha256.json'
    Get-Download "$baseUrl/files.sha256.json" $manifestPath
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Write-Host "Source commit: $revision"
}
$allowedPaths = @('.gitignore','README_TH.md','config.example.json','requirements.txt','start_windows.ps1',
    'install_windows.ps1','windows/auto_login.py','windows/wifi_portal_monitor.ps1',
    'windows/esp32_server.py','esp32/esp32_test/esp32_test.ino')
if ($manifest.schema -ne 1 -or @($manifest.files).Count -ne $allowedPaths.Count) { throw 'Invalid file manifest.' }
$seen = @{}
foreach ($entry in $manifest.files) {
    if ($entry.path -notin $allowedPaths -or $seen.ContainsKey($entry.path) -or $entry.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Unexpected manifest entry.' }
    $seen[$entry.path] = $true
    $target = Join-Path $InstallDir $entry.path
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $entry.sha256) { continue }
        if (-not $Repair) { Write-Warning "Keeping modified file: $($entry.path). Use -Repair to back up and replace it."; continue }
    }
    $temporary = Join-Path $downloadDir ([Guid]::NewGuid().ToString() + '.part')
    if ($SourceDirectory) { Copy-Item -LiteralPath (Join-Path $SourceDirectory $entry.path) -Destination $temporary }
    else { Get-Download "$baseUrl/$($entry.path)" $temporary }
    if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $entry.sha256) { throw "SHA256 mismatch: $($entry.path)" }
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
    if (Test-Path -LiteralPath $target) {
        $backup = Join-Path $InstallDir ('.repair-backups/' + [Guid]::NewGuid().ToString() + '/' + $entry.path)
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force
        Copy-Item -LiteralPath $target -Destination $backup
    }
    Copy-Item -LiteralPath $temporary -Destination $target -Force
    Remove-Item -LiteralPath $temporary
    Write-Host "Restored: $($entry.path)"
}
$configPath = Join-Path $InstallDir 'config.local.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    $config = Get-Content -LiteralPath (Join-Path $InstallDir 'config.example.json') -Raw | ConvertFrom-Json
    if ($PortalUrl) {
        $portal = [Uri]$PortalUrl
        if (-not $portal.IsAbsoluteUri -or $portal.Scheme -notin @('http','https') -or $portal.UserInfo) { throw 'PortalUrl must be an HTTP(S) URL without credentials.' }
        $config.PORTAL_URL = $portal.AbsoluteUri
        $config.PORTAL_ALLOWED_HOSTS = $portal.DnsSafeHost
    }
    $config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
    Write-Host 'Created config.local.json (no username/password saved).'
}
$null = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($Mode -ne 'Manual' -and -not $SkipDependencies) {
    if (-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Use 64-bit PowerShell on Windows x64.' }
    $pythonDir = Join-Path $InstallDir '.runtime/python'
    $python = Join-Path $pythonDir 'python.exe'
    if (-not (Test-Path -LiteralPath $python)) {
        $page = Invoke-WebRequest -UseBasicParsing -Uri 'https://www.python.org/downloads/windows/' -TimeoutSec 120
        $pattern = 'https://www\.python\.org/ftp/python/(3\.13\.\d+)/python-\1-amd64\.exe'
        $releases = @([regex]::Matches($page.Content, $pattern) | ForEach-Object { [pscustomobject]@{ Version = [version]$_.Groups[1].Value; Url = $_.Value } } | Sort-Object Version -Descending)
        if (-not $releases.Count) { throw 'No official Python 3.13 x64 installer found. Check python.org availability.' }
        $installer = Join-Path $downloadDir 'python-installer.exe'
        Get-Download $releases[0].Url $installer
        $signature = Get-AuthenticodeSignature -LiteralPath $installer
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Python Software Foundation') { throw 'Python installer publisher signature verification failed.' }
        $arguments = '/quiet InstallAllUsers=0 Include_launcher=0 Include_test=0 PrependPath=0 TargetDir="' + $pythonDir + '"'
        $process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -notin @(0,3010)) { throw "Python installation failed: $($process.ExitCode)" }
        if (-not (Test-Path -LiteralPath $python)) { throw 'Python installation did not create python.exe.' }
    }
    Invoke-Python $python @('-c','import sys, venv; assert sys.version_info >= (3, 10)')
    $venvPython = Join-Path $InstallDir '.venv/Scripts/python.exe'
    if (-not (Test-Path -LiteralPath $venvPython)) { Invoke-Python $python @('-m','venv',(Join-Path $InstallDir '.venv')) }
    & $venvPython -m pip --version
    if ($LASTEXITCODE -ne 0) { Invoke-Python $venvPython @('-m','ensurepip','--upgrade') }
    if ($Mode -eq 'Auto') {
        Invoke-Python $venvPython @('-m','pip','install','-r',(Join-Path $InstallDir 'requirements.txt'))
        & $venvPython -c 'import playwright.sync_api'
        if ($LASTEXITCODE -ne 0) {
            Invoke-Python $venvPython @('-m','pip','install','--force-reinstall','-r',(Join-Path $InstallDir 'requirements.txt'))
        }
        Invoke-Python $venvPython @('-m','playwright','install','chromium')
        Invoke-Python $venvPython @('-c','from playwright.sync_api import sync_playwright; p=sync_playwright().start(); b=p.chromium.launch(headless=True); b.close(); p.stop()')
    }
}
Write-Host "Ready: $InstallDir"
if ($SkipDependencies) { Write-Warning 'Dependencies were skipped; this is file recovery only.' }
if ($Run) {
    if ($SkipDependencies -and $Mode -ne 'Manual') { throw 'Cannot run Auto/Server with skipped dependency checks.' }
    if ($Mode -eq 'Server') { Invoke-Python (Join-Path $InstallDir '.venv/Scripts/python.exe') @((Join-Path $InstallDir 'windows/esp32_server.py')) }
    else { & (Join-Path $InstallDir 'start_windows.ps1') -Mode $Mode -Ssid $Ssid -ConfigPath $configPath }
}
