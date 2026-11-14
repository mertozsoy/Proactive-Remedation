<#
.SYNOPSIS
  Remediation script for Windows Recovery Environment.

.DESCRIPTION
  Enables WinRE with reagentc and checks the result.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'WinRE'
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
    $out = & reagentc.exe /enable 2>&1
    $rc  = $LASTEXITCODE
    Write-IRTLog "reagentc /enable exit $rc : $($out -join ' ')"
    if ($rc -eq 0) { Exit-Script 0 'WinRE enabled.' }

    $wim = Join-Path $env:WINDIR 'System32\Recovery\Winre.wim'
    $hint = if (Test-Path $wim) { 'Winre.wim present; check recovery partition size/ID.' } else { 'Winre.wim missing from System32\Recovery; restore it from matching install media.' }
    Exit-Script 1 "reagentc /enable failed (exit $rc). $hint"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
