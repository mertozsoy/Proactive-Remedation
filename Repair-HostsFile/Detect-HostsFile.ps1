<#
.SYNOPSIS
  Detection script for hosts file entries outside the approved baseline.

.DESCRIPTION
  Reads the local hosts file and compares active entries with the approved list. Exits 1 when the file is missing, an entry is not approved or an approved entry is missing. Exits 0 when the file matches the baseline.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedEntries = @()

$PackageName = 'HostsFile'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = ($Summary -replace '[\r\n]+', ' ').Trim()
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

$HostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'

function ConvertTo-HostsEntry { param([string]$Line)
    $text = $Line
    $hashIndex = $text.IndexOf('#')
    if ($hashIndex -ge 0) { $text = $text.Substring(0, $hashIndex) }
    $text = $text.Trim()
    if ($text.Length -eq 0) { return $null }
    return ($text -replace '\s+', ' ')
}

function Get-HostsInventory { param([string]$Path)
    $entries = @()
    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $value = ConvertTo-HostsEntry -Line $line
        if ($null -ne $value) { $entries += $value }
    }
    $entries
}

function Test-ApprovedEntry { param([string]$Entry, [string[]]$Approved)
    foreach ($item in $Approved) {
        $normalized = ($item -replace '\s+', ' ').Trim()
        if ($normalized.Length -gt 0 -and $Entry -ieq $normalized) { return $true }
    }
    return $false
}

function Test-LoopbackEntry { param([string]$Entry)
    $parts = $Entry -split ' '
    if ($parts.Count -lt 2) { return $false }
    if ($parts[0] -ne '127.0.0.1' -and $parts[0] -ne '::1') { return $false }
    for ($i = 1; $i -lt $parts.Count; $i++) {
        if ($parts[$i] -ieq 'localhost') { return $true }
    }
    return $false
}

try {
    if (-not (Test-Path -LiteralPath $HostsPath)) { Exit-Script 1 'Drift | Count=1; Entries=hosts file missing' }

    $entries = @(Get-HostsInventory -Path $HostsPath)
    $unapproved = @()
    foreach ($entry in $entries) {
        if (Test-ApprovedEntry -Entry $entry -Approved $ApprovedEntries) { continue }
        if (Test-LoopbackEntry -Entry $entry) { continue }
        $unapproved += $entry
    }

    $missing = @()
    foreach ($approved in $ApprovedEntries) {
        $normalized = ($approved -replace '\s+', ' ').Trim()
        if ($normalized.Length -eq 0) { continue }
        $found = $false
        foreach ($entry in $entries) {
            if ($entry -ieq $normalized) { $found = $true; break }
        }
        if (-not $found) { $missing += $normalized }
    }

    if ($unapproved.Count -eq 0 -and $missing.Count -eq 0) {
        Exit-Script 0 "Healthy | Entries=$($entries.Count); Baseline=approved"
    }

    $detail = @()
    if ($unapproved.Count -gt 0) { $detail += ('Unapproved=' + ($unapproved -join '|')) }
    if ($missing.Count -gt 0) { $detail += ('Missing=' + ($missing -join '|')) }
    Exit-Script 1 ("Drift | Count={0}; {1}" -f ($unapproved.Count + $missing.Count), ($detail -join '; '))
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
