<#
.SYNOPSIS
  Remediation script for corporate Microsoft Teams meeting backgrounds.

.DESCRIPTION
  Copies the company background images staged in ProgramData into the new Teams Uploads folder of the signed-in user. Only files with the configured prefix are written, so personal uploads are left alone. Exits 0 after the copies are verified, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$SourceFolder       = Join-Path $env:ProgramData 'Company\TeamsBackgrounds'
$TargetPrefix       = 'Corp-'
$ImageExtensions    = @('.jpg', '.jpeg', '.png')
$IncludeClassic     = $false
$EnableRemediation  = $true
$TeamsUploads       = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Backgrounds\Uploads'
$ClassicUploads     = Join-Path $env:APPDATA 'Microsoft\Teams\Backgrounds\Uploads'

$PackageName = 'TeamsCustomBackgrounds'
$Phase       = 'Remediate'
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
            $state += [pscustomobject]@{ Name = $targetName; State = 'Missing'; SourcePath = $file.FullName }
            continue
        }
        $targetLength = (Get-Item -LiteralPath $targetFile -ErrorAction SilentlyContinue).Length
        if ($targetLength -ne $file.Length) {
            $state += [pscustomobject]@{ Name = $targetName; State = 'Stale'; SourcePath = $file.FullName }
        }
        else {
            $state += [pscustomobject]@{ Name = $targetName; State = 'OK'; SourcePath = $file.FullName }
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

    if (-not $EnableRemediation) {
        Exit-Script 0 ('ReportOnly | EnableRemediation=False; SourceImages={0}' -f $sourceImages.Count)
    }

    $targets = @()
    $targets += [pscustomobject]@{ Type = 'NewTeams'; Path = $TeamsUploads }
    if ($IncludeClassic) { $targets += [pscustomobject]@{ Type = 'ClassicTeams'; Path = $ClassicUploads } }

    $copied = 0
    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target.Path)) {
            New-Item -ItemType Directory -Path $target.Path -Force -ErrorAction Stop | Out-Null
        }
        foreach ($item in Get-BackgroundState -TargetPath $target.Path) {
            if ($item.State -eq 'OK') { continue }
            Copy-Item -LiteralPath $item.SourcePath -Destination (Join-Path $target.Path $item.Name) -Force -ErrorAction Stop
            $copied++
            Write-IRTLog "Copied $($item.Name) to $($target.Type)"
        }
    }

    $remaining = @()
    foreach ($target in $targets) {
        $remaining += @(Get-BackgroundState -TargetPath $target.Path | Where-Object { $_.State -ne 'OK' })
    }

    $summary = 'Copied={0}; Remaining={1}; Source={2}' -f $copied, $remaining.Count, $sourceImages.Count
    if ($remaining.Count -gt 0) {
        $names = (@($remaining | ForEach-Object { $_.Name } | Select-Object -First 5) -join ',')
        Exit-Script 1 "Failed | $summary; Files=$names"
    }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
