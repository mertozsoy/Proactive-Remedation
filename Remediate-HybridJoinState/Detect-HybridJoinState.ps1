<#
.SYNOPSIS
  Detection script for Hybrid Entra join state.

.DESCRIPTION
  Reads dsregcmd output and flags domain joined devices that never completed Entra join, a failed DeviceAuthStatus and the AzureAdJoined plus WorkplaceJoined dual state. Exits 1 if any of these is found.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'HybridJoinState'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-DsregStatus {
    $map = @{}
    foreach ($line in (& dsregcmd.exe /status)) {
        if ($line -match '^\s*([A-Za-z]+)\s*:\s*(.+?)\s*$') { $map[$Matches[1]] = $Matches[2] }
    }
    return $map
}

try {
    $d = Get-DsregStatus
    $issues = @()
    $domain = $d['DomainJoined']; $entra = $d['AzureAdJoined']; $wpj = $d['WorkplaceJoined']; $auth = $d['DeviceAuthStatus']

    if ($domain -eq 'YES' -and $entra -ne 'YES') { $issues += 'HybridJoinPending' }
    if ($entra -eq 'YES' -and $auth -and $auth -ne 'SUCCESS') { $issues += "DeviceAuthStatus=$auth" }
    if ($entra -eq 'YES' -and $wpj -eq 'YES') { $issues += 'DualState(WorkplaceJoined)' }

    $summary = 'DomainJoined={0}; AzureAdJoined={1}; WorkplaceJoined={2}; DeviceAuth={3}; DeviceId={4}; Tenant={5}' -f `
        $domain, $entra, $wpj, $auth, $d['DeviceId'], $d['TenantName']
    if ($issues) { Exit-Script 1 "Unhealthy ($($issues -join ',')) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
