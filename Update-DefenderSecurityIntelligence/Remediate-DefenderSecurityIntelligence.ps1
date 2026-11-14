<#
.SYNOPSIS
  Remediation script that updates Defender security intelligence.

.DESCRIPTION
  Tries the configured update sources in order until one succeeds.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'DefenderSecurityIntelligence'
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
    $before = (Get-MpComputerStatus).AntivirusSignatureVersion
    $ok = $false
    foreach ($src in @($null, 'MicrosoftUpdateServer', 'MMPC')) {
        try {
            if ($src) { Update-MpSignature -UpdateSource $src -ErrorAction Stop } else { Update-MpSignature -ErrorAction Stop }
            Write-IRTLog "Update-MpSignature succeeded (source=$(if ($src) { $src } else { 'Default' }))"
            $ok = $true; break
        } catch { Write-IRTLog "Source $(if ($src) { $src } else { 'Default' }) failed: $($_.Exception.Message)" 'WARN' }
    }

    if (-not $ok) {
        $mpCmd = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
        if (Test-Path $mpCmd) {
            $p = Start-Process -FilePath $mpCmd -ArgumentList '-SignatureUpdate' -Wait -PassThru -WindowStyle Hidden
            $ok = ($p.ExitCode -eq 0)
            Write-IRTLog "MpCmdRun -SignatureUpdate exit $($p.ExitCode)"
        }
    }

    $mp = Get-MpComputerStatus
    $summary = 'Before={0}; After={1}; AgeDays={2}' -f $before, $mp.AntivirusSignatureVersion, $mp.AntivirusSignatureAge
    if ($ok) { Exit-Script 0 "Updated | $summary" }
    Exit-Script 1 "All update sources failed | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
