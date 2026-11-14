<#
.SYNOPSIS
  Detection script for AAD BrokerPlugin and CloudExperienceHost registration.

.DESCRIPTION
  Checks current-user registration, AppX status and Windows manifests. Exits 1 for missing or unhealthy components or a requested re-registration, 0 otherwise. Does not test interactive sign-in.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ForceReregister = $false

$PackageName = 'WamRegistration'
$Phase = 'Detect'
$LogDir = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile = Join-Path $LogDir "IRT_$PackageName.log"

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
function Get-WamState {
    foreach ($name in @('Microsoft.AAD.BrokerPlugin', 'Microsoft.Windows.CloudExperienceHost')) {
        $family = $name + '_cw5n1h2txyewy'
        $manifest = Join-Path $env:windir "SystemApps\$family\AppxManifest.xml"
        $apps = @(Get-AppxPackage -Name $name -ErrorAction Stop)
        $state = 'OK'
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf -ErrorAction Stop)) { $state = 'SourceMissing' }
        elseif ($apps.Count -eq 0) { $state = 'Missing' }
        elseif ($apps.Count -ne 1) { $state = 'Ambiguous' }
        elseif ($apps[0].PackageFamilyName -ne $family) { $state = 'UnexpectedFamily' }
        elseif ([string]$apps[0].Status -ne 'Ok') { $state = 'Unhealthy' }
        elseif ([string]::IsNullOrWhiteSpace([string]$apps[0].InstallLocation)) { $state = 'Unhealthy' }
        [pscustomobject]@{ Name = $name; Manifest = $manifest; State = $state }
    }
}

try {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 15063) { Exit-Script 0 'NotApplicable | OS=Unsupported' }
    New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $states = @(Get-WamState)
    $summary = ($states | ForEach-Object { '{0}={1}' -f $_.Name, $_.State }) -join '; '
    if (@($states | Where-Object { $_.State -ne 'OK' }).Count -gt 0) { Exit-Script 1 "Drift | $summary" }
    if ($ForceReregister) { Exit-Script 1 "Drift | Reason=RequestedReregister; $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Error: Failed | HResult={0}; Action=ReviewAppxDeploymentLogs' -f $_.Exception.HResult) }
