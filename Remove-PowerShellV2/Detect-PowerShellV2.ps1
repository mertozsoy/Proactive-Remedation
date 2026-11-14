<#
.SYNOPSIS
  Detection script for the Windows PowerShell 2.0 engine.

.DESCRIPTION
  Exits 1 if the PowerShell 2.0 optional feature is enabled, 0 if it is disabled or not present.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'PowerShellV2'
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
    $f = Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object { $_.FeatureName -in 'MicrosoftWindowsPowerShellV2Root', 'MicrosoftWindowsPowerShellV2' }
    $enabled = @($f | Where-Object { $_.State -eq 'Enabled' })
    if (-not $f) { Exit-Script 0 'Compliant | PowerShell 2.0 feature not present on this build' }
    $summary = ($f | ForEach-Object { "$($_.FeatureName)=$($_.State)" }) -join '; '
    if ($enabled.Count) { Exit-Script 1 "Enabled | $summary" }
    Exit-Script 0 "Compliant | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
