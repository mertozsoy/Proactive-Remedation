<#
.SYNOPSIS
  Remediation script that removes tattooed power policy values from a device.

.DESCRIPTION
  Exports and deletes the power policy settings under Software\Policies\Microsoft\Power\PowerSettings, then checks that no policy value is left. Exits 0 when the values are gone or an active MDM power policy still owns them, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $true

$PolicyRoot  = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings'
$MdmStateKey = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Power'
$BackupRoot  = Join-Path $env:ProgramData 'IntuneRemediations\Backup\TattooedPowerSettings'
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
$Phase       = 'Remediate'
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

function Backup-PowerSetting { param([string]$SettingId, [string]$Folder)
    $regPath = 'HKLM\SOFTWARE\Policies\Microsoft\Power\PowerSettings\' + $SettingId
    $file    = Join-Path $Folder ($SettingId + '.reg')
    & reg.exe export $regPath $file /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Backup failed for $SettingId with exit code $LASTEXITCODE" }
    Write-IRTLog "Backup written: $file"
}

try {
    $items = @(Get-TattooedPowerSetting)
    if ($items.Count -eq 0) { Exit-Script 0 'Healthy | TattooedPowerSettings=0' }

    $list = ($items | ForEach-Object { '{0}({1})' -f $_.Label, $_.Sides }) -join ','
    if (Test-MdmPowerPolicy) { Exit-Script 0 "Skipped | Count=$($items.Count); Settings=$list; Reason=MdmPowerPolicyActive" }
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | Count=$($items.Count); Settings=$list" }

    $folder = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop | Out-Null

    $removed = 0
    foreach ($item in $items) {
        Backup-PowerSetting -SettingId $item.Id -Folder $folder
        Remove-Item -LiteralPath $item.Key -Recurse -Force -ErrorAction Stop
        Write-IRTLog "Policy key removed: $($item.Id)"
        $removed++
    }

    $left = @(Get-TattooedPowerSetting)
    if ($left.Count -gt 0) {
        Exit-Script 1 "Failed | Removed=$removed; Remaining=$($left.Count); Settings=$list"
    }
    Exit-Script 0 "Fixed | Removed=$removed; Settings=$list; Backup=Yes"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
