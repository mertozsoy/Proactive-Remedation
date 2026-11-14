<#
.SYNOPSIS
  Remediation script for Windows time synchronization.

.DESCRIPTION
  Starts the Windows Time service, sets the correct source for the join type and resyncs the clock.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$NtpPeer = 'time.windows.com,0x9'

$PackageName = 'TimeSync'
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

try {
    Set-Service -Name W32Time -StartupType Automatic -ErrorAction Stop
    if ((Get-Service W32Time).Status -ne 'Running') { Start-Service W32Time -ErrorAction Stop }

    $partOfDomain = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
    if ($partOfDomain) {
        $cfg = & w32tm.exe /config /syncfromflags:domhier /update 2>&1
        $mode = 'domhier'
    } else {
        $cfg = & w32tm.exe /config /manualpeerlist:"$NtpPeer" /syncfromflags:manual /reliable:no /update 2>&1
        $mode = "manual($NtpPeer)"
    }
    Write-IRTLog "w32tm /config ($mode): $($cfg -join ' ')"

    Restart-Service W32Time -Force -ErrorAction Stop
    Start-Sleep -Seconds 5
    $rs = & w32tm.exe /resync /force 2>&1
    $rc = $LASTEXITCODE
    Write-IRTLog "w32tm /resync exit $rc : $($rs -join ' ')"

    $src = ((& w32tm.exe /query /source 2>$null) | Select-Object -First 1)
    if ($rc -eq 0) { Exit-Script 0 "Configured $mode; resync OK; source=$src" }
    Exit-Script 1 "Configured $mode; resync failed (exit $rc, device may be off-network); source=$src"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
