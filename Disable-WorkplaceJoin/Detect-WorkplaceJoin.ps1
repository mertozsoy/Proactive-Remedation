<#
.SYNOPSIS
  Detection script for the Workplace Join block policy.

.DESCRIPTION
  Reads BlockAADWorkplaceJoin under HKLM\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin. Exits 1 if the value is missing or not 1, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PolicyKey     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin'
$ValueName     = 'BlockAADWorkplaceJoin'
$ExpectedValue = 1

$PackageName = 'WorkplaceJoin'
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

function Get-BlockState {
    param([string]$KeyPath, [string]$Name)
    if (-not (Test-Path -LiteralPath $KeyPath)) { return 'Missing' }
    $item = Get-ItemProperty -LiteralPath $KeyPath -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 'Missing' }
    $property = $item.PSObject.Properties[$Name]
    if ($null -eq $property) { return 'Missing' }
    return [string]$property.Value
}

try {
    $state = Get-BlockState -KeyPath $PolicyKey -Name $ValueName
    $text  = 'BlockAADWorkplaceJoin={0}; Expected={1}' -f $state, $ExpectedValue

    if ($state -eq [string]$ExpectedValue) { Exit-Script 0 "Healthy | $text" }
    Exit-Script 1 "Drift | $text"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
