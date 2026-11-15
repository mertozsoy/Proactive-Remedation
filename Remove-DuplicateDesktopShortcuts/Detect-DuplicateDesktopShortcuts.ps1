<#
.SYNOPSIS
  Detection script for duplicate desktop shortcuts.

.DESCRIPTION
  Scans the signed-in user's Desktop for copy shortcuts such as "Microsoft Edge - Copy" or "Teams (2)" where the original shortcut still exists in the same folder. Exits 1 if at least one duplicate is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$CopyMarkers    = @(' - Copy', ' - Kopya', ' - Kopie', ' - Copie', ' - Copia')
$ShortcutTypes  = @('.lnk', '.url')
$MaxListedNames = 10

$PackageName = 'DuplicateDesktopShortcuts'
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

function Get-OriginalCandidate { param([string]$BaseName)
    $candidates = @()
    $root = $BaseName
    if ($root -match '^(?<stem>.+) \((?<num>[2-9]|[1-9][0-9])\)$') {
        $root = $Matches['stem']
        $candidates += $root
    }
    foreach ($marker in $CopyMarkers) {
        if ($root.EndsWith($marker, [System.StringComparison]::OrdinalIgnoreCase)) {
            $stem = $root.Substring(0, $root.Length - $marker.Length).TrimEnd()
            if ($stem) { $candidates += $stem }
        }
    }
    return $candidates
}

function Get-DuplicateShortcut { param([string]$Desktop)
    $files = @(Get-ChildItem -LiteralPath $Desktop -File -Force -ErrorAction Stop | Where-Object { $ShortcutTypes -contains $_.Extension.ToLowerInvariant() })
    if ($files.Count -eq 0) { return @() }
    $index = @{}
    foreach ($file in $files) { $index[$file.Name.ToLowerInvariant()] = $true }
    foreach ($file in $files) {
        foreach ($stem in @(Get-OriginalCandidate -BaseName $file.BaseName)) {
            $original = '{0}{1}' -f $stem, $file.Extension
            if ($index.ContainsKey($original.ToLowerInvariant())) {
                [pscustomobject]@{ Name = $file.Name; Original = $original }
                break
            }
        }
    }
}

try {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) { Exit-Script 0 'NotApplicable | DesktopFolder=NotFound' }

    $duplicates = @(Get-DuplicateShortcut -Desktop $desktop)
    if ($duplicates.Count -eq 0) { Exit-Script 0 'Healthy | Duplicates=0' }

    $listed = @($duplicates | Select-Object -First $MaxListedNames | ForEach-Object { $_.Name })
    $names  = $listed -join ','
    if ($duplicates.Count -gt $listed.Count) { $names = '{0},+{1}more' -f $names, ($duplicates.Count - $listed.Count) }
    Exit-Script 1 ('Duplicates | Count={0}; Names={1}' -f $duplicates.Count, $names)
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
