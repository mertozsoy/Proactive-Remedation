<#
.SYNOPSIS
  Remediation script for Defender for Endpoint sensor health.

.DESCRIPTION
  Sets the required services back to their default start type and starts them.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'MDESensorHealth'
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
    $done = @()
    $diag = Get-Service -Name DiagTrack -ErrorAction SilentlyContinue
    if ($diag) {
        if ($diag.StartType -ne 'Automatic') { Set-Service -Name DiagTrack -StartupType Automatic -ErrorAction Stop; $done += 'DiagTrack->Automatic' }
        if ((Get-Service DiagTrack).Status -ne 'Running') { Start-Service DiagTrack -ErrorAction Stop; $done += 'DiagTrack started' }
    }

    $sense = Get-Service -Name Sense -ErrorAction SilentlyContinue
    if (-not $sense) { Exit-Script 1 "Sense service missing (Windows edition / feature). $($done -join '; ')" }
    if ($sense.Status -ne 'Running') {
        try { Start-Service Sense -ErrorAction Stop; $done += 'Sense started' }
        catch { Write-IRTLog "Sense start failed: $($_.Exception.Message)" 'WARN'; $done += 'Sense start FAILED' }
    }

    $state = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status' -Name OnboardingState -ErrorAction SilentlyContinue).OnboardingState
    if ($state -ne 1) { Exit-Script 1 "Not onboarded (OnboardingState=$state). Check EDR onboarding policy. $($done -join '; ')" }

    if (-not $done) { $done = @('Nothing to change') }
    Exit-Script 0 ($done -join '; ')
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
