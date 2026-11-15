<#
.SYNOPSIS
  Remediation script that refreshes stale Group Policy on domain joined devices.

.DESCRIPTION
  Runs gpupdate against the computer policy store and waits for a new successful client-side extension event. Exits 0 when policy processing completed, 1 when it did not.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxAgeDays         = 7
$GpLogName          = 'Microsoft-Windows-GroupPolicy/Operational'
$SuccessIds         = @(5016)
$GpupdateWaitSec    = 600
$VerifyTimeoutSec   = 120
$VerifyPollSec      = 10
$CheckSecureChannel = $true

$PackageName = 'StaleGroupPolicy'
$Phase       = 'Remediate'
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
function Get-GpSuccessAfter { param([string]$LogName, [int[]]$EventId, [datetime]$StartTime)
    try { return Get-WinEvent -FilterHashtable @{ LogName = $LogName; Id = $EventId; StartTime = $StartTime } -MaxEvents 1 -ErrorAction Stop }
    catch { return $null }
}

try {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if (-not $computerSystem.PartOfDomain) { Exit-Script 0 'NotApplicable | NotDomainJoined' }

    $log = $null
    try { $log = Get-WinEvent -ListLog $GpLogName -ErrorAction Stop } catch { $log = $null }
    if ($null -eq $log) { Exit-Script 0 'NotApplicable | GroupPolicy operational log not found' }
    if (-not $log.IsEnabled) { Exit-Script 0 'NotApplicable | GroupPolicy operational log disabled' }

    $current = Get-GpLastSuccess -LogName $GpLogName -EventId $SuccessIds
    if ($null -ne $current) {
        $currentAge = [int][math]::Floor(((Get-Date) - $current.TimeCreated).TotalDays)
        if ($currentAge -lt $MaxAgeDays) {
            Exit-Script 0 "Healthy | LastSuccess=$($current.TimeCreated.ToString('yyyy-MM-dd HH:mm')); AgeDays=$currentAge; ThresholdDays=$MaxAgeDays"
        }
    }

    $gpupdate = Join-Path $env:SystemRoot 'System32\gpupdate.exe'
    if (-not (Test-Path -LiteralPath $gpupdate)) { Exit-Script 1 'Error: gpupdate.exe not found' }

    $startTime = Get-Date
    Write-IRTLog 'Starting gpupdate /force /target:computer'
    $gpupdateProcess = Start-Process -FilePath $gpupdate -ArgumentList "/force /target:computer /wait:$GpupdateWaitSec" -Wait -PassThru -WindowStyle Hidden
    $gpExit = $gpupdateProcess.ExitCode
    Write-IRTLog "gpupdate exit code $gpExit"

    $recent  = $null
    $deadline = (Get-Date).AddSeconds($VerifyTimeoutSec)
    do {
        $recent = Get-GpSuccessAfter -LogName $GpLogName -EventId $SuccessIds -StartTime $startTime.AddSeconds(-5)
        if ($null -eq $recent) { Start-Sleep -Seconds $VerifyPollSec }
    } while ($null -eq $recent -and (Get-Date) -lt $deadline)

    $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
    if ($null -ne $recent) {
        Exit-Script 0 "Fixed | GpupdateExit=$gpExit; LastSuccess=$($recent.TimeCreated.ToString('yyyy-MM-dd HH:mm')); ElapsedSec=$elapsed"
    }

    $secureChannel = 'Unknown'
    if ($CheckSecureChannel) {
        try {
            if (Test-ComputerSecureChannel -ErrorAction Stop) { $secureChannel = 'True' } else { $secureChannel = 'False' }
        }
        catch { $secureChannel = 'Unknown' }
    }
    Exit-Script 1 "Failed | GpupdateExit=$gpExit; LastSuccess=None; SecureChannel=$secureChannel; ElapsedSec=$elapsed"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
