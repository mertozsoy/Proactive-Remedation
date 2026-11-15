<#
.SYNOPSIS
  Detection script for inbox Store apps that are installed but do not open.

.DESCRIPTION
  Checks the package status and package files of Photos, Snipping Tool, Calculator and Notepad for the signed-in user. Exits 1 if an installed app is unhealthy or its package files are missing, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$TargetApps = @(
    @{ Name = 'Microsoft.Windows.Photos'; Family = 'Microsoft.Windows.Photos_8wekyb3d8bbwe'; Label = 'Photos' }
    @{ Name = 'Microsoft.ScreenSketch'; Family = 'Microsoft.ScreenSketch_8wekyb3d8bbwe'; Label = 'SnippingTool' }
    @{ Name = 'Microsoft.WindowsCalculator'; Family = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe'; Label = 'Calculator' }
    @{ Name = 'Microsoft.WindowsNotepad'; Family = 'Microsoft.WindowsNotepad_8wekyb3d8bbwe'; Label = 'Notepad' }
)

$PackageName = 'BrokenInboxApps'
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

try {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 15063) { Exit-Script 0 'NotApplicable | OS=Unsupported' }
    New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null

    $apps = @(Get-InboxAppState)
    $broken = @($apps | Where-Object { $_.State -ne 'Ok' -and $_.State -ne 'NotRegistered' })
    $skipped = @($apps | Where-Object { $_.State -eq 'NotRegistered' })
    $brokenText = if ($broken.Count -gt 0) { ($broken | ForEach-Object { '{0}({1})' -f $_.Label, $_.State }) -join ',' } else { 'None' }
    $skippedText = if ($skipped.Count -gt 0) { ($skipped | ForEach-Object { '{0}(NotRegistered)' -f $_.Label }) -join ',' } else { 'None' }
    $summary = 'Broken={0}; Skipped={1}' -f $brokenText, $skippedText

    if ($broken.Count -gt 0) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | Apps=$($apps.Count); $summary"
}
catch { Exit-Script 1 ('Error: Failed | HResult={0}; Action=ReviewAppxDeploymentLogs' -f $_.Exception.HResult) }
