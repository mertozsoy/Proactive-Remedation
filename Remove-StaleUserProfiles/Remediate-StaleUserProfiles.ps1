<#
.SYNOPSIS
  Remediation script for unused local user profiles.

.DESCRIPTION
  Removes unused profiles. Runs in report mode until $Enforce is set to $true.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$Enforce = $false
$InactiveDays = 90

$ExcludeRegex = @('^admin', '^administrator$', '^defaultuser\d*$', '^ladmin', '^svc[_-]', '^kiosk')

$PackageName = 'StaleUserProfiles'
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
    if (-not $stale.Count) { Exit-Script 0 'Nothing to remove' }

    $removed = @(); $failed = @()
    foreach ($s in $stale) {
        if (-not $Enforce) { Write-IRTLog "WHATIF remove $($s.Name) $($s.SID) last used $($s.LastUsed)"; continue }
        try {
            Remove-CimInstance -InputObject $s.Cim -ErrorAction Stop
            $removed += $s.Name
            Write-IRTLog "Removed $($s.Name) $($s.SID)"
        } catch {
            $failed += $s.Name
            Write-IRTLog "Failed $($s.Name): $($_.Exception.Message)" 'ERROR'
        }
    }

    if (-not $Enforce) { Exit-Script 0 "ReportOnly: would remove $($stale.Count): $(($stale.Name) -join ', ')" }
    if ($failed) { Exit-Script 1 "Removed=$($removed.Count) Failed=$($failed.Count): $($failed -join ', ')" }
    Exit-Script 0 "Removed=$($removed.Count): $($removed -join ', ')"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
