<#
.SYNOPSIS
  Detection script for BitLocker protection on the OS drive.

.DESCRIPTION
  Checks for suspended protection, a missing recovery password and a missing Entra ID backup. Exits 1 if one of them needs fixing.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$script:Phase = 'Detect'

$ErrorActionPreference = 'Stop'

if ($MyInvocation.InvocationName -ne '.' -and $env:PROCESSOR_ARCHITEW6432 -in @('AMD64', 'ARM64')) {
    $ps64 = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $ps64) {
        & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath
        exit $LASTEXITCODE
    }
}

function Write-RemLog {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    try {
        $dir = $script:LogDir
        if (-not $dir) { return }
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $file = Join-Path $dir ('IRT-{0}.log' -f $script:RemId)
        if ((Test-Path -LiteralPath $file) -and ((Get-Item -LiteralPath $file).Length -gt 1MB)) {
            Move-Item -LiteralPath $file -Destination ($file + '.old') -Force
        }
        $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $script:Phase, $Level, $Message
        Add-Content -LiteralPath $file -Value $line -Encoding UTF8
    }
    catch { }
}

function Format-RemOutput {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    if ($Text.Length -gt 2000) { return $Text.Substring(0, 1997) + '...' }
    return $Text
}

function Complete-Rem {
    param([scriptblock]$Main)
    try { $r = & $Main }
    catch { $r = [pscustomobject]@{ ExitCode = 2; Output = 'ERROR | ' + $_.Exception.Message } }
    if ($null -eq $r -or $null -eq $r.ExitCode) { $r = [pscustomobject]@{ ExitCode = 2; Output = 'ERROR | script returned no result' } }
    $out = Format-RemOutput $r.Output
    Write-RemLog ('EXIT {0} | {1}' -f $r.ExitCode, $out)
    Write-Output $out
    exit $r.ExitCode
}

$script:RemId    = 'REM-003'
$script:LogDir   = if ($env:ProgramData) { Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs' } else { $null }
$script:StateKey = 'HKLM:\SOFTWARE\IntuneRemediations\REM-003'

$script:LegacyProofKey = 'HKLM:\SOFTWARE\IntuneRemediationToolkit\BitLockerEscrow'

$ReportAttentionAsIssue = $false

$AutoResume               = $false
$MinRebootsSinceFirstSeen = 2
$MinSuspendedHours        = 72

$EpisodeGapHours          = 168

$ReEscrowAfterDays        = 90

$ResumeWhenSuspendCountUnknown = $false
$EnsureRecoveryPassword = $true
$EscrowToEntra          = $true
$AlsoEscrowToAD         = $false

function Get-RemOsVolume {
    $v = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    [pscustomobject]@{
        VolumeStatus     = [string]$v.VolumeStatus
        ProtectionStatus = [string]$v.ProtectionStatus
        Protectors       = @($v.KeyProtector | ForEach-Object { [pscustomobject]@{ Type = [string]$_.KeyProtectorType; Id = [string]$_.KeyProtectorId } })
    }
}
function Get-RemSuspendCount {
    try {
        $ev = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter ("DriveLetter='{0}'" -f $env:SystemDrive) -ErrorAction Stop
        $r = Invoke-CimMethod -InputObject $ev -MethodName GetSuspendCount -ErrorAction Stop
        if ($r.ReturnValue -eq 0) { return [int]$r.SuspendCount }
    } catch { }
    return $null
}
function Test-RemPendingReboot {
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { return $true }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { return $true }
    $p = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($p -and $p.PendingFileRenameOperations) { return $true }

    $sb = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot' -Name AvailableUpdates -ErrorAction SilentlyContinue
    if ($sb -and [int]$sb.AvailableUpdates -ne 0) { return $true }
    return $false
}
function Get-RemLastBoot { (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime }
function Get-RemState {
    param([string]$Name)
    $p = Get-ItemProperty -LiteralPath $script:StateKey -Name $Name -ErrorAction SilentlyContinue
    if ($p) { return $p.$Name }
    return $null
}
function Get-RemFvePolicy {
    param([string]$Name)
    $p = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\FVE' -Name $Name -ErrorAction SilentlyContinue
    if ($p) { return $p.$Name }
    return $null
}
function Test-RemEscrowProof {
    param([string]$Id)

    foreach ($k in ("$script:StateKey\Escrow", $script:LegacyProofKey)) {
        $p = Get-ItemProperty -LiteralPath $k -Name $Id -ErrorAction SilentlyContinue
        if ($p) {
            $t = ConvertTo-RemDate ([string]$p.$Id)
            if ($t -and ((Get-Date) - $t).TotalDays -lt $ReEscrowAfterDays) { return $true }
        }
    }
    return $false
}
function Get-RemBootsSince {
    param([datetime]$Since)
    try { return @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 12; StartTime = $Since } -ErrorAction Stop).Count }
    catch { return 0 }
}
function ConvertTo-RemDate {
    param([string]$Text)
    $t = [datetime]::MinValue
    if ($Text -and [datetime]::TryParse($Text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$t)) { return $t }
    return $null
}

function Get-BitLockerFindings {
    $findings = New-Object System.Collections.Generic.List[object]
    $add = { param($Kind, $Code, $Data) $findings.Add([pscustomobject]@{ Kind = $Kind; Code = $Code; Data = $Data }) }

    $vol = Get-RemOsVolume
    if ($vol.VolumeStatus -eq 'FullyDecrypted') {
        & $add 'NotApplicable' ("OsVolume={0}" -f $vol.VolumeStatus) $null
        return $findings
    }
    if ($vol.Protectors.Count -eq 0) {

        & $add 'Attention' ('EncryptedWithoutProtectors({0})' -f $vol.VolumeStatus) $null
        return $findings
    }

    $hasTpm = [bool]($vol.Protectors | Where-Object { $_.Type -like 'Tpm*' })
    $rp     = @($vol.Protectors | Where-Object Type -eq 'RecoveryPassword')

    if ($vol.ProtectionStatus -eq 'Off' -and $vol.VolumeStatus -eq 'FullyEncrypted') {
        $sc = Get-RemSuspendCount
        if (-not $hasTpm) { & $add 'Attention' 'Suspended(NoTpmProtector)' $null }
        elseif ($null -eq $sc -and -not $ResumeWhenSuspendCountUnknown) { & $add 'Attention' 'Suspended(SuspendCountUnknown)' $null }
        elseif ($sc -gt 0) { & $add 'Info' ("SuspendedPlanned(ResumesAfter{0}Reboot)" -f $sc) $null }
        elseif (-not $AutoResume) { & $add 'Attention' 'Protection=SuspendedIndefinitely(AutoResumeOff)' $null }
        else { & $add 'Fixable' 'Protection=SuspendedIndefinitely' $null }
    }
    elseif ($vol.VolumeStatus -ne 'FullyEncrypted') { & $add 'Info' ("VolumeStatus={0}" -f $vol.VolumeStatus) $null }

    if ($EnsureRecoveryPassword -and $rp.Count -eq 0) {

        if ((Get-RemFvePolicy 'OSRecoveryPassword') -eq 0) { & $add 'Attention' 'RecoveryPassword=Missing(NotAllowedByPolicy)' $null }
        else { & $add 'Fixable' 'RecoveryPassword=Missing' $null }
    }
    $unproven = @($rp | Where-Object { -not (Test-RemEscrowProof -Id $_.Id) })
    if (($EscrowToEntra -or $AlsoEscrowToAD) -and $unproven.Count) { & $add 'Fixable' ("Escrow=Unproven({0})" -f $unproven.Count) $unproven }

    return $findings
}

function Format-Findings {
    param($Findings)
    if ($Findings | Where-Object Kind -eq 'NotApplicable') { return 'NOT-APPLICABLE | ' + (($Findings | ForEach-Object Code) -join ', ') }
    $fix = @($Findings | Where-Object Kind -eq 'Fixable'   | ForEach-Object Code)
    $att = @($Findings | Where-Object Kind -eq 'Attention' | ForEach-Object Code)
    $inf = @($Findings | Where-Object Kind -eq 'Info'      | ForEach-Object Code)
    $parts = @($(if ($fix.Count) { 'FIXABLE' } elseif ($att.Count) { 'ATTENTION' } else { 'OK' }))
    if ($fix.Count) { $parts += 'Fixable: ' + ($fix -join ', ') }
    if ($att.Count) { $parts += 'Attention: ' + ($att -join ', ') }
    if ($inf.Count) { $parts += 'Info: ' + ($inf -join ', ') }
    $parts -join ' | '
}

function Invoke-RemDetection {
    $f = Get-BitLockerFindings
    $fix = @($f | Where-Object Kind -eq 'Fixable').Count
    $att = @($f | Where-Object Kind -eq 'Attention').Count
    $code = if ($fix -gt 0 -or ($ReportAttentionAsIssue -and $att -gt 0)) { 1 } else { 0 }
    [pscustomobject]@{ ExitCode = $code; Output = (Format-Findings $f) }
}

if ($MyInvocation.InvocationName -ne '.') { Complete-Rem { Invoke-RemDetection } }
