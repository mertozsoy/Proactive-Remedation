<#
.SYNOPSIS
  Remediation script for disabling device co-installers.

.DESCRIPTION
  Reports by default. With explicit approval and no external policy owner, backs up an existing key, writes DWORD 1 and verifies the result. Exits 1 for unresolved drift or failure and 0 for compliance or not applicable.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $false
$ManagedExternally = $false
$ExpectedDisableCoInstallers = 1

$PackageName = 'DeviceCoInstallers'
$Phase = 'Remediate'
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
function Get-CoInstallerState {
    $key = $null
    try {
        if (-not (Test-Path -LiteralPath $RegistryPath -ErrorAction Stop)) { return 'Missing' }
        $key = Get-Item -LiteralPath $RegistryPath -ErrorAction Stop
        if ($key.GetValueNames() -notcontains 'DisableCoInstallers') { return 'Missing' }
        if ($key.GetValueKind('DisableCoInstallers') -ne [Microsoft.Win32.RegistryValueKind]::DWord) { return 'WrongType' }
        if ($key.GetValue('DisableCoInstallers') -eq $ExpectedDisableCoInstallers) { return 'Compliant' }
        return 'DifferentValue'
    }
    finally { if ($null -ne $key) { $key.Close() } }
}

try {
    $ErrorActionPreference = 'Stop'
    $RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer'
    $NativeRegistryPath = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer'
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [version]$os.Version -lt [version]'10.0') {
        Exit-Script 0 'NotApplicable | Reason=WindowsClient10OrLaterRequired'
    }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Exit-Script 1 'Failed | Reason=Use64BitPowerShell'
    }
    if ($ExpectedDisableCoInstallers -ne 1) { Exit-Script 1 'Failed | Reason=ExpectedValueMustBe1' }
    $state = Get-CoInstallerState
    if ($state -eq 'Compliant') { Exit-Script 0 'Healthy | DisableCoInstallers=1; Type=DWord' }
    if ($ManagedExternally) { Exit-Script 1 'Blocked | Reason=ExternalPolicyOwner; Action=CorrectAtSource' }
    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | Setting=DisableCoInstallers; State=$state; EnableRemediation=False"
    }
    $backupStatus = 'KeyAbsent'
    if (Test-Path -LiteralPath $RegistryPath -ErrorAction Stop) {
        $backupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
        $null = New-Item -Path $backupRoot -ItemType Directory -Force -ErrorAction Stop
        $backupFile = Join-Path $backupRoot ('DeviceCoInstallers_{0}_{1}.reg' -f (Get-Date -Format 'yyyyMMddHHmmssfff'), [guid]::NewGuid().ToString('N'))
        $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
        $null = & $regExe export $NativeRegistryPath $backupFile /y 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupFile -ErrorAction Stop)) {
            Exit-Script 1 'Failed | Reason=RegistryBackupFailed; Changed=False'
        }
        $backupStatus = 'Exported'
    }
    else { $null = New-Item -Path $RegistryPath -Force -ErrorAction Stop }
    $null = New-ItemProperty -LiteralPath $RegistryPath -Name 'DisableCoInstallers' -PropertyType DWord -Value $ExpectedDisableCoInstallers -Force -ErrorAction Stop
    if ((Get-CoInstallerState) -ne 'Compliant') { Exit-Script 1 'Failed | Reason=VerificationFailed' }
    Exit-Script 0 "Fixed | DisableCoInstallers=1; Type=DWord; Backup=$backupStatus; Verification=RegistryOnly"
}
catch { Exit-Script 1 "Error: | Operation=Remediate; HResult=$($_.Exception.HResult)" }
