<#
.SYNOPSIS
  Detection script for a standard Dell BIOS baseline.

.DESCRIPTION
  Reads Dell BIOS attributes through the native WMI interface and compares the managed settings with the configured values. Exits 1 when a supported attribute is out of standard, 0 when the device matches or the interface is unavailable.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$BiosNamespace = 'root\dcim\sysman\biosattributes'
$ManageSecureBoot = $false
$DesiredSettings = @(
    [pscustomobject]@{ Name = 'WakeOnDock'; Value = 'Enabled' }
    [pscustomobject]@{ Name = 'AutoOn'; Value = 'Disabled' }
    [pscustomobject]@{ Name = 'AcPwrRcvry'; Value = 'Last' }
    [pscustomobject]@{ Name = 'TpmSecurity'; Value = 'Enabled' }
)
if ($ManageSecureBoot) { $DesiredSettings += [pscustomobject]@{ Name = 'SecureBoot'; Value = 'Enabled' } }

$PackageName = 'DellBiosSettings'
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
function Test-UefiBoot {
    try {
        $null = Confirm-SecureBootUEFI -ErrorAction Stop
        return $true
    }
    catch { return $false }
}
function Get-BiosAttribute {
    $attributes = @{}
    $available = $false
    foreach ($className in @('EnumerationAttribute', 'IntegerAttribute', 'StringAttribute')) {
        $items = $null
        try { $items = Get-CimInstance -Namespace $BiosNamespace -ClassName $className -ErrorAction Stop }
        catch { continue }
        $available = $true
        foreach ($item in @($items)) {
            $name = [string]$item.AttributeName
            if ([string]::IsNullOrWhiteSpace($name) -or $attributes.ContainsKey($name)) { continue }
            $attributes[$name] = [pscustomobject]@{
                Name = $name
                Value = [string]$item.CurrentValue
                Allowed = @($item.PossibleValue | ForEach-Object { [string]$_ })
            }
        }
    }
    if (-not $available -or $attributes.Count -eq 0) { return $null }
    return $attributes
}
function Get-SettingState {
    param($Setting, $Attributes, [bool]$Uefi)
    if (-not $Attributes.ContainsKey($Setting.Name)) { return 'Missing' }
    $entry = $Attributes[$Setting.Name]
    if ($Setting.Name -eq 'SecureBoot' -and -not $Uefi) { return 'UefiRequired' }
    if ($entry.Allowed.Count -gt 0 -and $entry.Allowed -notcontains $Setting.Value) { return 'InvalidValue' }
    if ($entry.Value -ieq $Setting.Value) { return 'Compliant' }
    return 'Drift'
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($computer.Manufacturer -notmatch '^Dell') { Exit-Script 0 'NotApplicable | Reason=NotDell' }
    $attributes = Get-BiosAttribute
    if ($null -eq $attributes) { Exit-Script 0 'NotApplicable | Reason=DellBiosWmiUnavailable' }
    $uefi = Test-UefiBoot
    $drift = @()
    $skipped = @()
    foreach ($setting in $DesiredSettings) {
        $state = Get-SettingState -Setting $setting -Attributes $attributes -Uefi $uefi
        Write-IRTLog ("Setting | Name={0}; Current={1}; Target={2}; State={3}" -f $setting.Name, $attributes[$setting.Name].Value, $setting.Value, $state)
        if ($state -eq 'Drift') { $drift += $setting.Name }
        elseif ($state -ne 'Compliant') { $skipped += ('{0}:{1}' -f $setting.Name, $state) }
    }
    if ($drift.Count -gt 0) {
        Exit-Script 1 ("Drift | Settings={0}; Drift={1}; Fields={2}; Skipped={3}" -f $DesiredSettings.Count, $drift.Count, ($drift -join ','), $skipped.Count)
    }
    Exit-Script 0 ("Healthy | Settings={0}; Drift=0; Skipped={1}" -f $DesiredSettings.Count, $skipped.Count)
}
catch { Exit-Script 1 "Failed | Reason=InspectionError; ErrorType=$($_.Exception.GetType().Name)" }
