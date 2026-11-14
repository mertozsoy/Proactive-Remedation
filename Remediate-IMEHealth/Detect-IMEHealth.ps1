<#
.SYNOPSIS
  Detection script for Intune Management Extension health.

.DESCRIPTION
  Checks the IME service start type and whether the IME log is still being written. Exits 1 if the start type is wrong or the log is stale.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxLogAgeHours = 12

$PackageName = 'IMEHealth'
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

try {
    $svc = Get-CimInstance Win32_Service -Filter "Name='IntuneManagementExtension'" -ErrorAction Stop
    if (-not $svc) { Exit-Script 1 'IME service not installed' }

    $imeLog = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log'
    $ageH   = if (Test-Path $imeLog) { [math]::Round(((Get-Date) - (Get-Item $imeLog).LastWriteTime).TotalHours, 1) } else { -1 }

    $issues = @()
    if ($svc.StartMode -ne 'Auto') { $issues += "StartMode=$($svc.StartMode)" }
    if ($svc.State -ne 'Running')  { $issues += "State=$($svc.State)" }
    if ($ageH -lt 0)               { $issues += 'MainLogMissing' }
    elseif ($ageH -gt $MaxLogAgeHours) { $issues += "MainLogStale=${ageH}h" }

    $summary = 'StartMode={0}; State={1}; LogAgeHours={2}' -f $svc.StartMode, $svc.State, $ageH
    if ($issues) { Exit-Script 1 "Unhealthy ($($issues -join ',')) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
