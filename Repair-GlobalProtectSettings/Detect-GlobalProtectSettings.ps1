<#
.SYNOPSIS
  Detection script for GlobalProtect portal and optional pre-logon bootstrap settings.

.DESCRIPTION
  Checks PanSetup string values against an approved local baseline. Exits 1 for drift or configuration errors and 0 when healthy or not applicable. Does not test VPN connectivity.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExpectedPortal = ''
$LocalSettingsOwnershipConfirmed = $false
$RepairPrelogon = $false
$ExpectedPrelogon = '1'

$PackageName = 'GlobalProtectSettings'
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
function Get-SettingDrift {
    $key = Get-Item -LiteralPath $SettingsPath -ErrorAction SilentlyContinue
    foreach ($name in $ExpectedValues.Keys) {
        if ($null -eq $key -or $key.GetValueNames() -notcontains $name) { $name; continue }
        if ($key.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::String -or
            [string]$key.GetValue($name) -cne [string]$ExpectedValues[$name]) { $name }
    }
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    $service = Get-Service -Name 'PanGPS' -ErrorAction SilentlyContinue
    if ($null -eq $service) { Exit-Script 0 'NotApplicable | Reason=GlobalProtectServiceMissing' }
    if ([string]::IsNullOrWhiteSpace($ExpectedPortal) -or $ExpectedPortal -ne $ExpectedPortal.Trim() -or
        [Uri]::CheckHostName($ExpectedPortal) -eq [UriHostNameType]::Unknown -or
        $ExpectedPortal -match '(?i)(^|\.)example\.(com|net|org)$') {
        Exit-Script 1 'ConfigurationRequired | Reason=SetApprovedPortalHostOrIP'
    }
    if ($RepairPrelogon -and $ExpectedPrelogon -cne '1') {
        Exit-Script 1 'ConfigurationRequired | Reason=SupportedPrelogonValueIsString1'
    }
    $SettingsPath = 'HKLM:\SOFTWARE\Palo Alto Networks\GlobalProtect\PanSetup'
    $ExpectedValues = @{ Portal = $ExpectedPortal }
    if ($RepairPrelogon) { $ExpectedValues['Prelogon'] = $ExpectedPrelogon }
    $drift = @(Get-SettingDrift)
    $fields = ($drift | Sort-Object) -join ','
    if ($drift.Count -eq 0) { Exit-Script 0 "Healthy | Values=$($ExpectedValues.Count); PrelogonManaged=$RepairPrelogon" }
    if (-not $LocalSettingsOwnershipConfirmed) {
        Exit-Script 1 "Blocked | Reason=OwnershipNotConfirmed; Fields=$fields; Changed=0"
    }
    Exit-Script 1 "Drift | Fields=$fields; PrelogonManaged=$RepairPrelogon"
}
catch { Exit-Script 1 'Error: InspectionFailed | Changed=0; Review=PermissionsAndConfiguration' }
