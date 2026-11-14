<#
.SYNOPSIS
  Detection script for Defender for Endpoint sensor health.

.DESCRIPTION
  Checks the onboarding state and the Sense and DiagTrack services. Exits 1 if onboarding is incomplete or one of the services is not healthy.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'MDESensorHealth'
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
    $issues = @()
    $state = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status' -Name OnboardingState -ErrorAction SilentlyContinue).OnboardingState
    if ($state -ne 1) { $issues += "OnboardingState=$state" }

    foreach ($name in 'Sense', 'DiagTrack') {
        $s = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
        if (-not $s) { $issues += "$name=Missing"; continue }
        if ($s.StartMode -eq 'Disabled') { $issues += "$name=Disabled" }
        if ($s.State -ne 'Running')     { $issues += "$name=$($s.State)" }
    }

    $orgId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status' -Name OrgId -ErrorAction SilentlyContinue).OrgId
    $summary = "OnboardingState=$state; OrgId=$orgId"
    if ($issues) { Exit-Script 1 "Unhealthy ($($issues -join ',')) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
