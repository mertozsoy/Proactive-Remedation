<#
.SYNOPSIS
  Remediation script for the LAN Manager authentication level.

.DESCRIPTION
  Sets LmCompatibilityLevel to 5 (Send NTLMv2 response only. Refuse LM and NTLM) on Windows clients. Saves the previous value to a reg file under ProgramData and verifies the new value. Exits 0 when fixed or already compliant, 1 when the change cannot be verified. Never restarts the device.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TargetLevel = 5
$BackupBeforeChange = $true
$ValueName = 'LmCompatibilityLevel'
$LsaSubKey = 'SYSTEM\CurrentControlSet\Control\Lsa'

$PackageName = 'NtlmV2Level'
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
function Get-LmState {
    param([Microsoft.Win32.RegistryKey]$Root)
    $key = $Root.OpenSubKey($LsaSubKey)
    if ($null -eq $key) {
        return [pscustomobject]@{ KeyFound = $false; Exists = $false; Kind = ''; Value = $null }
    }
    try {
        if (@($key.GetValueNames()) -notcontains $ValueName) {
            return [pscustomobject]@{ KeyFound = $true; Exists = $false; Kind = ''; Value = $null }
        }
        $kind = [string]$key.GetValueKind($ValueName)
        $value = $key.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        return [pscustomobject]@{ KeyFound = $true; Exists = $true; Kind = $kind; Value = $value }
    }
    finally { $key.Dispose() }
}
function Save-LmBackup {
    param([object]$State)
    $backupDir = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
    New-Item -Path $backupDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $fileName = 'NtlmV2Level_{0}.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmss')
    $filePath = Join-Path $backupDir $fileName
    $lines = @('Windows Registry Editor Version 5.00', '', '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa]')
    if (-not $State.Exists) {
        $lines += '; LmCompatibilityLevel was not present'
    }
    elseif ($State.Kind -eq 'DWord') {
        $lines += '"LmCompatibilityLevel"=dword:{0:x8}' -f [uint32]$State.Value
    }
    else {
        $lines += '"LmCompatibilityLevel"="{0}"' -f [string]$State.Value
    }
    $lines | Out-File -LiteralPath $filePath -Encoding Unicode -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $filePath)) { throw 'Registry backup failed.' }
    Write-IRTLog "Backup written to $fileName"
    $fileName
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=ServerOperatingSystem' }
    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $state = Get-LmState -Root $root
        if (-not $state.KeyFound) { Exit-Script 0 'NotApplicable | Reason=LsaKeyNotFound' }
        if ($state.Exists -and $state.Kind -eq 'DWord' -and [int64]$state.Value -eq $TargetLevel) {
            Exit-Script 0 "Healthy | $ValueName=$TargetLevel; Expected=$TargetLevel"
        }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            if ($identity.User.Value -ne 'S-1-5-18') { Exit-Script 1 'Failed | Reason=RequiresSystem' }
        }
        finally { $identity.Dispose() }
        $backupName = ''
        if ($BackupBeforeChange) { $backupName = Save-LmBackup -State $state }
        $key = $root.OpenSubKey($LsaSubKey, $true)
        if ($null -eq $key) { throw 'LSA key could not be opened for writing.' }
        try { $key.SetValue($ValueName, $TargetLevel, [Microsoft.Win32.RegistryValueKind]::DWord) }
        finally { $key.Dispose() }
        $verify = Get-LmState -Root $root
        if (-not $verify.Exists -or $verify.Kind -ne 'DWord' -or [int64]$verify.Value -ne $TargetLevel) {
            Exit-Script 1 "Failed | $ValueName=NotVerified; Expected=$TargetLevel"
        }
    }
    finally { $root.Dispose() }
    if ($state.Exists) { $previous = [string]$state.Value } else { $previous = 'Missing' }
    $summary = 'Fixed | {0}={1}->{2}; Expected={2}; Backup={3}; AppliesAt=NextRestart' -f $ValueName, $previous, $TargetLevel, $backupName
    Exit-Script 0 $summary
}
catch { Exit-Script 1 "Failed | Reason=RemediationError; ErrorType=$($_.Exception.GetType().Name)" }
