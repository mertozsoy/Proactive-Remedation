<#
.SYNOPSIS
  Detection script for stale Group Policy processing on domain joined devices.

.DESCRIPTION
  Reads the newest Group Policy operational event that reports a completed client-side extension and compares its age with $MaxAgeDays. Exits 1 if the last success is older than the threshold, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxAgeDays = 7
$GpLogName  = 'Microsoft-Windows-GroupPolicy/Operational'
$SuccessIds = @(5016)

$PackageName = 'StaleGroupPolicy'
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

function Get-GpLastSuccess { param([string]$LogName, [int[]]$EventId)
    try { return Get-WinEvent -FilterHashtable @{ LogName = $LogName; Id = $EventId } -MaxEvents 1 -ErrorAction Stop }
    catch { return $null }
}

try {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if (-not $computerSystem.PartOfDomain) { Exit-Script 0 'NotApplicable | NotDomainJoined' }

    $log = $null
    try { $log = Get-WinEvent -ListLog $GpLogName -ErrorAction Stop } catch { $log = $null }
    if ($null -eq $log) { Exit-Script 0 'NotApplicable | GroupPolicy operational log not found' }
    if (-not $log.IsEnabled) { Exit-Script 0 'NotApplicable | GroupPolicy operational log disabled' }

    $last = Get-GpLastSuccess -LogName $GpLogName -EventId $SuccessIds
    if ($null -eq $last) { Exit-Script 1 "Stale | LastSuccess=None; ThresholdDays=$MaxAgeDays" }

    $ageDays  = [int][math]::Floor(((Get-Date) - $last.TimeCreated).TotalDays)
    $lastText = $last.TimeCreated.ToString('yyyy-MM-dd HH:mm')
    if ($ageDays -ge $MaxAgeDays) {
        Exit-Script 1 "Stale | LastSuccess=$lastText; AgeDays=$ageDays; ThresholdDays=$MaxAgeDays"
    }
    Exit-Script 0 "Healthy | LastSuccess=$lastText; AgeDays=$ageDays; ThresholdDays=$MaxAgeDays"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
