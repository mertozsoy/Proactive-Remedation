<#
.SYNOPSIS
  Remediation script that re-registers inbox Store apps that are installed but do not open.

.DESCRIPTION
  Re-registers Photos, Snipping Tool, Calculator and Notepad from the package manifest for the signed-in user and checks the result. Optional app data reset is off by default. Exits 0 if every broken app is healthy again, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ResetAppData = $false
$TargetApps = @(
    @{ Name = 'Microsoft.Windows.Photos'; Family = 'Microsoft.Windows.Photos_8wekyb3d8bbwe'; Label = 'Photos' }
    @{ Name = 'Microsoft.ScreenSketch'; Family = 'Microsoft.ScreenSketch_8wekyb3d8bbwe'; Label = 'SnippingTool' }
    @{ Name = 'Microsoft.WindowsCalculator'; Family = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe'; Label = 'Calculator' }
    @{ Name = 'Microsoft.WindowsNotepad'; Family = 'Microsoft.WindowsNotepad_8wekyb3d8bbwe'; Label = 'Notepad' }
)

$PackageName = 'BrokenInboxApps'
$Phase = 'Remediate'
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
function Get-InboxAppState {
    foreach ($app in $TargetApps) {
        $packages = @(Get-AppxPackage -Name $app.Name -ErrorAction Stop | Where-Object { $_.PackageFamilyName -eq $app.Family })
        $state = 'Ok'
        $fullName = ''
        $location = ''
        if ($packages.Count -eq 0) { $state = 'NotRegistered' }
        elseif ($packages.Count -gt 1) { $state = 'MultipleVersions' }
        else {
            $pkg = $packages[0]
            $fullName = [string]$pkg.PackageFullName
            $location = [string]$pkg.InstallLocation
            if ([string]$pkg.Status -ne 'Ok') { $state = 'Status' + [string]$pkg.Status }
            elseif ([string]::IsNullOrWhiteSpace($location)) { $state = 'NoInstallLocation' }
            else {
                try { $null = Get-AppxPackageManifest -Package $fullName -ErrorAction Stop }
                catch { $state = 'ManifestUnreadable' }
            }
        }
        [pscustomobject]@{ Label = $app.Label; Family = $app.Family; State = $state; FullName = $fullName; Location = $location }
    }
}
function Invoke-AppRepair { param($App)
    $actions = @()
    if ($ResetAppData -and -not [string]::IsNullOrWhiteSpace($App.FullName)) {
        Reset-AppxPackage -Package $App.FullName -ErrorAction Stop
        $actions += 'Reset'
        Write-IRTLog "Reset app data for $($App.Label)"
    }
    $manifest = ''
    if (-not [string]::IsNullOrWhiteSpace($App.Location)) { $manifest = Join-Path $App.Location 'AppxManifest.xml' }
    $registered = $false
    if ($manifest -and (Test-Path -LiteralPath $manifest -PathType Leaf -ErrorAction SilentlyContinue)) {
        try {
            Add-AppxPackage -Path $manifest -Register -DisableDevelopmentMode -ErrorAction Stop
            $actions += 'Register'
            $registered = $true
        }
        catch {
            Write-IRTLog "Register from manifest failed for $($App.Label): $($_.Exception.Message)" 'WARN'
        }
    }
    if (-not $registered) {
        Add-AppxPackage -MainPackage $App.Family -RegisterByFamilyName -ErrorAction Stop
        $actions += 'RegisterByFamily'
    }
    Write-IRTLog "Repaired $($App.Label) with $($actions -join '+')"
    return ($actions -join '+')
}

try {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 15063) { Exit-Script 0 'NotApplicable | OS=Unsupported' }
    New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null

    $broken = @(Get-InboxAppState | Where-Object { $_.State -ne 'Ok' -and $_.State -ne 'NotRegistered' })
    if ($broken.Count -eq 0) { Exit-Script 0 'Healthy | Broken=None; Action=None' }

    $fixed = @()
    $failed = @()
    $methods = @()
    foreach ($app in $broken) {
        try {
            $method = Invoke-AppRepair -App $app
            $methods += ('{0}:{1}' -f $app.Label, $method)
            $fixed += $app.Label
        }
        catch {
            Write-IRTLog "Repair failed for $($app.Label): $($_.Exception.Message)" 'ERROR'
            $failed += $app.Label
        }
    }

    $after = @(Get-InboxAppState)
    $left = @($after | Where-Object { $_.State -ne 'Ok' -and $_.State -ne 'NotRegistered' })
    if ($left.Count -gt 0) {
        $leftText = ($left | ForEach-Object { '{0}({1})' -f $_.Label, $_.State }) -join ','
        Exit-Script 1 ('Failed | Remaining={0}; Actions={1}' -f $leftText, ($methods -join ','))
    }
    Exit-Script 0 ('Fixed | Apps={0}; Actions={1}; Verified=Ok' -f (($fixed -join ',')), ($methods -join ','))
}
catch { Exit-Script 1 ('Error: Failed | HResult={0}; Action=ReviewAppxDeploymentLogs' -f $_.Exception.HResult) }
