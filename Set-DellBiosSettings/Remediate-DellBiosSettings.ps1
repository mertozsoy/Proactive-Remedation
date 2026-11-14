<#
.SYNOPSIS
  Remediation script for a standard Dell BIOS baseline.

.DESCRIPTION
  Backs up the managed Dell BIOS attributes, writes the configured values through the native WMI interface and verifies the result. Exits 0 when every managed setting matches or the write was accepted for the next restart, 1 when a write fails.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$BiosNamespace = 'root\dcim\sysman\biosattributes'
$BiosAdminPassword = ''
$ManageSecureBoot = $false
$DesiredSettings = @(
    [pscustomobject]@{ Name = 'WakeOnDock'; Value = 'Enabled' }
    [pscustomobject]@{ Name = 'AutoOn'; Value = 'Disabled' }
    [pscustomobject]@{ Name = 'AcPwrRcvry'; Value = 'Last' }
    [pscustomobject]@{ Name = 'TpmSecurity'; Value = 'Enabled' }
)
if ($ManageSecureBoot) { $DesiredSettings += [pscustomobject]@{ Name = 'SecureBoot'; Value = 'Enabled' } }

$PackageName = 'DellBiosSettings'
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
function Test-UefiBoot {
    try {
        $null = Confirm-SecureBootUEFI -ErrorAction Stop
        return $true
    }
    catch { return $false }
}
function Test-BiosAdminPassword {
    try {
        $entry = Get-CimInstance -Namespace 'root\dcim\sysman\wmisecurity' -ClassName PasswordObject -ErrorAction Stop | Where-Object { $_.NameId -eq 'Admin' } | Select-Object -First 1
        if ($null -eq $entry) { return $false }
        return ([int]$entry.IsPasswordSet -eq 1)
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
function Save-BiosBackup {
    param($Attributes, $Settings)
    $backupDir = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
    if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force -ErrorAction Stop | Out-Null }
    $path = Join-Path $backupDir ("DellBios_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $rows = foreach ($setting in $Settings) {
        $before = ''
        if ($Attributes.ContainsKey($setting.Name)) { $before = $Attributes[$setting.Name].Value }
        [pscustomobject]@{ Name = $setting.Name; Before = $before; Target = $setting.Value }
    }
    $rows | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop
    Write-IRTLog "Backup | File=$path"
}
function Set-BiosSetting {
    param($Interface, $Setting, [string]$BiosSecret)
    $arguments = @{
        SecType = [uint32]0
        SecHndCount = [uint32]0
        SecHandle = [byte[]]@()
        AttributeName = $Setting.Name
        AttributeValue = $Setting.Value
    }
    if (-not [string]::IsNullOrEmpty($BiosSecret)) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($BiosSecret)
        $arguments.SecType = [uint32]1
        $arguments.SecHndCount = [uint32]$bytes.Length
        $arguments.SecHandle = [byte[]]$bytes
    }
    $result = Invoke-CimMethod -InputObject $Interface -MethodName SetAttribute -Arguments $arguments -ErrorAction Stop
    return [int]$result.Status
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
        if ($state -eq 'Drift') { $drift += $setting }
        elseif ($state -ne 'Compliant') { $skipped += ('{0}:{1}' -f $setting.Name, $state) }
    }
    $verified = $DesiredSettings.Count - $skipped.Count
    if ($drift.Count -eq 0) {
        Exit-Script 0 ("Healthy | Updated=0; Verified={0}; Skipped={1}" -f $verified, $skipped.Count)
    }
    if ((Test-BiosAdminPassword) -and [string]::IsNullOrEmpty($BiosAdminPassword)) {
        Exit-Script 1 ("Failed | Reason=BiosAdminPasswordRequired; Drift={0}" -f $drift.Count)
    }
    $interface = Get-CimInstance -Namespace $BiosNamespace -ClassName BIOSAttributeInterface -ErrorAction Stop
    Save-BiosBackup -Attributes $attributes -Settings $DesiredSettings
    $updated = 0
    $failed = @()
    foreach ($setting in $drift) {
        $status = Set-BiosSetting -Interface $interface -Setting $setting -BiosSecret $BiosAdminPassword
        Write-IRTLog ("Write | Name={0}; Target={1}; Status={2}" -f $setting.Name, $setting.Value, $status)
        if ($status -eq 0) { $updated++ }
        else { $failed += ('{0}:{1}' -f $setting.Name, $status) }
    }
    $after = Get-BiosAttribute
    $remaining = @()
    if ($null -ne $after) {
        foreach ($setting in $DesiredSettings) {
            if ((Get-SettingState -Setting $setting -Attributes $after -Uefi $uefi) -eq 'Drift') { $remaining += $setting.Name }
        }
    }
    if ($failed.Count -gt 0) {
        Exit-Script 1 ("Failed | Updated={0}; Failed={1}; Remaining={2}" -f $updated, ($failed -join ','), $remaining.Count)
    }
    if ($remaining.Count -gt 0) {
        Exit-Script 0 ("PendingRestart | Updated={0}; Verified={1}; Remaining={2}; Restart=Required" -f $updated, $verified, $remaining.Count)
    }
    Exit-Script 0 ("Fixed | Updated={0}; Verified={1}; Skipped={2}" -f $updated, $verified, $skipped.Count)
}
catch { Exit-Script 1 "Failed | Reason=RemediationError; ErrorType=$($_.Exception.GetType().Name)" }
