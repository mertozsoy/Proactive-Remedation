<#
.SYNOPSIS
  Detection script for drive mappings to retired servers.

.DESCRIPTION
  Matches SMB drive mappings against an exact server allowlist without testing connectivity.
  Exits 1 if retired mappings exist or an error occurs, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$RetiredServers = @()
$PolicyReviewedServers = @()

$PackageName = 'RetiredServerDrives'
$Phase = 'Detect'
$LogFile = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try {
        $logDir = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null }
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Get-RetiredMapping {
    foreach ($mapping in @(Get-SmbMapping -ErrorAction Stop)) {
        if ($mapping.LocalPath -notmatch '^[A-Za-z]:$') { continue }
        if ($mapping.RemotePath -notmatch '^\\\\([^\\]+)\\[^\\]+') { continue }
        $server = $Matches[1].ToLowerInvariant()
        if ($RetiredServers -contains $server) {
            [pscustomobject]@{
                Mapping = $mapping
                Letter = $mapping.LocalPath
                Approved = ($PolicyReviewedServers -contains $server)
            }
        }
    }
}

try {
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { Exit-Script 0 'NotApplicable | Context=System' }
    if ($RetiredServers.Count -eq 0) { Exit-Script 0 'NotApplicable | RetiredServers=None' }
    foreach ($server in @($RetiredServers) + @($PolicyReviewedServers)) {
        if ($server -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$' -or $server.EndsWith('.')) { Exit-Script 1 'Failed | Reason=InvalidServerList' }
    }
    $found = @(Get-RetiredMapping)
    if ($found.Count -eq 0) { Exit-Script 0 'Healthy | RetiredMappings=0' }
    $blocked = @($found | Where-Object { -not $_.Approved }).Count
    $letters = (@($found | ForEach-Object { $_.Letter } | Sort-Object -Unique) -join ',')
    Exit-Script 1 "Drift | RetiredMappings=$($found.Count); Drives=$letters; PolicyReviewRequired=$blocked"
} catch { Exit-Script 1 ('Error: Failed | Reason=InspectionError; HResult={0}' -f $_.Exception.HResult) }
