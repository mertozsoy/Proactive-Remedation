<#
.SYNOPSIS
  Remediation script for BitLocker suspension during an approved BIOS maintenance window.

.DESCRIPTION
  Restores a finite suspend reboot count and verifies protection and the remaining count.
  Requires explicit approval after recovery escrow and conflicting management exclusions are confirmed.
  Exits 0 after verification or when not applicable and 1 for unresolved drift or errors.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $false
$MaintenanceStartUtc = ''
$MaintenanceEndUtc = ''
$RebootCount = 1

$PackageName = 'BitLockerBiosSuspendCount'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Test-MaintenanceWindow {
    if (-not $MaintenanceStartUtc -or -not $MaintenanceEndUtc) {
        Exit-Script 0 'NotApplicable | Reason=MaintenanceWindowNotConfigured'
    }
    $style = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $start = [datetime]::ParseExact($MaintenanceStartUtc, "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture, $style)
    $end = [datetime]::ParseExact($MaintenanceEndUtc, "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture, $style)
    if ($end -le $start -or ($end - $start).TotalHours -gt 4 -or $RebootCount -lt 1 -or $RebootCount -gt 15) {
        Exit-Script 1 'Failed | Reason=InvalidWindowOrRebootCount'
    }
    $now = [datetime]::UtcNow
    if ($now -lt $start -or $now -ge $end) { Exit-Script 0 'NotApplicable | Reason=OutsideMaintenanceWindow' }
    $boot = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
    if ($null -eq $boot) { throw 'BootTimeUnavailable' }
    if ($boot.ToUniversalTime() -ge $start) { Exit-Script 0 'NotApplicable | Reason=MaintenanceRebootObserved' }
}

function Get-SuspensionState {
    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    if ($volume.VolumeStatus -eq 'FullyDecrypted') { Exit-Script 0 'NotApplicable | Reason=OsVolumeNotEncrypted' }
    if ($volume.VolumeStatus -ne 'FullyEncrypted' -or $volume.LockStatus -ne 'Unlocked') {
        Exit-Script 1 'Failed | Reason=VolumeNotReady'
    }
    $types = @($volume.KeyProtector | ForEach-Object { [string]$_.KeyProtectorType })
    if (-not ($types | Where-Object { $_ -like 'Tpm*' }) -or $types -notcontains 'RecoveryPassword') {
        Exit-Script 1 'Failed | Reason=RequiredProtectorsMissing'
    }
    if ($volume.ProtectionStatus -eq 'On') { return [pscustomobject]@{ Protection = 'On'; Count = -1 } }
    if ($volume.ProtectionStatus -ne 'Off') { throw 'ProtectionStatusUnknown' }
    $encryptedVolume = @(Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter ("DriveLetter='{0}'" -f $env:SystemDrive) -ErrorAction Stop)
    if ($encryptedVolume.Count -ne 1) { throw 'OsVolumeAmbiguous' }
    $result = Invoke-CimMethod -InputObject $encryptedVolume[0] -MethodName GetSuspendCount -ErrorAction Stop
    if ($null -eq $result.ReturnValue -or $result.ReturnValue -ne 0 -or $null -eq $result.SuspendCount) { throw 'SuspendCountUnavailable' }
    return [pscustomobject]@{ Protection = 'Off'; Count = [int]$result.SuspendCount }
}

try {
    Test-MaintenanceWindow
    if (-not (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
        Exit-Script 0 'NotApplicable | Reason=BitLockerModuleUnavailable'
    }
    $state = Get-SuspensionState
    if ($state.Protection -eq 'Off' -and $state.Count -eq $RebootCount) {
        Exit-Script 0 "Healthy | Protection=Off; SuspendCount=$($state.Count); Window=Active"
    }
    if (-not $EnableRemediation) {
        Exit-Script 1 "Blocked | Reason=ApprovalRequired; Protection=$($state.Protection); Expected=$RebootCount"
    }
    Test-MaintenanceWindow
    Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount $RebootCount -ErrorAction Stop | Out-Null
    $after = Get-SuspensionState
    if ($after.Protection -ne 'Off' -or $after.Count -ne $RebootCount) {
        Exit-Script 1 "Failed | Reason=Verification; Protection=$($after.Protection); SuspendCount=$($after.Count)"
    }
    Exit-Script 0 "Fixed | Protection=Off; SuspendCount=$($after.Count); Window=Active"
}
catch { Exit-Script 1 ("Error: RemediationFailed | HResult={0}" -f $_.Exception.HResult) }
