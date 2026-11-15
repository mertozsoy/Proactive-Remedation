<#
.SYNOPSIS
  Detection script for omadmclient.exe processes that stayed running too long.

.DESCRIPTION
  Reads every running omadmclient.exe process and measures its running time. A healthy
  OMA-DM session ends in minutes. Exits 1 if at least one process is older than the
  threshold, 0 if none.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$StuckMinutes = 30
$MaxInstances = 1
$MaxListedPids = 5

$PackageName = 'OmadmClient'
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
function Get-OmadmInstance { param([string]$Name)
    $now = Get-Date
    @(Get-CimInstance -ClassName Win32_Process -Filter "Name = '$Name'" -ErrorAction Stop | ForEach-Object {
        $age = -1
        if ($_.CreationDate) {
            $age = [int][math]::Floor(($now - $_.CreationDate).TotalMinutes)
        }
        [pscustomobject]@{
            ProcessId    = [int]$_.ProcessId
            CreationDate = $_.CreationDate
            AgeMinutes   = $age
        }
    })
}
try {
    $clientPath = Join-Path $env:SystemRoot 'System32\omadmclient.exe'
    if (-not (Test-Path -LiteralPath $clientPath -ErrorAction Stop)) { Exit-Script 0 'NotApplicable | OmaDmClient=Missing' }

    $instances = @(Get-OmadmInstance -Name 'omadmclient.exe')
    $stuck = @($instances | Where-Object { $_.AgeMinutes -ge $StuckMinutes })
    $oldest = 0
    if ($instances.Count -gt 0) {
        $oldest = [int](($instances | Measure-Object -Property AgeMinutes -Maximum).Maximum)
    }
    $overLimit = $instances.Count -gt $MaxInstances

    foreach ($instance in $instances) {
        Write-IRTLog ('ProcessId={0} AgeMinutes={1} Stuck={2}' -f $instance.ProcessId, $instance.AgeMinutes, ($instance.AgeMinutes -ge $StuckMinutes))
    }

    if ($stuck.Count -eq 0) {
        Exit-Script 0 "Healthy | Instances=$($instances.Count); OldestMinutes=$oldest; ThresholdMinutes=$StuckMinutes; OverLimit=$overLimit"
    }

    $listed = @($stuck | Sort-Object AgeMinutes -Descending | Select-Object -First $MaxListedPids | ForEach-Object { '{0}({1}m)' -f $_.ProcessId, $_.AgeMinutes })
    $more = [math]::Max(0, $stuck.Count - $MaxListedPids)
    $pidText = $listed -join ','
    if ($more -gt 0) { $pidText += ",+$more" }

    Exit-Script 1 "Drift | Instances=$($instances.Count); Stuck=$($stuck.Count); OldestMinutes=$oldest; ThresholdMinutes=$StuckMinutes; Pids=$pidText"
}
catch { Exit-Script 1 "Error | Type=$($_.Exception.GetType().Name); Action=InspectOmadmClient" }
