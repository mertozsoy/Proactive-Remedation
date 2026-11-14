<#
.SYNOPSIS
  Detection script for the automatic time zone setting.

.DESCRIPTION
  Checks the tzautoupdate service start value, the device level location consent and the Geolocation service. Exits 1 if automatic time zone cannot work, 0 if it is ready.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'AutoTimeZone'
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
    $autoStart = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' -Name 'Start'
    if ($null -eq $autoStart) { Exit-Script 0 'NotApplicable | tzautoupdate=NotFound' }

    $consent = Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -Name 'Value'
    $geo     = Get-CimInstance Win32_Service -Filter "Name='lfsvc'"
    $blocks  = @(Get-LocationPolicyBlock)

    $issues = @()
    if ([int]$autoStart -ne 3)            { $issues += "tzautoupdate=$autoStart" }
    if ($consent -ne 'Allow')             { $issues += "LocationConsent=$consent" }
    if (-not $geo)                        { $issues += 'lfsvc=NotFound' }
    elseif ($geo.StartMode -eq 'Disabled') { $issues += 'lfsvc=Disabled' }
    if ($blocks.Count -gt 0)              { $issues += "PolicyBlock=$($blocks -join '+')" }

    $summary = 'TimeZone={0}; AutoTimeZone={1}; LocationConsent={2}; lfsvc={3}' -f (Get-TimeZone).Id, $autoStart, $consent, $geo.StartMode
    if ($issues) { Exit-Script 1 "Unhealthy ($($issues -join ',')) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
