<#
.SYNOPSIS
  Detection script for a missing or damaged machine-wide WebView2 Runtime.

.DESCRIPTION
  Checks Evergreen registration, runtime files and the executable signature.
  Exits 1 for missing or damaged runtime files, 0 when the checks pass.
  Does not test application startup or inspect per-user and Fixed Version runtimes.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RuntimeRoots = @()

$PackageName = 'WebView2Runtime'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Get-RuntimeState {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry32)
    try {
        $key = $base.OpenSubKey('SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}')
        $raw = ''
        if ($null -ne $key) {
            try { $raw = [string]$key.GetValue('pv', '') } finally { $key.Dispose() }
        }
    } finally { $base.Dispose() }
    $version = $null
    if ($raw -notmatch '^\d+\.\d+\.\d+\.\d+$' -or -not [version]::TryParse($raw, [ref]$version) -or $version -le [version]'0.0.0.0') {
        return [pscustomobject]@{ Healthy = $false; Reason = 'RegistrationMissing'; Version = 'None'; Registered = $false }
    }
    foreach ($root in $RuntimeRoots) {
        $directory = Join-Path $root $raw
        $executable = Join-Path $directory 'msedgewebview2.exe'
        $library = Join-Path $directory 'msedge.dll'
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf -ErrorAction Stop)) { continue }
        if (-not (Test-Path -LiteralPath $library -PathType Leaf -ErrorAction Stop)) { continue }
        if ((Get-Item -LiteralPath $library -ErrorAction Stop).Length -eq 0) { continue }
        $signature = Get-AuthenticodeSignature -LiteralPath $executable -ErrorAction Stop
        if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate) {
            return [pscustomobject]@{ Healthy = $false; Reason = "Signature$($signature.Status)"; Version = $raw; Registered = $true }
        }
        $publisher = $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
        if ($publisher -ne 'Microsoft Corporation') {
            return [pscustomobject]@{ Healthy = $false; Reason = 'UnexpectedPublisher'; Version = $raw; Registered = $true }
        }
        return [pscustomobject]@{ Healthy = $true; Reason = 'FilesVerified'; Version = $raw; Registered = $true }
    }
    return [pscustomobject]@{ Healthy = $false; Reason = 'RuntimeFilesMissing'; Version = $raw; Registered = $true }
}

try {
    $ErrorActionPreference = 'Stop'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    if ($RuntimeRoots.Count -eq 0) {
        $programFiles = $env:ProgramFiles
        if ([Environment]::Is64BitOperatingSystem) { $programFiles = ${env:ProgramFiles(x86)} }
        $RuntimeRoots = @(Join-Path $programFiles 'Microsoft\EdgeWebView\Application')
    }
    $state = Get-RuntimeState
    if ($state.Healthy) { Exit-Script 0 "Healthy | Version=$($state.Version); Check=FilesVerified" }
    Exit-Script 1 "Drift | Version=$($state.Version); Reason=$($state.Reason)"
} catch { Exit-Script 1 "Error: Failed | Reason=InspectionError; HResult=$($_.Exception.HResult)" }
