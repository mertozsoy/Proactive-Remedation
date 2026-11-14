<#
.SYNOPSIS
  Remediation script for the new Outlook toggle and automatic migration settings.

.DESCRIPTION
  Hides the toggle and disables both migration flows for the current user.
  Preserves conflicting Office policies. Exits 0 after verification, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedHideNewOutlookToggle = 1
$ExpectedDoNewOutlookAutoMigration = 0
$ExpectedNewOutlookMigrationUserSetting = 0

$PackageName = 'NewOutlookMigration'
$Phase = 'Remediate'
$LogFile = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $logDirectory = Split-Path -Path $LogFile -Parent
        if (-not (Test-Path -LiteralPath $logDirectory -ErrorAction Stop)) {
            New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop | Out-Null
        }
        $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch { return }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-RegistrySetting {
    param([string]$Path, [string]$Name, [int]$Expected)
    if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return 'Missing' }
    $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    try {
        if ($key.GetValueNames() -notcontains $Name) { return 'Missing' }
        if ($key.GetValueKind($Name) -ne [Microsoft.Win32.RegistryValueKind]::DWord) { return 'WrongType' }
        if ($key.GetValue($Name) -ne $Expected) { return 'WrongValue' }
        return 'Expected'
    }
    finally { $key.Close() }
}

function Get-OutlookSettingState {
    foreach ($setting in $Settings) {
        $managed = $false
        $conflict = $false
        foreach ($root in $PolicyRoots) {
            if (-not (Test-Path -LiteralPath $root -ErrorAction Stop)) { continue }
            $paths = @($root) + @(Get-ChildItem -LiteralPath $root -Recurse -ErrorAction Stop | Select-Object -ExpandProperty PSPath)
            foreach ($path in $paths) {
                $policyState = Get-RegistrySetting -Path $path -Name $setting.Name -Expected $setting.Expected
                if ($policyState -eq 'Missing') { continue }
                $managed = $true
                if ($policyState -ne 'Expected') { $conflict = $true }
            }
        }
        if ($conflict) { $state = 'PolicyConflict' }
        elseif ($managed) { $state = 'Managed' }
        else { $state = Get-RegistrySetting -Path $setting.Path -Name $setting.Name -Expected $setting.Expected }
        [pscustomobject]@{ Name = $setting.Name; Path = $setting.Path; Expected = $setting.Expected; State = $state }
    }
}

try {
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 1 'Error: WrongContext | Required=User'
    }
    $outlookRoot = 'HKCU:\Software\Microsoft\Office\16.0\Outlook'
    if (-not (Test-Path -LiteralPath $outlookRoot -ErrorAction Stop)) {
        Exit-Script 0 'NotApplicable | ClassicOutlookUserSettings=Absent'
    }
    $PolicyRoots = @(
        'HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook'
        'HKCU:\Software\Policies\Microsoft\Cloud\Office\16.0\Outlook'
    )
    $Settings = @(
        @{ Name = 'HideNewOutlookToggle'; Path = "$outlookRoot\Options\General"; Expected = $ExpectedHideNewOutlookToggle }
        @{ Name = 'DoNewOutlookAutoMigration'; Path = "$outlookRoot\Options\General"; Expected = $ExpectedDoNewOutlookAutoMigration }
        @{ Name = 'NewOutlookMigrationUserSetting'; Path = 'HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Preferences'; Expected = $ExpectedNewOutlookMigrationUserSetting }
    )
    $states = @(Get-OutlookSettingState)
    if (@($states | Where-Object { $_.State -eq 'PolicyConflict' }).Count -gt 0) {
        $summary = ($states | ForEach-Object { '{0}={1}' -f $_.Name, $_.State }) -join '; '
        Exit-Script 1 "Blocked | $summary; Action=ReviewCentralPolicy"
    }
    $changed = 0
    foreach ($setting in $states) {
        if ($setting.State -in @('Expected', 'Managed')) { continue }
        $current = @(Get-OutlookSettingState)
        if (@($current | Where-Object { $_.State -eq 'PolicyConflict' }).Count -gt 0) {
            Exit-Script 1 "Blocked | Action=ReviewCentralPolicy; Changed=$changed"
        }
        $latest = $current | Where-Object { $_.Name -eq $setting.Name }
        if ($latest.State -in @('Expected', 'Managed')) { continue }
        if (-not (Test-Path -LiteralPath $setting.Path -ErrorAction Stop)) {
            New-Item -Path $setting.Path -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value $setting.Expected -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        $changed++
        Write-IRTLog ("Set {0}={1}" -f $setting.Name, $setting.Expected)
    }
    $after = @(Get-OutlookSettingState)
    $summary = ($after | ForEach-Object { '{0}={1}' -f $_.Name, $_.State }) -join '; '
    if (@($after | Where-Object { $_.State -notin @('Expected', 'Managed') }).Count -gt 0) {
        Exit-Script 1 "Failed | $summary; Changed=$changed"
    }
    if ($changed -eq 0) { Exit-Script 0 "Healthy | $summary; Changed=0" }
    Exit-Script 0 "Fixed | $summary; Changed=$changed; Apply=NextOutlookLaunch"
}
catch { Exit-Script 1 ("Error: RegistryWriteOrVerificationFailed | HResult={0}" -f $_.Exception.HResult) }
