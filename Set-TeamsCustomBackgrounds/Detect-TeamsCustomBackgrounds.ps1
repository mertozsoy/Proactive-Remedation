<#
.SYNOPSIS
  Detection script for corporate Microsoft Teams meeting backgrounds.

.DESCRIPTION
  Compares the company background images staged in ProgramData with the copies in the new Teams Uploads folder of the signed-in user. Exits 1 if an image is missing or differs in size, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$SourceFolder    = Join-Path $env:ProgramData 'Company\TeamsBackgrounds'
$TargetPrefix    = 'Corp-'
$ImageExtensions = @('.jpg', '.jpeg', '.png')
$IncludeClassic  = $false
$TeamsUploads    = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Backgrounds\Uploads'
$ClassicUploads  = Join-Path $env:APPDATA 'Microsoft\Teams\Backgrounds\Uploads'

$PackageName = 'TeamsCustomBackgrounds'
$Phase       = 'Detect'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-TeamsImage {
    param([string]$SourcePath)
    $result = @()
    if (-not (Test-Path -LiteralPath $SourcePath)) { return $result }
    foreach ($file in Get-ChildItem -LiteralPath $SourcePath -File -ErrorAction SilentlyContinue) {
        if ($ImageExtensions -contains $file.Extension.ToLower()) { $result += $file }
    }
    return $result
}

function Get-BackgroundState {
    param([string]$TargetPath)
    $state = @()
    foreach ($file in Get-TeamsImage -SourcePath $SourceFolder) {
        $targetName = $TargetPrefix + $file.Name
        $targetFile = Join-Path $TargetPath $targetName
        if (-not (Test-Path -LiteralPath $targetFile)) {
            $state += [pscustomobject]@{ Name = $targetName; State = 'Missing' }
            continue
        }
        $targetLength = (Get-Item -LiteralPath $targetFile -ErrorAction SilentlyContinue).Length
        if ($targetLength -ne $file.Length) {
            $state += [pscustomobject]@{ Name = $targetName; State = 'Stale' }
        }
        else {
            $state += [pscustomobject]@{ Name = $targetName; State = 'OK' }
        }
    }
    return $state
}

try {
    if (-not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe'))) {
        Exit-Script 0 'NotApplicable | NewTeams=NotInstalled'
    }

    $sourceImages = @(Get-TeamsImage -SourcePath $SourceFolder)
    if ($sourceImages.Count -eq 0) {
        Exit-Script 0 'NotApplicable | SourceImages=None'
    }

    $targets = @()
    $targets += [pscustomobject]@{ Type = 'NewTeams'; Path = $TeamsUploads }
    if ($IncludeClassic) { $targets += [pscustomobject]@{ Type = 'ClassicTeams'; Path = $ClassicUploads } }

    $states = @()
    foreach ($target in $targets) {
        foreach ($item in Get-BackgroundState -TargetPath $target.Path) {
            $states += [pscustomobject]@{ Type = $target.Type; Name = $item.Name; State = $item.State }
        }
    }

    $missing = @($states | Where-Object { $_.State -ne 'OK' })
    $missingCount = @($states | Where-Object { $_.State -eq 'Missing' }).Count
    $staleCount = @($states | Where-Object { $_.State -eq 'Stale' }).Count
    $summary = 'Missing={0}; Stale={1}; Expected={2}; Source={3}' -f $missingCount, $staleCount, $states.Count, $sourceImages.Count

    if ($missing.Count -gt 0) {
        $names = (@($missing | ForEach-Object { $_.Name } | Select-Object -First 5) -join ',')
        Exit-Script 1 "Drift | $summary; Files=$names"
    }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
