<#
.SYNOPSIS
  Detects whether WinHTTP WPAD auto-discovery is disabled.

.DESCRIPTION
  Checks the native machine DisableWpad DWORD. Exits 1 for missing or incorrect
  configuration and 0 for compliant or explicitly excluded devices.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SettingManagedExternally = $false

$PackageName = 'Wpad'
$Phase = 'Detect'
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
    Exit-Script 1 "Drift | State=$state; Expected=DWORD1; Scope=WinHTTP"
}
catch { Exit-Script 1 "Error: | Type=$($_.Exception.GetType().Name); Scope=WinHTTP" }
