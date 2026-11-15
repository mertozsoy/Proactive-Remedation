<#
.SYNOPSIS
  Remediation script that installs the missing SENSE Client feature on demand.

.DESCRIPTION
  Adds the Microsoft.Windows.Sense.Client capability with DISM, then verifies the
  capability state and starts the Sense service when it is present. Exits 0 when the
  capability is installed, 1 when it is still missing.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$CapabilityName      = 'Microsoft.Windows.Sense.Client~~~~'
$CapabilityPrefix    = 'Microsoft.Windows.Sense.Client'
$MinimumBuild        = 26100
$UnsupportedEditions = @('Core', 'CoreN', 'CoreSingleLanguage', 'CoreCountrySpecific')
$SourcePath          = ''
$VerificationSeconds = 60
$StartSenseService   = $true

$PackageName = 'MdeSenseCapability'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Get-DeviceScope {
    $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $build = 0
    if (-not [int]::TryParse([string]$currentVersion.CurrentBuildNumber, [ref]$build)) { throw 'BuildNumberUnreadable' }
    [pscustomobject]@{ Build = $build; Edition = [string]$currentVersion.EditionID }
}
function Get-CapabilityState { param([string]$Name, [string]$Prefix)
    try {
        $capability = Get-WindowsCapability -Online -Name $Name -ErrorAction Stop
        if ($null -ne $capability) { return [string]$capability.State }
    } catch { }
    try {
        $inventory = @(Get-WindowsCapability -Online -ErrorAction Stop)
    } catch { return 'Unknown' }
    $match = $inventory | Where-Object { $_.Name -like "$Prefix*" } | Select-Object -First 1
    if ($null -eq $match) { return 'Missing' }
    [string]$match.State
}
function Get-SenseState {
    $service = Get-Service -Name 'Sense' -ErrorAction SilentlyContinue
    if ($null -eq $service) { return 'Missing' }
    [string]$service.Status
}
function Install-SenseCapability { param([string]$Name, [string]$Source)
    $parameters = @{ Online = $true; Name = $Name; ErrorAction = 'Stop' }
    $usedSource = -not [string]::IsNullOrWhiteSpace($Source)
    if ($usedSource) {
        $parameters['Source'] = @($Source)
        $parameters['LimitAccess'] = $true
    }
    $started = Get-Date
    $result = Add-WindowsCapability @parameters
    $seconds = [int]((Get-Date) - $started).TotalSeconds
    $restart = 'Unknown'
    if ($null -ne $result) { $restart = [string]$result.RestartNeeded }
    Write-IRTLog "CapabilityInstall=Completed; Seconds=$seconds; RestartNeeded=$restart; UsedSource=$usedSource"
    $restart
}
function Wait-CapabilityInstalled { param([string]$Name, [string]$Prefix, [int]$Seconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $state = Get-CapabilityState -Name $Name -Prefix $Prefix
        if ($state -eq 'Installed') { return $state }
        if ((Get-Date) -ge $deadline) { return $state }
        Start-Sleep -Seconds 5
    } while ($true)
}
function Start-SenseIfNeeded {
    if (-not $StartSenseService) { return }
    if ((Get-SenseState) -ne 'Stopped') { return }
    try { Start-Service -Name 'Sense' -ErrorAction Stop }
    catch { Write-IRTLog "SenseStart=Failed; HResult=$($_.Exception.HResult)" 'WARN' }
}

try {
    $ErrorActionPreference = 'Stop'
    $scope = Get-DeviceScope
    if ($scope.Build -lt $MinimumBuild) { Exit-Script 0 "NotApplicable | Build=$($scope.Build); Reason=BuildBelow24H2" }
    if ($UnsupportedEditions -contains $scope.Edition) { Exit-Script 0 "NotApplicable | Edition=$($scope.Edition); Reason=UnsupportedEdition" }

    $capability = Get-CapabilityState -Name $CapabilityName -Prefix $CapabilityPrefix
    Write-IRTLog "Build=$($scope.Build); Edition=$($scope.Edition); Capability=$capability; Sense=$(Get-SenseState)"

    if ($capability -eq 'Installed') {
        Start-SenseIfNeeded
        Exit-Script 0 "Healthy | Build=$($scope.Build); Capability=Installed; Sense=$(Get-SenseState)"
    }

    $restartNeeded = Install-SenseCapability -Name $CapabilityName -Source $SourcePath
    $capability = Wait-CapabilityInstalled -Name $CapabilityName -Prefix $CapabilityPrefix -Seconds $VerificationSeconds
    if ($capability -ne 'Installed') {
        Exit-Script 1 "Failed | Reason=CapabilityNotInstalled; Capability=$capability; RestartNeeded=$restartNeeded"
    }

    Start-SenseIfNeeded
    $sense = Get-SenseState
    if ($sense -eq 'Missing') { Exit-Script 1 'Failed | Reason=SenseServiceMissing; Capability=Installed' }
    Exit-Script 0 "Fixed | Capability=Installed; Sense=$sense; RestartNeeded=$restartNeeded"
}
catch { Exit-Script 1 "Error: Failed | Reason=ServicingError; HResult=$($_.Exception.HResult)" }
