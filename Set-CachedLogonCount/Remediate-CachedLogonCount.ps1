<#
.SYNOPSIS
  Remediation script that limits the cached domain logon count.

.DESCRIPTION
  Exports the Winlogon key to a backup file and writes CachedLogonsCount as the allowed maximum. Reads the value back to verify the change. Exits 0 if the device is compliant or fixed, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxCachedLogons = 4
$BackupFolder = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'CachedLogonCount'
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

$WinlogonKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$ValueName = 'CachedLogonsCount'

function Get-CachedLogonsValue {
    $item = Get-ItemProperty -LiteralPath $WinlogonKey -Name $ValueName -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    if ($null -eq $item.$ValueName) { return $null }
    return [string]$item.$ValueName
}
function Backup-WinlogonKey {
    if (-not (Test-Path -LiteralPath $BackupFolder)) {
        New-Item -ItemType Directory -Path $BackupFolder -Force -ErrorAction Stop | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $file = Join-Path $BackupFolder "Winlogon_CachedLogonsCount_$stamp.reg"
    $arguments = 'export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "' + $file + '" /y'
    $process = Start-Process -FilePath "$env:SystemRoot\System32\reg.exe" -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $file)) {
        throw "Registry backup failed with exit code $($process.ExitCode)."
    }
    return $file
}

try {
    if ($MaxCachedLogons -lt 0 -or $MaxCachedLogons -gt 50) {
        Exit-Script 1 "Error: MaxCachedLogons=$MaxCachedLogons; AllowedRange=0-50"
    }
    if (-not (Test-Path -LiteralPath $WinlogonKey)) {
        Exit-Script 0 'NotApplicable | Winlogon key not found'
    }

    $raw = Get-CachedLogonsValue
    $current = -1
    if ($null -ne $raw -and $raw.Trim().Length -gt 0) {
        if ([int]::TryParse($raw.Trim(), [ref]$current)) {
            if ($current -ge 0 -and $current -le $MaxCachedLogons) {
                Exit-Script 0 "Healthy | CachedLogonsCount=$current; Max=$MaxCachedLogons; Action=None"
            }
        }
        else {
            $current = -1
            Write-IRTLog "Current value is not numeric: $($raw.Trim())" 'WARN'
        }
    }

    $backupFile = Backup-WinlogonKey
    Write-IRTLog "Backup saved: $backupFile"

    Set-ItemProperty -LiteralPath $WinlogonKey -Name $ValueName -Value ([string]$MaxCachedLogons) -Type String -Force -ErrorAction Stop
    Write-IRTLog "CachedLogonsCount written: $MaxCachedLogons"

    $verifyRaw = Get-CachedLogonsValue
    $verified = -1
    if ($null -eq $verifyRaw -or -not [int]::TryParse($verifyRaw.Trim(), [ref]$verified)) {
        Exit-Script 1 "Failed | CachedLogonsCount=Unreadable; Expected=$MaxCachedLogons"
    }
    if ($verified -ne $MaxCachedLogons) {
        Exit-Script 1 "Failed | CachedLogonsCount=$verified; Expected=$MaxCachedLogons"
    }

    $previous = 'Missing'
    if ($current -ge 0) { $previous = [string]$current }
    elseif ($null -ne $raw -and $raw.Trim().Length -gt 0) { $previous = $raw.Trim() }

    Exit-Script 0 "Fixed | CachedLogonsCount=$previous->$verified; Max=$MaxCachedLogons; Backup=$([System.IO.Path]::GetFileName($backupFile)); AppliesAt=next domain sign-in"
}
catch { Exit-Script 1 "Error: Operation=RemediateCachedLogonCount; Exception=$($_.Exception.GetType().Name)" }
