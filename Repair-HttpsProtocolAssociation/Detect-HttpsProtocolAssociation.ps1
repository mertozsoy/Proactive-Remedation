<#
.SYNOPSIS
  Detection script for http and https protocol associations that point to a missing application.

.DESCRIPTION
  Reads the per-user UserChoice entry for http and https, resolves the ProgId shell command and checks that the handler executable exists. Reports the Microsoft Edge package state for the user. Exits 1 when an association points to a missing application, 0 otherwise. Does not change anything.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$Protocols = @('https', 'http')
$ReportEdgeState = $true

$PackageName = 'HttpsProtocolAssociation'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $directory = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null }
        Add-Content -LiteralPath $LogFile -Value ('{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message) -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function ConvertTo-ExecutablePath {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Command.Trim())
    if ($expanded.StartsWith('"')) {
        $end = $expanded.IndexOf('"', 1)
        if ($end -gt 1) { return $expanded.Substring(1, $end - 1) }
        return ''
    }
    $match = [regex]::Match($expanded, '^(.*?\.exe)(\s|$)')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return ($expanded -split '\s+')[0]
}

function Get-ProtocolAssociation {
    param([string]$Protocol)
    $association = [pscustomobject]@{
        Protocol   = $Protocol
        ProgId     = ''
        Command    = ''
        Executable = ''
        State      = 'Missing'
    }
    $keyPath = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\{0}\UserChoice' -f $Protocol
    if (-not (Test-Path -LiteralPath $keyPath)) { return $association }
    $values = Get-ItemProperty -LiteralPath $keyPath -ErrorAction Stop
    $progId = [string]$values.ProgId
    if ([string]::IsNullOrWhiteSpace($progId)) { $association.State = 'NoProgId'; return $association }
    $association.ProgId = $progId
    if ([string]::IsNullOrWhiteSpace([string]$values.Hash)) { $association.State = 'NoHash'; return $association }
    $commandKey = 'Registry::HKEY_CLASSES_ROOT\{0}\shell\open\command' -f $progId
    $command = [string](Get-ItemProperty -LiteralPath $commandKey -ErrorAction SilentlyContinue).'(default)'
    if ([string]::IsNullOrWhiteSpace($command)) { $association.State = 'NoCommand'; return $association }
    $association.Command = $command
    $executable = ConvertTo-ExecutablePath -Command $command
    $association.Executable = $executable
    if ([string]::IsNullOrWhiteSpace($executable) -or -not (Test-Path -LiteralPath $executable)) {
        $association.State = 'MissingApp'
        return $association
    }
    $association.State = 'Valid'
    return $association
}

function Format-Association {
    param($Association)
    if ($null -eq $Association) { return 'Unknown' }
    if ($Association.State -eq 'Missing') { return 'Missing' }
    return ('{0}:{1}' -f $Association.State, $Association.ProgId)
}

function Get-EdgeState {
    $candidates = @()
    $appPath = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' -ErrorAction SilentlyContinue).'(default)'
    if (-not [string]::IsNullOrWhiteSpace([string]$appPath)) { $candidates += [string]$appPath }
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) { $candidates += (Join-Path $programFilesX86 'Microsoft\Edge\Application\msedge.exe') }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) { $candidates += (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe') }
    $installed = $false
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { $installed = $true; break }
    }
    if (-not $installed) { return 'NotInstalled' }
    $registered = $false
    try {
        $package = @(Get-AppxPackage -Name 'Microsoft.MicrosoftEdge.Stable*' -ErrorAction Stop | Select-Object -First 1)
        $registered = $package.Count -gt 0
    } catch { $registered = $false }
    if ($registered) { return 'Registered' }
    return 'NotRegistered'
}

try {
    $ErrorActionPreference = 'Stop'
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem -or [System.Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
        Exit-Script 0 'NotApplicable | Context=NonUserSession'
    }
    $associations = @()
    foreach ($protocol in $Protocols) { $associations += Get-ProtocolAssociation -Protocol $protocol }
    $broken = @($associations | Where-Object { $_.State -ne 'Valid' -and $_.State -ne 'Missing' })
    $edge = 'Skipped'
    if ($ReportEdgeState) { $edge = Get-EdgeState }
    $https = $associations | Where-Object { $_.Protocol -eq 'https' } | Select-Object -First 1
    $http = $associations | Where-Object { $_.Protocol -eq 'http' } | Select-Object -First 1
    $summary = 'Https={0}; Http={1}; Edge={2}' -f (Format-Association -Association $https), (Format-Association -Association $http), $edge
    if ($broken.Count -eq 0) { Exit-Script 0 "Healthy | $summary" }
    $reasons = @($broken | ForEach-Object { 'Broken:' + $_.Protocol })
    Exit-Script 1 "Drift | $summary; Reason=$($reasons -join ',')"
} catch { Exit-Script 1 ('Error: DetectionFailed | HResult={0}' -f $_.Exception.HResult) }
