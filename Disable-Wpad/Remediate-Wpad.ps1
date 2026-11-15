<#
.SYNOPSIS
  Disables WinHTTP WPAD auto-discovery without changing services.

.DESCRIPTION
  Creates DisableWpad as DWORD 1 and verifies the native registry value.
  Existing conflicting values are report-only unless replacement is approved.
  Exits 0 after verification or exclusion and 1 on blocked or failed repair.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SettingManagedExternally = $false
$ReplaceExistingValue = $false

$PackageName = 'Wpad'
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
function Get-WpadState {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    $key = $null
    try {
        $key = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp')
        if ($null -eq $key -or $key.GetValueNames() -notcontains 'DisableWpad') { return 'Missing' }
        if ($key.GetValueKind('DisableWpad') -ne [Microsoft.Win32.RegistryValueKind]::DWord) { return 'WrongType' }
        if ($key.GetValue('DisableWpad') -eq 1) { return 'Disabled' }
        return 'Enabled'
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        $base.Dispose()
    }
}
try {
    $ErrorActionPreference = 'Stop'
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ([int]$os.BuildNumber -lt 17763) { Exit-Script 0 'NotApplicable | Reason=UnsupportedOS; MinimumBuild=17763' }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Error: | Reason=Use64BitPowerShell' }
    if ($SettingManagedExternally) { Exit-Script 0 'NotApplicable | Reason=ExternallyManaged; Scope=WinHTTP' }
    $state = Get-WpadState
    if ($state -eq 'Disabled') { Exit-Script 0 'Healthy | DisableWpad=1; Scope=WinHTTP' }
    if ($state -ne 'Missing' -and -not $ReplaceExistingValue) {
        Exit-Script 1 "Blocked | State=$state; Reason=ExistingValueRequiresApproval; Scope=WinHTTP"
    }
    if ($state -ne 'Missing') {
        $backupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
        New-Item -Path $backupRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $backupFile = Join-Path $backupRoot ('Wpad_{0}.reg' -f [guid]::NewGuid().ToString('N'))
        & "$env:SystemRoot\System32\reg.exe" export 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp' $backupFile /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupFile)) { Exit-Script 1 'Failed | Reason=BackupFailed; Scope=WinHTTP' }
    }
    $registryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
    New-Item -Path $registryPath -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -LiteralPath $registryPath -Name 'DisableWpad' -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
    if ((Get-WpadState) -ne 'Disabled') { Exit-Script 1 'Failed | Reason=VerificationFailed; Scope=WinHTTP' }
    Exit-Script 0 'Fixed | DisableWpad=1; Scope=WinHTTP; ServiceChanged=False'
}
catch { Exit-Script 1 "Error: | Type=$($_.Exception.GetType().Name); Scope=WinHTTP" }
