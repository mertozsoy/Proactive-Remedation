<#
.SYNOPSIS
  Remediation script that restores the local hosts file to the approved baseline.

.DESCRIPTION
  Backs up the current hosts file, removes every active entry that is not approved, re-adds missing approved entries and verifies the result. Exits 0 when the file matches the baseline, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedEntries    = @()
$EnableRemediation  = $false
$BackupFolder       = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'HostsFile'
$Phase       = 'Remediate'
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
$HeaderLines = @(
    '# Hosts file baseline'
    '# Managed by Intune. Local additions are removed.'
    ''
)

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

function Get-UnapprovedEntry { param([string[]]$Entries)
    $result = @()
    foreach ($entry in $Entries) {
        if (Test-ApprovedEntry -Entry $entry -Approved $ApprovedEntries) { continue }
        if (Test-LoopbackEntry -Entry $entry) { continue }
        $result += $entry
    }
    $result
}

function Get-MissingEntry { param([string[]]$Entries)
    $result = @()
    foreach ($approved in $ApprovedEntries) {
        $normalized = ($approved -replace '\s+', ' ').Trim()
        if ($normalized.Length -eq 0) { continue }
        $found = $false
        foreach ($entry in $Entries) {
            if ($entry -ieq $normalized) { $found = $true; break }
        }
        if (-not $found) { $result += $normalized }
    }
    $result
}

try {
    $entries = @()
    if (Test-Path -LiteralPath $HostsPath) { $entries = @(Get-HostsInventory -Path $HostsPath) }
    $unapproved = @(Get-UnapprovedEntry -Entries $entries)
    $missing = @(Get-MissingEntry -Entries $entries)
    $driftCount = $unapproved.Count + $missing.Count

    if ($driftCount -eq 0 -and (Test-Path -LiteralPath $HostsPath)) {
        Exit-Script 0 "Healthy | Entries=$($entries.Count); Baseline=approved"
    }

    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | Unapproved=$($unapproved.Count); Missing=$($missing.Count); Action=enable remediation"
    }

    if (-not (Test-Path -LiteralPath $BackupFolder)) {
        New-Item -ItemType Directory -Path $BackupFolder -Force -ErrorAction Stop | Out-Null
    }
    $backupPath = $null
    if (Test-Path -LiteralPath $HostsPath) {
        $backupName = 'hosts_{0}.bak' -f (Get-Date -Format 'yyyyMMdd_HHmmss')
        $backupPath = Join-Path $BackupFolder $backupName
        Copy-Item -LiteralPath $HostsPath -Destination $backupPath -Force -ErrorAction Stop
        Write-IRTLog "Backup written: $backupName"
    }

    $kept = @()
    foreach ($entry in $entries) {
        if (Test-LoopbackEntry -Entry $entry) {
            if ($kept -notcontains $entry) { $kept += $entry }
        }
    }

    $content = @()
    $content += $HeaderLines
    foreach ($entry in $kept) { $content += $entry }
    foreach ($approved in $ApprovedEntries) {
        $normalized = ($approved -replace '\s+', ' ').Trim()
        if ($normalized.Length -eq 0) { continue }
        if ($content -notcontains $normalized) { $content += $normalized }
    }

    if (Test-Path -LiteralPath $HostsPath) {
        $hostsItem = Get-Item -LiteralPath $HostsPath -Force -ErrorAction Stop
        if ($hostsItem.IsReadOnly) {
            $hostsItem.IsReadOnly = $false
            Write-IRTLog 'Read-only attribute cleared on the hosts file'
        }
    }

    $tempPath = Join-Path (Split-Path -Parent $HostsPath) 'hosts.irt.tmp'
    Set-Content -LiteralPath $tempPath -Value $content -Encoding ASCII -ErrorAction Stop
    Copy-Item -LiteralPath $tempPath -Destination $HostsPath -Force -ErrorAction Stop
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction Stop
    Write-IRTLog "Hosts file rewritten with $($kept.Count) loopback and $($ApprovedEntries.Count) approved entries"

    $after = @(Get-HostsInventory -Path $HostsPath)
    $remaining = @(Get-UnapprovedEntry -Entries $after)
    $stillMissing = @(Get-MissingEntry -Entries $after)
    if ($remaining.Count -gt 0 -or $stillMissing.Count -gt 0) {
        Exit-Script 1 "Failed | Remaining=$($remaining.Count); Missing=$($stillMissing.Count); Action=ReviewHostsPermissions"
    }

    $backupLabel = 'none'
    if ($null -ne $backupPath) { $backupLabel = Split-Path -Leaf $backupPath }
    Exit-Script 0 "Fixed | Removed=$($unapproved.Count); Added=$($missing.Count); Kept=$($kept.Count); Backup=$backupLabel"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
