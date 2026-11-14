<#
.SYNOPSIS
  Detection script for pending restarts and long uptime.

.DESCRIPTION
  Checks pending restart flags and uptime. Exits 1 if a restart is pending or uptime is over the limit. Report only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxUptimeDays = 14

$PackageName = 'PendingReboot'
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
    $reasons = New-Object System.Collections.Generic.List[string]

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons.Add('CBS') }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons.Add('WindowsUpdate') }

    $pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($pfro) { $reasons.Add("FileRename($(@($pfro | Where-Object { $_ }).Count))") }

    $active  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction SilentlyContinue).ComputerName
    $pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction SilentlyContinue).ComputerName
    if ($active -and $pending -and ($active -ne $pending)) { $reasons.Add("Rename($active->$pending)") }

    try {
        $ccm = Invoke-CimMethod -Namespace 'root\ccm\ClientSDK' -ClassName 'CCM_ClientUtilities' -MethodName 'DetermineIfRebootPending' -ErrorAction Stop
        if ($ccm.RebootPending -or $ccm.IsHardRebootPending) { $reasons.Add('ConfigMgr') }
    } catch { }

    $os     = Get-CimInstance Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime
    $days   = [math]::Round($uptime.TotalDays, 1)
    if ($days -gt $MaxUptimeDays) { $reasons.Add("Uptime>$MaxUptimeDays d") }

    $summary = 'UptimeDays={0}; LastBoot={1:yyyy-MM-dd HH:mm}; Reasons={2}' -f $days, $os.LastBootUpTime, ($(if ($reasons.Count) { $reasons -join ',' } else { 'None' }))
    if ($reasons.Count -gt 0) { Exit-Script 1 "RebootNeeded | $summary" }
    Exit-Script 0 "OK | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
