<#
.SYNOPSIS
  Detection script for a broken Configuration Manager client on a co-managed device.

.DESCRIPTION
  Checks the SMS Agent Host service, the root\ccm WMI provider and the assigned site. Exits 1 if the service is stopped or disabled, the provider does not answer or the client has no site, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$CimTimeoutSeconds = 20

$PackageName = 'ConfigMgrClientHealth'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}
function Get-AgentServiceState {
    $service = @(Get-CimInstance -ClassName Win32_Service -Filter "Name='CcmExec'" -OperationTimeoutSec $CimTimeoutSeconds -ErrorAction SilentlyContinue)
    if ($service.Count -eq 0) {
        return [pscustomobject]@{ Present = $false; State = 'Absent'; StartMode = 'Absent' }
    }
    [pscustomobject]@{ Present = $true; State = [string]$service[0].State; StartMode = [string]$service[0].StartMode }
}
function Get-ClientWmiState {
    $result = [pscustomobject]@{ Ok = $false; Site = ''; Version = ''; HResult = 0 }
    try {
        $client = Get-CimInstance -Namespace 'root/ccm' -ClassName SMS_Client -OperationTimeoutSec $CimTimeoutSeconds -ErrorAction Stop
        $result.Version = [string]$client.ClientVersion
        $site = Invoke-CimMethod -Namespace 'root/ccm' -ClassName SMS_Client -MethodName GetAssignedSite -OperationTimeoutSec $CimTimeoutSeconds -ErrorAction Stop
        if ([int]$site.ReturnValue -eq 0) {
            $result.Site = [string]$site.sSiteCode
            $result.Ok = $true
        }
    }
    catch {
        $result.HResult = $_.Exception.HResult
    }
    $result
}

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 0 'NotApplicable | Reason=Requires64BitPowerShell' }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec $CimTimeoutSeconds -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=NotWorkstation' }

    $service = Get-AgentServiceState
    $clientKeyPresent = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\CCM' -ErrorAction SilentlyContinue
    if (-not $service.Present -and -not $clientKeyPresent) { Exit-Script 0 'NotApplicable | Reason=ConfigMgrClientNotFound' }

    $setup = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='ccmsetup.exe'" -OperationTimeoutSec $CimTimeoutSeconds -ErrorAction SilentlyContinue)
    if ($setup.Count -gt 0) { Exit-Script 0 "Busy | SetupProcesses=$($setup.Count); Action=WaitForSetup" }

    $wmi = Get-ClientWmiState
    $problems = @()
    if (-not $service.Present) { $problems += 'Service=Missing' }
    elseif ($service.State -ne 'Running') { $problems += "Service=$($service.State)" }
    if ($service.Present -and $service.StartMode -eq 'Disabled') { $problems += 'StartMode=Disabled' }
    if (-not $wmi.Ok) { $problems += 'Wmi=Unresponsive' }
    elseif ([string]::IsNullOrWhiteSpace($wmi.Site)) { $problems += 'Site=NotAssigned' }

    $wmiLabel = 'Unresponsive'
    if ($wmi.Ok) { $wmiLabel = 'OK' }
    $siteLabel = 'None'
    if (-not [string]::IsNullOrWhiteSpace($wmi.Site)) { $siteLabel = $wmi.Site }
    $versionLabel = 'Unknown'
    if (-not [string]::IsNullOrWhiteSpace($wmi.Version)) { $versionLabel = $wmi.Version }
    $summary = "Service=$($service.State); StartMode=$($service.StartMode); Wmi=$wmiLabel; Site=$siteLabel; Version=$versionLabel"

    if ($problems.Count -gt 0) { Exit-Script 1 "Drift | $summary; Problems=$($problems -join ',')" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Error: QueryFailed | HResult={0}; Action=ReviewCimAndAccess' -f $_.Exception.HResult) }
