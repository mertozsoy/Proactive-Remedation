<#
.SYNOPSIS
  Remediation script that marks the user Enrollment Status Page as skipped on provisioned devices.

.DESCRIPTION
  Finds MDM enrollments where the device is already provisioned but the user status page is not marked as skipped. Exports a backup of the FirstSync key and writes SkipUserStatusPage as 0xffffffff. The write is on by default and can be turned off with $EnableRemediation. Exits 0 when nothing is left to fix, 1 when the write fails.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation    = $true
$SkipDeviceStatusPage = $false
$MinProvisionDays     = 2
$MdmProviderId        = 'MS DM Server'

$PackageName = 'EspUserStatusPage'
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

$EnrollmentsRoot  = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
$TrackingSetupKey = 'HKLM:\SOFTWARE\Microsoft\Windows\Autopilot\EnrollmentStatusTracking\Device\Setup'
$GuidPattern      = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
$SkipMarker       = -1
$BackupRoot       = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

function Test-ProvisioningDone { param([int]$AgeDays)
    $tracking = Get-ItemProperty -LiteralPath $TrackingSetupKey -Name 'HasProvisioningCompleted' -ErrorAction SilentlyContinue
    if ($null -ne $tracking -and [int]$tracking.HasProvisioningCompleted -eq 1) { return $true }
    return ($AgeDays -ge $MinProvisionDays)
}

function Get-EspEnrollment {
    $list = @()
    foreach ($key in Get-ChildItem -LiteralPath $EnrollmentsRoot -ErrorAction SilentlyContinue) {
        if ($key.PSChildName -notmatch $GuidPattern) { continue }
        $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if ([string]$props.ProviderID -ne $MdmProviderId) { continue }
        $firstSync = Join-Path $key.PSPath 'FirstSync'
        if (-not (Test-Path -LiteralPath $firstSync)) { continue }
        $values = Get-ItemProperty -LiteralPath $firstSync -ErrorAction SilentlyContinue
        $userSkip = $false
        if ($null -ne $values.SkipUserStatusPage) { $userSkip = ([int64]$values.SkipUserStatusPage -eq $SkipMarker) }
        $ageDays = 0
        $item = Get-Item -LiteralPath $firstSync -ErrorAction SilentlyContinue
        if ($null -ne $item) { $ageDays = [int]((Get-Date) - $item.LastWriteTime).TotalDays }
        $list += [pscustomobject]@{
            Guid        = $key.PSChildName
            Path        = $firstSync
            UserSkip    = $userSkip
            AgeDays     = $ageDays
            Provisioned = (Test-ProvisioningDone -AgeDays $ageDays)
        }
    }
    $list
}

function Save-FirstSyncBackup { param([string]$EnrollmentPath, [string]$Guid)
    $null = New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop
    $file = Join-Path $BackupRoot ('EspFirstSync-{0}-{1}.reg' -f $Guid.Substring(0, 8), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $regPath = 'HKLM\' + $EnrollmentPath.Substring($EnrollmentPath.IndexOf('SOFTWARE'))
    $output = & reg.exe export $regPath $file /y 2>&1
    if ($LASTEXITCODE -ne 0) { throw "reg export failed with exit code $LASTEXITCODE ($($output -join ' '))" }
    $file
}

try {
    if (-not (Test-Path -LiteralPath $EnrollmentsRoot)) { Exit-Script 0 'NotApplicable | Enrollments key not found' }

    $esp = @(Get-EspEnrollment)
    if ($esp.Count -eq 0) { Exit-Script 0 'NotApplicable | No MDM enrollment with ESP settings' }

    $pending = @($esp | Where-Object { -not $_.UserSkip -and $_.Provisioned })
    if ($pending.Count -eq 0) {
        $active = @($esp | Where-Object { -not $_.Provisioned }).Count
        if ($active -gt 0) { Exit-Script 0 "Healthy | MdmEnrollments=$($esp.Count); UserPage=Shown; Provisioning=Active" }
        Exit-Script 0 "Healthy | MdmEnrollments=$($esp.Count); UserPage=Skipped"
    }

    if (-not $EnableRemediation) {
        Exit-Script 0 "ReportOnly | Pending=$($pending.Count); Toggle=EnableRemediation"
    }

    $fixed    = 0
    $failed   = 0
    $backup   = $null
    foreach ($entry in $pending) {
        $entryBackup = Save-FirstSyncBackup -EnrollmentPath $entry.Path -Guid $entry.Guid
        if (-not $backup) { $backup = $entryBackup }
        Set-ItemProperty -LiteralPath $entry.Path -Name 'SkipUserStatusPage' -Value $SkipMarker -Type DWord -ErrorAction Stop
        if ($SkipDeviceStatusPage) {
            Set-ItemProperty -LiteralPath $entry.Path -Name 'SkipDeviceStatusPage' -Value $SkipMarker -Type DWord -ErrorAction Stop
        }
        $after = Get-ItemProperty -LiteralPath $entry.Path -ErrorAction SilentlyContinue
        if ($null -ne $after -and ([int64]$after.SkipUserStatusPage -eq $SkipMarker)) {
            Write-IRTLog "SkipUserStatusPage set for enrollment $($entry.Guid)"
            $fixed++
        }
        else {
            Write-IRTLog "SkipUserStatusPage did not stay set for enrollment $($entry.Guid)"
            $failed++
        }
    }

    $deviceNote = 'No'
    if ($SkipDeviceStatusPage) { $deviceNote = 'Yes' }

    if ($failed -gt 0) { Exit-Script 1 "Failed | Updated=$fixed; Failed=$failed; SkipUserStatusPage=0xffffffff; Backup=$backup" }
    Exit-Script 0 "Fixed | Updated=$fixed; SkipUserStatusPage=0xffffffff; SkipDeviceStatusPage=$deviceNote; Backup=$backup"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
