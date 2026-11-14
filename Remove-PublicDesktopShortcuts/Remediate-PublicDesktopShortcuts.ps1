<#
.SYNOPSIS
  Remediation script for unwanted shortcuts on the Public Desktop.

.DESCRIPTION
  Deletes the .lnk and .url files on the Public Desktop whose names match the list, including read-only ones. Exits 0 if none are left, 1 if a file could not be removed.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ShortcutNames = @('Microsoft Edge', 'Google Chrome', 'Firefox', 'Zoom*', 'Adobe Acrobat*', 'VLC media player')

$PackageName = 'PublicDesktopShortcuts'
$Phase       = 'Remediate'
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

    $removed = @()
    foreach ($file in @(Get-UnwantedShortcut)) {
        try {
            if ($file.IsReadOnly) { $file.IsReadOnly = $false }
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removed += $file.Name
            Write-IRTLog "Removed $($file.FullName)"
        }
        catch { Write-IRTLog "Could not remove $($file.FullName): $($_.Exception.Message)" 'WARN' }
    }

    $left = @(Get-UnwantedShortcut)
    $summary = 'Removed={0}; Left={1}' -f $removed.Count, $left.Count
    if ($left.Count -eq 0) { Exit-Script 0 "Remediated | $summary; Shortcuts=$($removed -join ',')" }
    Exit-Script 1 "Failed | $summary; Shortcuts=$($left.Name -join ',')"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
