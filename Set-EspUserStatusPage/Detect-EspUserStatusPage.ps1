<#
.SYNOPSIS
  Detection script for the user Enrollment Status Page coming back after the device was provisioned.

.DESCRIPTION
  Reads the FirstSync settings of every MDM enrollment. Reports an enrollment when the device is already provisioned but the user status page is not marked as skipped. Exits 1 if at least one enrollment needs the change, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinProvisionDays = 2
$MdmProviderId    = 'MS DM Server'

$PackageName = 'EspUserStatusPage'
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

$EnrollmentsRoot   = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
$TrackingSetupKey  = 'HKLM:\SOFTWARE\Microsoft\Windows\Autopilot\EnrollmentStatusTracking\Device\Setup'
$GuidPattern       = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
$SkipMarker        = -1

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
        $deviceSkip = $false
        if ($null -ne $values.SkipUserStatusPage) { $userSkip = ([int64]$values.SkipUserStatusPage -eq $SkipMarker) }
        if ($null -ne $values.SkipDeviceStatusPage) { $deviceSkip = ([int64]$values.SkipDeviceStatusPage -eq $SkipMarker) }
        $ageDays = 0
        $item = Get-Item -LiteralPath $firstSync -ErrorAction SilentlyContinue
        if ($null -ne $item) { $ageDays = [int]((Get-Date) - $item.LastWriteTime).TotalDays }
        $list += [pscustomobject]@{
            Guid        = $key.PSChildName
            Path        = $firstSync
            UserSkip    = $userSkip
            DeviceSkip  = $deviceSkip
            AgeDays     = $ageDays
            Provisioned = (Test-ProvisioningDone -AgeDays $ageDays)
        }
    }
    $list
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

    $ages = (($pending | ForEach-Object { $_.AgeDays }) -join ',')
    Exit-Script 1 "Drift | MdmEnrollments=$($esp.Count); UserPage=Shown; Pending=$($pending.Count); AgeDays=$ages"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
