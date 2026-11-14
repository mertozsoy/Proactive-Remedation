<#
.SYNOPSIS
  Remediation script for a retired Windows Update driver exclusion.

.DESCRIPTION
  Requires operator confirmation of driver management and policy source retirement. Exports the parent key, removes only DWORD 1 and verifies absence. Exits 0 after success or when no exclusion exists, 1 if blocked or unsuccessful.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$DriverRingsConfirmed = $false
$PolicySourcesRetired = $false

$PackageName = 'WUDriverExclusion'
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

try {
    $ErrorActionPreference = 'Stop'
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 14393) {
        Exit-Script 0 'NotApplicable | Reason=UnsupportedOS'
    }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $valueName = 'ExcludeWUDriversInQualityUpdate'
    if (-not (Test-Path -LiteralPath $policyPath)) { Exit-Script 0 'Healthy | Exclusion=Absent' }
    $key = Get-Item -LiteralPath $policyPath
    if ($key.GetValueNames() -notcontains $valueName) { Exit-Script 0 'Healthy | Exclusion=Absent' }
    if ($key.GetValueKind($valueName) -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
        Exit-Script 1 'Failed | Reason=UnexpectedValueType; Action=ReviewPolicy'
    }
    $value = $key.GetValue($valueName)
    if ($value -eq 0) { Exit-Script 0 'Healthy | Exclusion=0' }
    if ($value -ne 1) { Exit-Script 1 'Failed | Reason=UnexpectedValueData; Action=ReviewPolicy' }
    if (-not $DriverRingsConfirmed -or -not $PolicySourcesRetired) {
        Exit-Script 1 'Blocked | Exclusion=1; Reason=PolicyReviewRequired'
    }
    $backupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup\WUDriverExclusion'
    $null = New-Item -Path $backupRoot -ItemType Directory -Force
    $backupFile = Join-Path $backupRoot ('WindowsUpdate_{0}.reg' -f [guid]::NewGuid().ToString('N'))
    $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
    $null = & $regExe export 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' $backupFile /y 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupFile)) {
        Exit-Script 1 'Failed | Reason=BackupFailed; Removed=0'
    }
    if ((Get-Item -LiteralPath $backupFile).Length -eq 0) {
        Exit-Script 1 'Failed | Reason=EmptyBackup; Removed=0'
    }
    $key = Get-Item -LiteralPath $policyPath
    if ($key.GetValueNames() -notcontains $valueName) { Exit-Script 0 'Healthy | Exclusion=Absent' }
    if ($key.GetValueKind($valueName) -ne [Microsoft.Win32.RegistryValueKind]::DWord -or $key.GetValue($valueName) -ne 1) {
        Exit-Script 1 'Failed | Reason=ValueChangedDuringBackup; Removed=0'
    }
    Remove-ItemProperty -LiteralPath $policyPath -Name $valueName -ErrorAction Stop
    if ((Get-Item -LiteralPath $policyPath).GetValueNames() -contains $valueName) {
        Exit-Script 1 'Failed | Reason=ValueStillPresent; Action=ReviewPolicy'
    }
    Exit-Script 0 'Fixed | Exclusion=Absent; Removed=1; Backup=Created'
}
catch { Exit-Script 1 ('Error: OperationFailed | HResult={0}' -f $_.Exception.HResult) }
