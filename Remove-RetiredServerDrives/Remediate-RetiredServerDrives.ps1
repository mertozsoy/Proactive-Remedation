<#
.SYNOPSIS
  Remediation script for drive mappings to retired servers.

.DESCRIPTION
  Removes only allowlisted SMB drive mappings approved after policy review, including persistent mappings.
  Exits 0 if no retired mapping remains, 1 if blocked, removal fails or verification fails.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$RetiredServers = @()
$PolicyReviewedServers = @()

$PackageName = 'RetiredServerDrives'
$Phase = 'Remediate'
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
    $removed = 0
    $errors = 0
    $blocked = @($found | Where-Object { -not $_.Approved }).Count
    foreach ($drive in $found) {
        if (-not $drive.Approved) { continue }
        try {
            $current = @(Get-SmbMapping -ErrorAction Stop | Where-Object { $_.LocalPath -eq $drive.Letter })
            if ($current.Count -eq 0) { continue }
            if ($current.Count -ne 1 -or $current[0].RemotePath -ne $drive.Mapping.RemotePath) {
                $errors++
                Write-IRTLog "Skipped | Drive=$($drive.Letter); Reason=MappingChanged" 'WARN'
                continue
            }
            Remove-SmbMapping -InputObject $current[0] -UpdateProfile -Force -Confirm:$false -ErrorAction Stop
            $removed++
            Write-IRTLog "Removed | Drive=$($drive.Letter)"
        } catch {
            $errors++
            Write-IRTLog ('Failed | Drive={0}; HResult={1}' -f $drive.Letter, $_.Exception.HResult) 'ERROR'
        }
    }
    $remaining = @(Get-RetiredMapping)
    if ($remaining.Count -eq 0 -and $errors -eq 0) { Exit-Script 0 "Fixed | Removed=$removed; Remaining=0" }
    Exit-Script 1 "Failed | Removed=$removed; Remaining=$($remaining.Count); PolicyReviewRequired=$blocked; Errors=$errors"
} catch { Exit-Script 1 ('Error: Failed | Reason=RemediationError; HResult={0}' -f $_.Exception.HResult) }
