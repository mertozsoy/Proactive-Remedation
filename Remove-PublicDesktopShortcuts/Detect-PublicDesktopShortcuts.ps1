<#
.SYNOPSIS
  Detection script for unwanted shortcuts on the Public Desktop.

.DESCRIPTION
  Looks for .lnk and .url files on the Public Desktop whose names match the list. Exits 1 if a match is found, 0 if the Public Desktop is clean.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ShortcutNames = @('Microsoft Edge', 'Google Chrome', 'Firefox', 'Zoom*', 'Adobe Acrobat*', 'VLC media player')

$PackageName = 'PublicDesktopShortcuts'
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

function Get-UnwantedShortcut {
    $desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) { return @() }
    $files = Get-ChildItem -LiteralPath $desktop -File -Force -ErrorAction Stop | Where-Object { $_.Extension -in '.lnk', '.url' }
    foreach ($file in $files) {
        foreach ($pattern in $ShortcutNames) {
            if ($file.BaseName -like $pattern) { $file; break }
        }
    }
}

try {
    if (-not $ShortcutNames -or $ShortcutNames.Count -eq 0) { Exit-Script 0 'NotApplicable | ShortcutNames=None' }

    $found = @(Get-UnwantedShortcut)
    if ($found.Count -gt 0) { Exit-Script 1 "Found | Count=$($found.Count); Shortcuts=$($found.Name -join ',')" }
    Exit-Script 0 'Clean | Count=0'
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
