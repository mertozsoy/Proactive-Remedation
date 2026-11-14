<#
.SYNOPSIS
  Detection script for power policy values left behind after a power profile is removed.

.DESCRIPTION
  Reads the power policy keys under Software\Policies\Microsoft\Power\PowerSettings and lists the settings that still lock the power options. Exits 1 if tattooed values are found and no MDM power policy is active, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PolicyRoot  = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings'
$MdmStateKey = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Power'
$FriendlyNames = @{
    '5ca83367-6e45-459f-a27b-476b1d01c936' = 'LidClose'
    '7648efa3-dd9c-4e3e-b566-50f929386280' = 'PowerButton'
    '96996bc0-ad50-47ec-923b-6f41874dd9eb' = 'SleepButton'
    '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e' = 'DisplayOff'
    '29f6c1db-86da-48c5-9fdb-f2b67b1f44da' = 'Sleep'
    '9d7815a6-7ee4-497e-8888-515a05f02364' = 'Hibernate'
    'e69653ca-cf7f-4f05-aa73-cb833fa90ad4' = 'EnergySaverThreshold'
}

$PackageName = 'TattooedPowerSettings'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-TattooedPowerSetting {
    if (-not (Test-Path -LiteralPath $PolicyRoot)) { return @() }
    $items = @()
    foreach ($key in Get-ChildItem -LiteralPath $PolicyRoot -ErrorAction Stop) {
        $names = @($key.GetValueNames())
        $sides = @()
        if ($names -contains 'ACSettingIndex') { $sides += 'AC' }
        if ($names -contains 'DCSettingIndex') { $sides += 'DC' }
        if ($sides.Count -eq 0) { continue }
        $id = $key.PSChildName.ToLowerInvariant()
        $label = $FriendlyNames[$id]
        if (-not $label) { $label = $id }
        $items += [pscustomobject]@{
            Id    = $key.PSChildName
            Label = $label
            Key   = $key.PSPath
            Sides = ($sides -join '/')
        }
    }
    $items
}

function Test-MdmPowerPolicy {
    if (-not (Test-Path -LiteralPath $MdmStateKey)) { return $false }
    $key = Get-Item -LiteralPath $MdmStateKey -ErrorAction Stop
    try { return (@($key.GetValueNames()).Count -gt 0) } finally { $key.Close() }
}

try {
    $items = @(Get-TattooedPowerSetting)
    if ($items.Count -eq 0) { Exit-Script 0 'Healthy | TattooedPowerSettings=0' }

    $list = ($items | ForEach-Object { '{0}({1})' -f $_.Label, $_.Sides }) -join ','
    if (Test-MdmPowerPolicy) { Exit-Script 0 "Managed | Count=$($items.Count); Settings=$list; Reason=MdmPowerPolicyActive" }

    Exit-Script 1 "Drift | Count=$($items.Count); Settings=$list"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
