<#
.SYNOPSIS
  Detection script for unused local user profiles.

.DESCRIPTION
  Lists profiles that have not been used for the configured number of days. Exits 1 if any are found.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$InactiveDays = 90

$ExcludeRegex = @('^admin', '^administrator$', '^defaultuser\d*$', '^ladmin', '^svc[_-]', '^kiosk')

$PackageName = 'StaleUserProfiles'
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

function Get-StaleProfiles {
    param([int]$Days, [string[]]$ExcludeRegex)
    $cutoff = (Get-Date).AddDays(-$Days)
    $plKey  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    foreach ($p in (Get-CimInstance Win32_UserProfile -Filter 'Special=False AND Loaded=False')) {
        if ($p.SID -notmatch '^S-1-(5-21|12-1)-') { continue }
        $name = Split-Path $p.LocalPath -Leaf
        if ($ExcludeRegex | Where-Object { $name -match $_ }) { continue }

        $k = Get-ItemProperty -Path (Join-Path $plKey $p.SID) -ErrorAction SilentlyContinue
        $last = $null
        if ($k -and $null -ne $k.LocalProfileUnloadTimeHigh) {

            $hi = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$k.LocalProfileUnloadTimeHigh), 0)
            $lo = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$k.LocalProfileUnloadTimeLow), 0)
            $ft = ([uint64]$hi -shl 32) -bor [uint64]$lo
            if ($ft -gt 0) { $last = [datetime]::FromFileTime([int64]$ft) }
        }
        if (-not $last) { $last = $p.LastUseTime }
        if ($last -and $last -lt $cutoff) {
            [pscustomobject]@{ Name = $name; SID = $p.SID; LastUsed = $last; Path = $p.LocalPath; Cim = $p }
        }
    }
}

try {
    $stale = @(Get-StaleProfiles -Days $InactiveDays -ExcludeRegex $ExcludeRegex)
    if ($stale.Count) {
        $list = ($stale | Sort-Object LastUsed | ForEach-Object { '{0}({1:yyyy-MM-dd})' -f $_.Name, $_.LastUsed }) -join ', '
        Exit-Script 1 "Stale=$($stale.Count) (>$InactiveDays d) | $list"
    }
    Exit-Script 0 "No profiles inactive for more than $InactiveDays days"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
