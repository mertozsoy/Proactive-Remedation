<#
.SYNOPSIS
  Detection script for physical disk health.

.DESCRIPTION
  Reads disk health and wear counters. Exits 1 if a disk is failing or worn. Report only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$WearThreshold   = 85
$MaxTemperatureC = 70

$PackageName = 'DiskHealth'
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
    $findings = @(); $info = @()
    foreach ($d in (Get-PhysicalDisk -ErrorAction Stop | Where-Object BusType -ne 'USB')) {
        $r = $null
        try { $r = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
        $tag = '{0} {1} {2}GB' -f $d.MediaType, $d.FriendlyName, [math]::Round($d.Size / 1GB)
        $info += '{0} Health={1} Wear={2} Temp={3}' -f $tag, $d.HealthStatus, $r.Wear, $r.Temperature

        if ($d.HealthStatus -ne 'Healthy') { $findings += "$tag Health=$($d.HealthStatus)" }
        if (($d.OperationalStatus | Where-Object { $_ -ne 'OK' })) { $findings += "$tag Op=$($d.OperationalStatus -join '/')" }
        if ($r) {
            if ($r.Wear -ge $WearThreshold) { $findings += "$tag Wear=$($r.Wear)%" }
            if ($r.ReadErrorsUncorrected -gt 0 -or $r.WriteErrorsUncorrected -gt 0) { $findings += "$tag UncorrectedErrors R=$($r.ReadErrorsUncorrected) W=$($r.WriteErrorsUncorrected)" }
            if ($r.Temperature -ge $MaxTemperatureC) { $findings += "$tag Temp=$($r.Temperature)C" }
        }
    }
    if ($findings) { Exit-Script 1 "AtRisk | $($findings -join ' ; ')" }
    Exit-Script 0 "Healthy | $($info -join ' ; ')"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
