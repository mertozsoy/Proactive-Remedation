<#
.SYNOPSIS
  Remediation script for explicit LSA protection configuration.

.DESCRIPTION
  Sets missing or disabled RunAsPPL to DWORD 2 on Windows 11 22H2 or later clients and verifies the registry value. Does not create a UEFI lock or restart Windows. Leaves policy-managed or ambiguous configurations unchanged. Exits 0 after configuration succeeds, 1 if blocked or unsuccessful.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumBuild = 22621
$EnableRemediation = $false
$ExpectedRunAsPPL = 2

$PackageName = 'LsaProtection'
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
    if ($ExpectedRunAsPPL -ne 2) { Exit-Script 1 'Blocked | Reason=OnlyNonUefiLockValue2Allowed' }
    $policyState = Get-LsaPolicyState
    $current = Get-LsaConfiguration
    if ($policyState -ne 'NoneDetected') { Exit-Script 1 "PolicyManaged | Source=$policyState; RunAsPPL=$current; Action=ReviewPolicy" }
    if ($current -in @('1', '2')) { Exit-Script 0 "Healthy | RunAsPPL=$current; Scope=Configuration; Runtime=NotChecked" }
    if ($current -notin @('Missing', '0')) { Exit-Script 1 "Blocked | RunAsPPL=$current; Reason=UnexpectedConfiguration" }
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | RunAsPPL=$current; Remediation=Disabled" }
    $policyState = Get-LsaPolicyState
    if ($policyState -ne 'NoneDetected') { Exit-Script 1 "PolicyManaged | Source=$policyState; Action=ReviewPolicy" }
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Lsa', $true)
    if ($null -eq $key) { throw 'LSA registry key unavailable for writing.' }
    try {
        $latest = 'Missing'
        if ($key.GetValueNames() -contains 'RunAsPPL') {
            if ($key.GetValueKind('RunAsPPL') -ne [Microsoft.Win32.RegistryValueKind]::DWord) { throw 'Configuration changed before write.' }
            $latest = [string]$key.GetValue('RunAsPPL')
        }
        if ($latest -notin @('Missing', '0', '1', '2')) { throw 'Unexpected configuration before write.' }
        if ($latest -in @('Missing', '0')) {
            $key.SetValue('RunAsPPL', $ExpectedRunAsPPL, [Microsoft.Win32.RegistryValueKind]::DWord)
            $key.Flush()
        }
    }
    finally { $key.Dispose() }
    $verified = Get-LsaConfiguration
    if ($verified -notin @('1', '2')) { Exit-Script 1 "Failed | RunAsPPL=$verified; Reason=VerificationFailed" }
    Exit-Script 0 "Fixed | RunAsPPL=$verified; Restart=Required; Runtime=NotChecked"
}
catch { Exit-Script 1 "Error: Failed | Reason=ConfigurationOrPolicyCheckFailed; Type=$($_.Exception.GetType().Name)" }
