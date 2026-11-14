<#
.SYNOPSIS
  Remediation script that turns User Account Control back on when it was disabled locally.

.DESCRIPTION
  Backs up the UAC policy key, sets EnableLUA to 1 and verifies the value. Exits 0 if UAC is on, 1 if the value could not be restored.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExpectedEnableLUA  = 1
$EnableRemediation  = $true
$BackupRoot         = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'EnableUAC'
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

$UacKey       = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$UacKeyNative = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

function Get-EnableLuaValue {
    if (-not (Test-Path -LiteralPath $UacKey)) { return $null }
    $props = Get-ItemProperty -LiteralPath $UacKey -ErrorAction Stop
    if ($null -eq $props.PSObject.Properties['EnableLUA']) { return $null }
    return [int]$props.EnableLUA
}

function Backup-UacKey {
    if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $target = Join-Path $BackupRoot "UAC-PoliciesSystem-$stamp.reg"
    & reg.exe export $UacKeyNative $target /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Registry backup failed with exit code $LASTEXITCODE" }
    Write-IRTLog "Backup written to $target"
    return $target
}

try {
    if (-not (Test-Path -LiteralPath $UacKey)) { Exit-Script 0 'NotApplicable | UAC policy key not found' }

    $current = Get-EnableLuaValue
    if ($null -eq $current) { Exit-Script 0 'Healthy | EnableLUA=default' }
    if ($current -eq $ExpectedEnableLUA) { Exit-Script 0 "Healthy | EnableLUA=$current" }

    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | EnableLUA=$current; Expected=$ExpectedEnableLUA" }

    $backupFile = Backup-UacKey
    New-ItemProperty -LiteralPath $UacKey -Name 'EnableLUA' -Value $ExpectedEnableLUA -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    Write-IRTLog "EnableLUA set to $ExpectedEnableLUA from $current"

    $after = Get-EnableLuaValue
    if ($after -ne $ExpectedEnableLUA) { Exit-Script 1 "Failed | EnableLUA=$after; Expected=$ExpectedEnableLUA" }

    $backupName = Split-Path -Leaf $backupFile
    Exit-Script 0 "Fixed | EnableLUA=$after; Restart=Required; Backup=$backupName"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
