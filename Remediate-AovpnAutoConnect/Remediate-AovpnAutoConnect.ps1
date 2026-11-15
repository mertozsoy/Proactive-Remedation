<#
.SYNOPSIS
  Remediation script that re-enables Always On VPN auto-connect for blocked profiles.

.DESCRIPTION
  Backs up the RasMan Config key, removes the profile names from AutoTriggerDisabledProfilesList and verifies the result. Exits 0 if the names are gone, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ProfileNames      = @()
$EnableRemediation = $true
$BackupFolder      = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$RasManConfigKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\RasMan\Config'
$ValueName       = 'AutoTriggerDisabledProfilesList'

$PackageName = 'AovpnAutoConnect'
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

function Get-RegistryProfileList {
    $raw = (Get-ItemProperty -LiteralPath $RasManConfigKey -Name $ValueName -ErrorAction SilentlyContinue).$ValueName
    if ($null -eq $raw) { return @() }
    @($raw | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
}

function Get-DisabledProfileName {
    $names = @(Get-RegistryProfileList)
    if ($ProfileNames.Count -gt 0) {
        $names = @($names | Where-Object { $ProfileNames -contains $_ })
    }
    @($names | Select-Object -Unique)
}

function Backup-RasManConfig {
    if (-not (Test-Path -LiteralPath $BackupFolder)) {
        New-Item -ItemType Directory -Path $BackupFolder -Force -ErrorAction Stop | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $file  = Join-Path $BackupFolder ('RasManConfig_{0}.reg' -f $stamp)
    $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
    & $regExe export 'HKLM\SYSTEM\CurrentControlSet\Services\RasMan\Config' $file /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) { return $null }
    $file
}

try {
    if (-not (Test-Path -LiteralPath $RasManConfigKey)) { Exit-Script 0 'NotApplicable | RasMan config key not found' }

    $disabled = @(Get-DisabledProfileName)
    if ($disabled.Count -eq 0) { Exit-Script 0 'Healthy | AutoTriggerDisabled=0' }

    $list = ($disabled | Sort-Object) -join ';'
    if (-not $EnableRemediation) { Exit-Script 1 "Drift | Profiles=$($disabled.Count); Names=$list; Remediation=Disabled" }

    $backup = Backup-RasManConfig
    if (-not $backup) { Exit-Script 1 "Failed | Backup=Failed; Names=$list" }
    Write-IRTLog "Backup written: $backup"

    $allNames  = @(Get-RegistryProfileList)
    $remaining = @($allNames | Where-Object { $disabled -notcontains $_ })

    if ($remaining.Count -eq 0) {
        Remove-ItemProperty -LiteralPath $RasManConfigKey -Name $ValueName -Force -ErrorAction Stop
    }
    else {
        Set-ItemProperty -LiteralPath $RasManConfigKey -Name $ValueName -Value ([string[]]$remaining) -Type MultiString -Force -ErrorAction Stop
    }

    $left = @(Get-DisabledProfileName)
    $names = ($disabled | Sort-Object) -join ';'
    $backupName = Split-Path -Path $backup -Leaf
    if ($left.Count -gt 0) { Exit-Script 1 "Failed | Remaining=$($left.Count); Names=$names" }
    Exit-Script 0 "Fixed | Profiles=$($disabled.Count); Removed=$names; Backup=$backupName"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
