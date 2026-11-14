<#
.SYNOPSIS
  Detection script for Intune MDM sync health.

.DESCRIPTION
  Reads the last successful OMA-DM session time. Exits 1 if the device has not synced within the threshold.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxHoursSinceSync = 24

$PackageName = 'MDMSyncHealth'
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

function Get-IntuneEnrollmentId {
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue | Where-Object {
        (Get-ItemProperty $_.PSPath -Name ProviderID -ErrorAction SilentlyContinue).ProviderID -eq 'MS DM Server'
    } | Select-Object -First 1 -ExpandProperty PSChildName
}

try {
    $issues = @()
    $enrollId = Get-IntuneEnrollmentId
    if (-not $enrollId) { Exit-Script 1 'No Intune MDM enrollment found (ProviderID MS DM Server)' }

    $last = $null
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts' -ErrorAction SilentlyContinue | ForEach-Object {
        $raw = (Get-ItemProperty (Join-Path $_.PSPath 'Protected\ConnInfo') -Name ServerLastSuccessTime -ErrorAction SilentlyContinue).ServerLastSuccessTime
        if ($raw) {
            try {
                $t = [datetime]::ParseExact($raw, "yyyyMMdd'T'HHmmss'Z'", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
                if (-not $last -or $t -gt $last) { $last = $t }
            } catch { }
        }
    }
    if (-not $last) { $issues += 'NoSuccessfulSyncRecorded'; $hours = -1 }
    else {
        $hours = [math]::Round(((Get-Date) - $last).TotalHours, 1)
        if ($hours -gt $MaxHoursSinceSync) { $issues += "LastSync=${hours}h" }
    }

    $push = Get-CimInstance Win32_Service -Filter "Name='dmwappushservice'" -ErrorAction SilentlyContinue
    if (-not $push) { $issues += 'dmwappushservice=Missing' }
    elseif ($push.StartMode -eq 'Disabled') { $issues += 'dmwappushservice=Disabled' }

    $task = Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\$enrollId\" -TaskName 'PushLaunch' -ErrorAction SilentlyContinue
    if (-not $task) { $issues += 'PushLaunch=Missing' } elseif ($task.State -eq 'Disabled') { $issues += 'PushLaunch=Disabled' }

    $summary = 'Enrollment={0}; LastSuccessUtc={1}; HoursAgo={2}' -f $enrollId, ($(if ($last) { $last.ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } else { 'n/a' })), $hours
    if ($issues) { Exit-Script 1 "Unhealthy ($($issues -join ',')) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
