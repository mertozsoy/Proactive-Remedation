<#
.SYNOPSIS
  Detection script for Defender security intelligence age.

.DESCRIPTION
  Checks the signature age and antivirus state. Exits 1 if signatures are older than the threshold.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxSignatureAgeDays = 2

$PackageName = 'DefenderSecurityIntelligence'
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
    $mp = Get-MpComputerStatus -ErrorAction Stop
    $age = [Math]::Max([int]$mp.AntivirusSignatureAge, [int]$mp.AntispywareSignatureAge)
    $summary = 'Mode={0}; RTP={1}; SigVersion={2}; SigAgeDays={3}; Engine={4}; Platform={5}' -f `
        $mp.AMRunningMode, $mp.RealTimeProtectionEnabled, $mp.AntivirusSignatureVersion, $age, $mp.AMEngineVersion, $mp.AMProductVersion
    if ($age -gt $MaxSignatureAgeDays) { Exit-Script 1 "Stale | $summary" }
    Exit-Script 0 "Fresh | $summary"
}
catch { Exit-Script 1 "Error reading Defender status: $($_.Exception.Message)" }
