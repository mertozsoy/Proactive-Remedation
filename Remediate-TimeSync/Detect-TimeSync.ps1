<#
.SYNOPSIS
  Detection script for Windows time synchronization.

.DESCRIPTION
  Checks the Windows Time service, time source and last successful sync. Exits 1 if time sync is broken.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxOffsetSeconds = 60

$PackageName = 'TimeSync'
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

function Get-TimeOffsetSeconds { param([string]$Peer)
    $out = & w32tm.exe /stripchart /computer:$Peer /dataonly /samples:1 2>$null
    foreach ($line in $out) {
        if ($line -match '([+-]\d+[\.,]\d+)s\s*$') { return [math]::Abs([double]($Matches[1] -replace ',', '.')) }
    }
    return $null
}

try {
    $issues = @()
    $svc = Get-CimInstance Win32_Service -Filter "Name='W32Time'"
    if ($svc.StartMode -eq 'Disabled') { $issues += 'W32Time=Disabled' }
    if ($svc.State -ne 'Running')      { $issues += "W32Time=$($svc.State)" }

    $source = $null; $offset = $null
    if ($svc.State -eq 'Running') {
        $source = ((& w32tm.exe /query /source 2>$null) | Select-Object -First 1)
        if ($source) { $source = ($source.Trim() -split ',')[0] }
        if (-not $source -or $source -match '\s') { $issues += "LocalClockSource($source)" }
        else {
            $offset = Get-TimeOffsetSeconds -Peer $source
            if ($null -ne $offset -and $offset -gt $MaxOffsetSeconds) { $issues += "Offset=${offset}s" }
        }
    }

    $summary = 'Source={0}; OffsetSec={1}; Service={2}/{3}' -f $source, ($(if ($null -ne $offset) { [math]::Round($offset, 3) } else { 'unreachable' })), $svc.StartMode, $svc.State
    if ($issues) { Exit-Script 1 "Unhealthy ($($issues -join ',')) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
