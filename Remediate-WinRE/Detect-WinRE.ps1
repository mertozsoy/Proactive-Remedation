<#
.SYNOPSIS
  Detection script for Windows Recovery Environment.

.DESCRIPTION
  Checks reagentc status. Exits 1 if WinRE is disabled.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'WinRE'
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

try {
    $xmlPath = Join-Path $env:WINDIR 'System32\Recovery\ReAgent.xml'
    $state = $null
    if (Test-Path $xmlPath) {
        [xml]$x = Get-Content -LiteralPath $xmlPath -Raw
        $state = $x.WindowsRE.InstallState.state
        $loc   = $x.WindowsRE.WinreLocation.path
    }
    if ($null -eq $state) {
        $info = (& reagentc.exe /info) -join ' '
        if ($info -match 'Enabled|Etkin') { $state = '1' } elseif ($info -match 'Disabled|Devre') { $state = '0' }
    }
    $summary = "InstallState=$state; Location=$loc"
    if ($state -eq '1') { Exit-Script 0 "Enabled | $summary" }
    Exit-Script 1 "Disabled | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
