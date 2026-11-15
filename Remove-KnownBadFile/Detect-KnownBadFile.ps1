<#
.SYNOPSIS
  Detection script for known-bad files left behind in fixed folders.

.DESCRIPTION
  Scans every entry in $Targets for files that match the name pattern and the optional SHA256 hash. Exits 1 if at least one match is found, 0 when every target is clean or not present.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$Targets = @()
$MaxFilesInOutput = 5

$PackageName = 'KnownBadFile'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-TargetFile {
    foreach ($target in $Targets) {
        if (-not $target.Path -or -not [System.IO.Path]::IsPathRooted([string]$target.Path)) { continue }
        if (-not $target.Pattern -and -not $target.Hash) { continue }
        if (-not (Test-Path -LiteralPath $target.Path -PathType Container)) { continue }

        foreach ($file in @(Get-ChildItem -LiteralPath $target.Path -File -ErrorAction SilentlyContinue)) {
            if ($target.Pattern -and $file.Name -notlike $target.Pattern) { continue }
            if ($target.Hash) {
                try { $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash }
                catch { continue }
                if ($hash -ne $target.Hash) { continue }
            }
            [pscustomobject]@{
                Name     = $file.Name
                FullName = $file.FullName
                Folder   = $target.Path
                SizeKB   = [int][math]::Round($file.Length / 1KB)
            }
        }
    }
}

try {
    $present = @($Targets | Where-Object { $_.Path -and (Test-Path -LiteralPath $_.Path -PathType Container) })
    if ($present.Count -eq 0) {
        Exit-Script 0 "NotApplicable | Targets=$($Targets.Count); Present=0"
    }

    $files = @(Get-TargetFile)
    if ($files.Count -eq 0) {
        Exit-Script 0 "Healthy | Targets=$($present.Count); Matches=0"
    }

    $sample = (($files | Sort-Object Name | Select-Object -First $MaxFilesInOutput | ForEach-Object { $_.Name }) -join ',')
    $folders = (($files | Select-Object -ExpandProperty Folder -Unique | Select-Object -First $MaxFilesInOutput) -join ';')
    Exit-Script 1 "Drift | Targets=$($present.Count); Matches=$($files.Count); Files=$sample; Folders=$folders"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
