<#
.SYNOPSIS
  Detection script for User Account Control turned off in the local registry.

.DESCRIPTION
  Reads EnableLUA under the UAC policy key. Exits 1 if UAC is disabled, 0 if it is enabled or the key is absent.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExpectedEnableLUA = 1

$PackageName = 'EnableUAC'
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

$UacKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

try {
    if (-not (Test-Path -LiteralPath $UacKey)) { Exit-Script 0 'NotApplicable | UAC policy key not found' }

    $props = Get-ItemProperty -LiteralPath $UacKey -ErrorAction Stop
    if ($null -eq $props.PSObject.Properties['EnableLUA']) { Exit-Script 0 'Healthy | EnableLUA=default' }

    $enableLua = [int]$props.EnableLUA
    if ($enableLua -eq $ExpectedEnableLUA) { Exit-Script 0 "Healthy | EnableLUA=$enableLua" }

    $consent = 'absent'
    if ($null -ne $props.PSObject.Properties['ConsentPromptBehaviorAdmin']) { $consent = [int]$props.ConsentPromptBehaviorAdmin }
    Exit-Script 1 "Drift | EnableLUA=$enableLua; Expected=$ExpectedEnableLUA; ConsentPromptBehaviorAdmin=$consent"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
