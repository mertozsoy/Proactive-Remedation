<#
.SYNOPSIS
  Remediation script that registers the Microsoft Update service and turns on Microsoft product updates.

.DESCRIPTION
  Sets the Windows Update UX value for Microsoft product updates and registers the Microsoft Update service through the Windows Update Agent. Leaves a policy that blocks Microsoft product updates unchanged. Exits 0 when the service is registered, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MuServiceId      = '7971f918-a847-4430-9279-4a52d1efe18d'
$UxSettingsKey    = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
$UxValueName      = 'AllowMUUpdateService'
$PolicyClass      = 'MDM_Policy_Config01_Update02'
$PolicyProperty   = 'AllowMUUpdateService'
$TriggerScan      = $false

$PackageName = 'MicrosoftUpdateService'
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

function Register-MuService {
    $manager = New-Object -ComObject 'Microsoft.Update.ServiceManager'
    try {
        $manager.ClientApplicationID = 'IntuneRemediation'
        $existing = $null
        foreach ($service in $manager.Services) {
            if ([string]$service.ServiceID -eq $MuServiceId) { $existing = $service }
        }
        if ($null -eq $existing) {
            $null = $manager.AddService2($MuServiceId, 7, '')
            Write-IRTLog 'Microsoft Update service added'
            return 'Added'
        }
        if (-not [bool]$existing.IsRegisteredWithAU) {
            $manager.RegisterServiceWithAU($MuServiceId)
            Write-IRTLog 'Microsoft Update service registered with Automatic Updates'
            return 'RegisteredWithAU'
        }
        return 'AlreadyRegistered'
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

    if ($policy -eq 0) {
        Exit-Script 0 "NotApplicable | PolicyManaged; MuSetting=$ux; Setting=Unchanged; Service=Unchanged"
    }

    $changes = @()

    if ($ux -ne 1) {
        if (-not (Test-Path -LiteralPath $UxSettingsKey)) { $null = New-Item -Path $UxSettingsKey -Force -ErrorAction Stop }
        Set-ItemProperty -LiteralPath $UxSettingsKey -Name $UxValueName -Value 1 -Type DWord -ErrorAction Stop
        $changes += 'Setting'
        Write-IRTLog 'AllowMUUpdateService set to 1'
    }

    if ($null -eq $service -or -not $service.Registered) {
        $null = Register-MuService
        $changes += 'Service'
    }

    if ($TriggerScan) {
        $autoUpdate = New-Object -ComObject 'Microsoft.Update.AutoUpdate'
        try { $autoUpdate.DetectNow() } finally { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($autoUpdate) }
        $scan = 'Started'
    }
    else { $scan = 'NotTriggered' }

    $uxAfter = Get-UxValue
    $serviceAfter = Get-MuServiceState
    $registered = ($null -ne $serviceAfter -and $serviceAfter.Registered)
    $changed = $changes -join ','
    if (-not $changed) { $changed = 'None' }

    if (-not $registered) {
        Exit-Script 1 "Failed | MuService=NotRegistered; MuSetting=$uxAfter; Changed=$changed; Scan=$scan"
    }

    if ($policy -ne 1 -and $uxAfter -ne 1) {
        Exit-Script 1 "Failed | MuService=Registered; MuSetting=$uxAfter; Changed=$changed; Scan=$scan"
    }

    Exit-Script 0 "Fixed | MuService=Registered; MuSetting=$uxAfter; Changed=$changed; Scan=$scan"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
