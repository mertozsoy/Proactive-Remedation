<#
.SYNOPSIS
  Detection script for the SENSE Client feature on demand used by Microsoft Defender for Endpoint.

.DESCRIPTION
  Reads the Windows build and edition, then the state of the Microsoft.Windows.Sense.Client
  capability and the Sense service. Exits 1 when the capability is missing on a supported
  device, 0 when it is installed or not applicable.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$CapabilityName      = 'Microsoft.Windows.Sense.Client~~~~'
$CapabilityPrefix    = 'Microsoft.Windows.Sense.Client'
$MinimumBuild        = 26100
$UnsupportedEditions = @('Core', 'CoreN', 'CoreSingleLanguage', 'CoreCountrySpecific')

$PackageName = 'MdeSenseCapability'
$Phase       = 'Detect'
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

try {
    $scope = Get-DeviceScope
    if ($scope.Build -lt $MinimumBuild) { Exit-Script 0 "NotApplicable | Build=$($scope.Build); Reason=BuildBelow24H2" }
    if ($UnsupportedEditions -contains $scope.Edition) { Exit-Script 0 "NotApplicable | Edition=$($scope.Edition); Reason=UnsupportedEdition" }

    $capability = Get-CapabilityState -Name $CapabilityName -Prefix $CapabilityPrefix
    $sense = Get-SenseState
    Write-IRTLog "Build=$($scope.Build); Edition=$($scope.Edition); Capability=$capability; Sense=$sense"

    if ($capability -eq 'Installed') { Exit-Script 0 "Healthy | Build=$($scope.Build); Capability=$capability; Sense=$sense" }
    if ($capability -eq 'Unknown') { Exit-Script 1 "Unknown | Build=$($scope.Build); Capability=$capability; Sense=$sense" }
    Exit-Script 1 "Drift | Build=$($scope.Build); Capability=$capability; Sense=$sense"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
