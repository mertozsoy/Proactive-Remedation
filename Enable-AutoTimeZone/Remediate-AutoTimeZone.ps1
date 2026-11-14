<#
.SYNOPSIS
  Remediation script for the automatic time zone setting.

.DESCRIPTION
  Sets tzautoupdate to 3, allows location at device level and makes sure the Geolocation service can start. Does nothing if a policy turns location off. Exits 0 if the settings are in place, 1 if not.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'AutoTimeZone'
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

function Get-RegValue { param([string]$Path, [string]$Name)
    return (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue).$Name
}

function Get-LocationPolicyBlock {
    $blocks = @()
    if ((Get-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name 'DisableLocation') -eq 1) { $blocks += 'GPO:DisableLocation' }
    $allow = Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\System' -Name 'AllowLocation'
    if ($null -ne $allow -and [int]$allow -eq 0) { $blocks += 'MDM:AllowLocation' }
    return $blocks
}

try {
    $blocks = @(Get-LocationPolicyBlock)
    if ($blocks.Count -gt 0) { Exit-Script 1 "Blocked | PolicyBlock=$($blocks -join '+'); Action=None" }

    $tzKey      = 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate'
    $consentKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
    $before     = (Get-TimeZone).Id
    $actions    = @()

    if ([int](Get-RegValue -Path $tzKey -Name 'Start') -ne 3) {
        Set-ItemProperty -LiteralPath $tzKey -Name 'Start' -Value 3 -Type DWord -ErrorAction Stop
        $actions += 'AutoTimeZoneOn'
    }

    if ((Get-RegValue -Path $consentKey -Name 'Value') -ne 'Allow') {
        if (-not (Test-Path -LiteralPath $consentKey)) { New-Item -Path $consentKey -Force | Out-Null }
        Set-ItemProperty -LiteralPath $consentKey -Name 'Value' -Value 'Allow' -Type String -ErrorAction Stop
        $actions += 'LocationAllowed'
    }

    $geo = Get-CimInstance Win32_Service -Filter "Name='lfsvc'"
    if ($geo -and $geo.StartMode -eq 'Disabled') {
        Set-Service -Name lfsvc -StartupType Manual -ErrorAction Stop
        $actions += 'lfsvcManual'
    }
    if ($geo -and (Get-Service lfsvc).Status -ne 'Running') {
        try { Start-Service lfsvc -ErrorAction Stop; $actions += 'lfsvcStarted' } catch { Write-IRTLog "lfsvc start: $($_.Exception.Message)" 'WARN' }
    }
    try { Start-Service tzautoupdate -ErrorAction Stop } catch { Write-IRTLog "tzautoupdate start: $($_.Exception.Message)" 'WARN' }

    $autoStart = Get-RegValue -Path $tzKey -Name 'Start'
    $consent   = Get-RegValue -Path $consentKey -Name 'Value'
    $geo       = Get-CimInstance Win32_Service -Filter "Name='lfsvc'"
    $ok        = ([int]$autoStart -eq 3) -and ($consent -eq 'Allow') -and $geo -and ($geo.StartMode -ne 'Disabled')

    $summary = 'TimeZoneBefore={0}; AutoTimeZone={1}; LocationConsent={2}; lfsvc={3}; Actions={4}' -f $before, $autoStart, $consent, $geo.StartMode, ($actions -join ',')
    if ($ok) { Exit-Script 0 "Remediated | $summary" }
    Exit-Script 1 "Failed | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
