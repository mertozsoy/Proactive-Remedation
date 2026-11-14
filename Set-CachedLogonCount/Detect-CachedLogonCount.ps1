<#
.SYNOPSIS
  Detection script for the cached domain logon count.

.DESCRIPTION
  Reads CachedLogonsCount under the Winlogon key and compares it with the allowed maximum. Exits 1 if the value is missing, invalid or above the maximum, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxCachedLogons = 4

$PackageName = 'CachedLogonCount'
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

$WinlogonKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$ValueName = 'CachedLogonsCount'

function Get-CachedLogonsValue {
    $item = Get-ItemProperty -LiteralPath $WinlogonKey -Name $ValueName -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    if ($null -eq $item.$ValueName) { return $null }
    return [string]$item.$ValueName
}

try {
    if ($MaxCachedLogons -lt 0 -or $MaxCachedLogons -gt 50) {
        Exit-Script 1 "Error: MaxCachedLogons=$MaxCachedLogons; AllowedRange=0-50"
    }
    if (-not (Test-Path -LiteralPath $WinlogonKey)) {
        Exit-Script 0 'NotApplicable | Winlogon key not found'
    }

    $raw = Get-CachedLogonsValue
    if ($null -eq $raw -or $raw.Trim().Length -eq 0) {
        Exit-Script 1 "Drift | CachedLogonsCount=Missing; EffectiveDefault=10; Max=$MaxCachedLogons"
    }

    $count = 0
    if (-not [int]::TryParse($raw.Trim(), [ref]$count)) {
        Exit-Script 1 "Drift | CachedLogonsCount=$($raw.Trim()); State=NotNumeric; Max=$MaxCachedLogons"
    }
    if ($count -lt 0 -or $count -gt 50) {
        Exit-Script 1 "Drift | CachedLogonsCount=$count; State=OutOfRange; Max=$MaxCachedLogons"
    }
    if ($count -gt $MaxCachedLogons) {
        Exit-Script 1 "Drift | CachedLogonsCount=$count; Max=$MaxCachedLogons"
    }

    Exit-Script 0 "Healthy | CachedLogonsCount=$count; Max=$MaxCachedLogons"
}
catch { Exit-Script 1 "Error: Operation=DetectCachedLogonCount; Exception=$($_.Exception.GetType().Name)" }
