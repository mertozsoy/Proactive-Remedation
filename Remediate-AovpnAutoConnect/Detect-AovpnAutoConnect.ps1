<#
.SYNOPSIS
  Detection script for Always On VPN profiles stuck in the auto-trigger disabled list.

.DESCRIPTION
  Reads the AutoTriggerDisabledProfilesList value under the RasMan Config key. Lists the profile names that Windows will not connect automatically. Exits 1 if the list has entries, 0 if not.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ProfileNames = @()

$RasManConfigKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\RasMan\Config'
$ValueName       = 'AutoTriggerDisabledProfilesList'

$PackageName = 'AovpnAutoConnect'
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

function Get-RegistryProfileList {
    $raw = (Get-ItemProperty -LiteralPath $RasManConfigKey -Name $ValueName -ErrorAction SilentlyContinue).$ValueName
    if ($null -eq $raw) { return @() }
    @($raw | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
}

function Get-DisabledProfileName {
    $names = @(Get-RegistryProfileList)
    if ($ProfileNames.Count -gt 0) {
        $names = @($names | Where-Object { $ProfileNames -contains $_ })
    }
    @($names | Select-Object -Unique)
}

try {
    if (-not (Test-Path -LiteralPath $RasManConfigKey)) { Exit-Script 0 'NotApplicable | RasMan config key not found' }

    $disabled = @(Get-DisabledProfileName)
    if ($disabled.Count -eq 0) { Exit-Script 0 'Healthy | AutoTriggerDisabled=0' }

    $list = ($disabled | Sort-Object) -join ';'
    Exit-Script 1 "Drift | Profiles=$($disabled.Count); Names=$list"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
