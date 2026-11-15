<#
.SYNOPSIS
  Detection script for the LAN Manager authentication level.

.DESCRIPTION
  Reads LmCompatibilityLevel from the LSA registry key on Windows clients. Exits 1 when the value is missing, has the wrong type or allows LM or NTLM. Exits 0 when the value is NTLMv2 only or the device is not applicable.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TargetLevel = 5
$ValueName = 'LmCompatibilityLevel'
$LsaSubKey = 'SYSTEM\CurrentControlSet\Control\Lsa'

$PackageName = 'NtlmV2Level'
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

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=ServerOperatingSystem' }
    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    try { $state = Get-LmState -Root $root }
    finally { $root.Dispose() }
    if (-not $state.KeyFound) { Exit-Script 0 'NotApplicable | Reason=LsaKeyNotFound' }
    if (-not $state.Exists) { Exit-Script 1 "Drift | $ValueName=Missing; Expected=$TargetLevel; State=NotConfigured" }
    if ($state.Kind -ne 'DWord') { Exit-Script 1 "Drift | $ValueName=WrongType; Expected=$TargetLevel; State=NotDWord" }
    $current = [int64]$state.Value
    if ($current -ne $TargetLevel) { Exit-Script 1 "Drift | $ValueName=$current; Expected=$TargetLevel; State=Different" }
    Exit-Script 0 "Healthy | $ValueName=$current; Expected=$TargetLevel"
}
catch { Exit-Script 1 "Failed | Reason=InspectionError; ErrorType=$($_.Exception.GetType().Name)" }
