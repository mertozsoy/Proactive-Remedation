<#
.SYNOPSIS
  Detection script for explicit LSA protection configuration.

.DESCRIPTION
  Checks RunAsPPL on Windows 11 22H2 or later clients. Exits 1 for missing or disabled configuration, policy blocks or unreadable state. Exits 0 for DWORD 1 or 2, or unsupported devices. Checks configuration, not running LSASS protection.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumBuild = 22621

$PackageName = 'LsaProtection'
$Phase = 'Detect'
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
function Get-LsaPolicyState {
    $admxPath = Join-Path $env:windir 'PolicyDefinitions\LocalSecurityAuthority.admx'
    [xml]$admx = Get-Content -LiteralPath $admxPath -Raw -ErrorAction Stop
    $policy = $admx.SelectSingleNode("//*[local-name()='policy' and @name='ConfigureLsaProtectedProcess']")
    if ($null -eq $policy -or $policy.GetAttribute('key') -ne 'Software\Policies\Microsoft\Windows\System') {
        throw 'Policy mapping unavailable.'
    }
    $names = @($policy.SelectNodes('descendant-or-self::*[@valueName]') | ForEach-Object { $_.GetAttribute('valueName') } | Sort-Object -Unique)
    if ($names.Count -eq 0) { throw 'Policy value mapping unavailable.' }
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($policy.GetAttribute('key'))
    if ($null -ne $key) {
        try {
            foreach ($name in $names) {
                if ($key.GetValueNames() -contains $name) { return 'GroupPolicy' }
            }
        }
        finally { $key.Dispose() }
    }
    $namespace = 'root\cimv2\mdm\dmmap'
    $classes = @(Get-CimClass -Namespace $namespace -ClassName 'MDM_Policy_Config*' -ErrorAction Stop | Where-Object {
        $_.CimClassProperties.Name -contains 'ConfigureLsaProtectedProcess'
    })
    if ($classes.Count -eq 0) { throw 'MDM policy schema unavailable.' }
    foreach ($class in $classes) {
        $instances = @(Get-CimInstance -Namespace $namespace -ClassName $class.CimClassName -ErrorAction Stop)
        foreach ($instance in $instances) {
            if ($null -ne $instance.ConfigureLsaProtectedProcess) { return 'MDMOrDefault' }
        }
    }
    return 'NoneDetected'
}
function Get-LsaConfiguration {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Lsa')
    if ($null -eq $key) { throw 'LSA registry key unavailable.' }
    try {
        if ($key.GetValueNames() -notcontains 'RunAsPPL') { return 'Missing' }
        if ($key.GetValueKind('RunAsPPL') -ne [Microsoft.Win32.RegistryValueKind]::DWord) { return 'UnexpectedType' }
        return [string]$key.GetValue('RunAsPPL')
    }
    finally { $key.Dispose() }
}
try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') { Exit-Script 1 'Failed | Reason=RequiresSystem' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt $MinimumBuild) {
        Exit-Script 0 'NotApplicable | Requires=Windows11-22H2OrLaterClient'
    }
    $policyState = Get-LsaPolicyState
    $current = Get-LsaConfiguration
    if ($policyState -ne 'NoneDetected') { Exit-Script 1 "PolicyManaged | Source=$policyState; RunAsPPL=$current; Action=ReviewPolicy" }
    if ($current -in @('1', '2')) { Exit-Script 0 "Healthy | RunAsPPL=$current; Scope=Configuration; Runtime=NotChecked" }
    if ($current -notin @('Missing', '0')) { Exit-Script 1 "Blocked | RunAsPPL=$current; Reason=UnexpectedConfiguration" }
    Exit-Script 1 "Drift | RunAsPPL=$current; Expected=1Or2; Runtime=NotChecked"
}
catch { Exit-Script 1 "Error: Failed | Reason=ReadOrPolicyCheckFailed; Type=$($_.Exception.GetType().Name)" }
