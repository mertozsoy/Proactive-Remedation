<#
.SYNOPSIS
  Detection script for a Microsoft Update service that is not registered with Windows Update.

.DESCRIPTION
  Reads the Microsoft product updates policy and the Windows Update UX setting, then checks whether the Microsoft Update service is registered with Automatic Updates. Exits 1 if the service is missing or the setting is off, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MuServiceId    = '7971f918-a847-4430-9279-4a52d1efe18d'
$UxSettingsKey  = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
$UxValueName    = 'AllowMUUpdateService'
$PolicyClass    = 'MDM_Policy_Config01_Update02'
$PolicyProperty = 'AllowMUUpdateService'

$PackageName = 'MicrosoftUpdateService'
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

function Get-PolicyValue {
    try {
        $item = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName $PolicyClass -ErrorAction Stop
        $value = $item.$PolicyProperty
        if ($null -eq $value) { return $null }
        return [int]$value
    }
    catch { return $null }
}

function Get-UxValue {
    try {
        $value = (Get-ItemProperty -LiteralPath $UxSettingsKey -Name $UxValueName -ErrorAction Stop).$UxValueName
        return [int]$value
    }
    catch { return $null }
}

function Get-MuServiceState {
    $manager = New-Object -ComObject 'Microsoft.Update.ServiceManager'
    try {
        $manager.ClientApplicationID = 'IntuneRemediation'
        $found = $null
        foreach ($service in $manager.Services) {
            if ([string]$service.ServiceID -eq $MuServiceId) {
                $found = [pscustomobject]@{ Name = [string]$service.Name; Registered = [bool]$service.IsRegisteredWithAU }
            }
        }
        return $found
    }
    finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($manager)
    }
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ([int]$os.BuildNumber -lt 14393) { Exit-Script 0 'NotApplicable | Reason=RequiresWindows10OrLater' }

    $policy = Get-PolicyValue
    $ux = Get-UxValue
    $service = Get-MuServiceState

    $policyText = 'NotConfigured'
    if ($null -ne $policy) { $policyText = [string]$policy }

    $serviceState = 'NotRegistered'
    if ($null -ne $service -and $service.Registered) { $serviceState = 'Registered' }

    if ($policy -eq 0) {
        Exit-Script 0 "PolicyManaged | MuService=$serviceState; MuSetting=$ux; Policy=Blocked; Action=None"
    }

    if ($serviceState -eq 'Registered' -and ($policy -eq 1 -or $ux -eq 1)) {
        Exit-Script 0 "Healthy | MuService=Registered; MuSetting=$ux; Policy=$policyText"
    }

    Exit-Script 1 "Drift | MuService=$serviceState; MuSetting=$ux; Policy=$policyText"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
