<#
.SYNOPSIS
  Remediation script that repairs a broken Configuration Manager client on a co-managed device.

.DESCRIPTION
  Restores the SMS Agent Host service, restarts it when the root\ccm provider does not answer, sends a policy request and verifies the assigned site. Exits 0 when the client answers and has a site, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RestartAgentHost          = $true
$EnableClientReinstall     = $false
$ServiceWaitSeconds        = 60
$WmiRetrySeconds           = 90
$ReinstallTimeoutSeconds   = 1800
$CimTimeoutSeconds         = 20

$PackageName = 'ConfigMgrClientHealth'
$Phase       = 'Remediate'
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
function Get-SetupProcess {
    @(Get-CimInstance -ClassName Win32_Process -Filter "Name='ccmsetup.exe'" -OperationTimeoutSec $CimTimeoutSeconds -ErrorAction SilentlyContinue)
}
function Get-ClientSummary {
    param($Service, $Wmi)
    $wmiLabel = 'Unresponsive'
    if ($Wmi.Ok) { $wmiLabel = 'OK' }
    $siteLabel = 'None'
    if (-not [string]::IsNullOrWhiteSpace($Wmi.Site)) { $siteLabel = $Wmi.Site }
    $versionLabel = 'Unknown'
    if (-not [string]::IsNullOrWhiteSpace($Wmi.Version)) { $versionLabel = $Wmi.Version }
    "Service=$($Service.State); StartMode=$($Service.StartMode); Wmi=$wmiLabel; Site=$siteLabel; Version=$versionLabel"
}

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 0 'NotApplicable | Reason=Requires64BitPowerShell' }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec $CimTimeoutSeconds -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=NotWorkstation' }

    $service = Get-AgentServiceState
    $clientKeyPresent = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\CCM' -ErrorAction SilentlyContinue
    if (-not $service.Present -and -not $clientKeyPresent) { Exit-Script 0 'NotApplicable | Reason=ConfigMgrClientNotFound' }

    $wmi = Get-ClientWmiState
    $changes = @()

    $setup = Get-SetupProcess
    if ($setup.Count -gt 0) { Exit-Script 0 "Busy | SetupProcesses=$($setup.Count); Changes=None; Action=WaitForSetup" }

    if (-not $service.Present -and -not $EnableClientReinstall) {
        Exit-Script 1 'Failed | Reason=CcmExecMissing; Changes=None; Action=ReinstallClientManually'
    }

    if ($service.Present) {
        if ($service.StartMode -eq 'Disabled' -or $service.StartMode -eq 'Manual') {
            Set-Service -Name 'CcmExec' -StartupType Automatic -ErrorAction Stop
            $changes += "StartMode=$($service.StartMode)->Automatic"
            Write-IRTLog "CcmExec start mode changed from $($service.StartMode) to Automatic"
        }
        if ($service.State -ne 'Running') {
            Start-Service -Name 'CcmExec' -ErrorAction Stop
            $changes += "Service=$($service.State)->Start"
            Write-IRTLog "CcmExec start requested"
        }
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        while ($timer.Elapsed.TotalSeconds -lt $ServiceWaitSeconds) {
            $service = Get-AgentServiceState
            if ($service.State -eq 'Running') { break }
            Start-Sleep -Seconds 3
        }
    }

    if (-not $wmi.Ok -and $RestartAgentHost -and $service.Present) {
        Restart-Service -Name 'CcmExec' -Force -ErrorAction Stop
        $changes += 'AgentHostRestarted=1'
        Write-IRTLog 'CcmExec restarted because the root\ccm provider did not answer'
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        while ($timer.Elapsed.TotalSeconds -lt $WmiRetrySeconds) {
            Start-Sleep -Seconds 5
            $wmi = Get-ClientWmiState
            if ($wmi.Ok) { break }
        }
    }

    if (-not $wmi.Ok -and $EnableClientReinstall) {
        $setupPath = Join-Path $env:windir 'ccmsetup\ccmsetup.exe'
        if (Test-Path -LiteralPath $setupPath -PathType Leaf -ErrorAction Stop) {
            $signature = Get-AuthenticodeSignature -LiteralPath $setupPath -ErrorAction Stop
            $publisher = ''
            if ($null -ne $signature.SignerCertificate) {
                $publisher = $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
            }
            if ($signature.Status -ne 'Valid' -or $publisher -ne 'Microsoft Corporation') {
                Exit-Script 1 'Failed | Reason=SetupSignatureInvalid; Changes=None; Action=ReviewTrustedClientSource'
            }
            $process = Start-Process -FilePath $setupPath -ArgumentList '/forceinstall' -WorkingDirectory (Split-Path -Path $setupPath -Parent) -PassThru -WindowStyle Hidden -ErrorAction Stop
            if (-not $process.WaitForExit([int]($ReinstallTimeoutSeconds * 1000))) {
                Exit-Script 1 'Failed | Reason=ReinstallTimeout; Changes=None; Action=ReviewCCMSetupLog'
            }
            $process.Refresh()
            $changes += "ClientReinstall=ExitCode$($process.ExitCode)"
            Write-IRTLog "ccmsetup /forceinstall finished with exit code $($process.ExitCode)"
            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            while ($timer.Elapsed.TotalSeconds -lt $WmiRetrySeconds) {
                Start-Sleep -Seconds 5
                $wmi = Get-ClientWmiState
                if ($wmi.Ok) { break }
            }
        }
    }

    if ($wmi.Ok) {
        try {
            Invoke-CimMethod -Namespace 'root/ccm' -ClassName SMS_Client -MethodName TriggerSchedule -Arguments @{ sScheduleID = '{00000000-0000-0000-0000-000000000021}' } -OperationTimeoutSec $CimTimeoutSeconds -ErrorAction Stop | Out-Null
            $changes += 'PolicyRequest=Sent'
        }
        catch {
            $changes += 'PolicyRequest=Failed'
        }
    }

    $service = Get-AgentServiceState
    $wmi = Get-ClientWmiState
    $summary = Get-ClientSummary -Service $service -Wmi $wmi
    $changeLabel = 'None'
    if ($changes.Count -gt 0) { $changeLabel = $changes -join ',' }

    if (-not $service.Present -or $service.State -ne 'Running' -or -not $wmi.Ok -or [string]::IsNullOrWhiteSpace($wmi.Site)) {
        Exit-Script 1 "Failed | $summary; Changes=$changeLabel; Action=ReviewCcmExecServiceAndCcmLogs"
    }
    if ($changes.Count -eq 0) { Exit-Script 0 "Healthy | $summary" }
    Exit-Script 0 "Fixed | $summary; Changes=$changeLabel"
}
catch { Exit-Script 1 ('Error: RepairFailed | HResult={0}; Action=ReviewCcmExecServiceAndCcmLogs' -f $_.Exception.HResult) }
