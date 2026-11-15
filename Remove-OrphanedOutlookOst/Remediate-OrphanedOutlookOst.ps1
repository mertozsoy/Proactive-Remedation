<#
.SYNOPSIS
  Remediation script for reviewed orphaned Outlook OST files.

.DESCRIPTION
  Removes only aged OST files approved by exact filename and SHA256 in the current
  user's default Outlook folder. RemoveFiles defaults to false. Approval requires
  checking every Outlook profile and preserving any data absent from the server.
  Exits 0 only after removal is verified and no aged review candidates remain.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$MinimumAgeDays = 30
$ApprovedOstFiles = @()
$RemoveFiles = $false

$PackageName = 'OrphanedOutlookOst'
$Phase = 'Remediate'
$LogFile = $null

function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    try {
        if ($LogFile) {
            $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
            Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
        }
    } catch { }
}

function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Test-OutlookRunning {
    $processes = @(Get-Process -ErrorAction Stop)
    return @($processes | Where-Object { $_.ProcessName -in @('OUTLOOK', 'olk', 'WINWORD') }).Count -gt 0
}

function Test-PlainPath { param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        if ($item -is [IO.FileInfo]) { $item = $item.Directory } else { $item = $item.Parent }
    }
    return $true
}

function Remove-ApprovedOst { param([IO.FileInfo]$File, [string]$ExpectedHash, [DateTime]$Cutoff)
    $stream = $null
    $algorithm = $null
    try {
        if (-not (Test-PlainPath -Path $File.FullName)) { return 'Blocked' }
        if (Test-OutlookRunning) { return 'Blocked' }
        $stream = [IO.File]::Open($File.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Delete)
        $algorithm = [Security.Cryptography.SHA256]::Create()
        $actualHash = [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '')
        if ($actualHash -ne $ExpectedHash) { return 'Changed' }
        $current = Get-Item -LiteralPath $File.FullName -Force -ErrorAction Stop
        if ($current.LastWriteTimeUtc -ge $Cutoff -or -not (Test-PlainPath -Path $File.FullName)) { return 'Blocked' }
        if (Test-OutlookRunning) { return 'Blocked' }
        Remove-Item -LiteralPath $File.FullName -ErrorAction Stop
    } finally {
        if ($null -ne $algorithm) { $algorithm.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
    if (Test-Path -LiteralPath $File.FullName) { return 'Blocked' }
    return 'Removed'
}

try {
    $ErrorActionPreference = 'Stop'
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { Exit-Script 1 'Failed | Reason=UserContextRequired' }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { Exit-Script 1 'Failed | Reason=LocalAppDataMissing' }
    $logDir = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
    New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
    $LogFile = Join-Path $logDir "IRT_$PackageName.log"
    if ($MinimumAgeDays -lt 1) { throw 'InvalidMinimumAge' }
    $seen = @{}
    foreach ($entry in $ApprovedOstFiles) {
        if ([string]::IsNullOrWhiteSpace($entry.Name) -or
            $entry.Name -ne [IO.Path]::GetFileName($entry.Name) -or
            $entry.Name -match '[:*?\\/]' -or
            [IO.Path]::GetExtension($entry.Name) -ne '.ost' -or
            $entry.SHA256 -notmatch '^[A-Fa-f0-9]{64}$' -or $seen.ContainsKey($entry.Name)) {
            throw 'InvalidApproval'
        }
        $seen[$entry.Name] = $true
    }
    $root = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { Exit-Script 0 'NotApplicable | Reason=OutlookFolderMissing' }
    if ($root.StartsWith('\\') -or -not (Test-PlainPath -Path $root)) { Exit-Script 1 'Failed | Reason=UnsupportedPath' }
    $cutoff = [DateTime]::UtcNow.AddDays(-$MinimumAgeDays)
    $files = @(Get-ChildItem -LiteralPath $root -Filter '*.ost' -File -Force -ErrorAction Stop |
        Where-Object { $_.LastWriteTimeUtc -lt $cutoff })
    if ($files.Count -eq 0) { Exit-Script 0 'Healthy | AgedOst=0' }
    if (-not $RemoveFiles) { Exit-Script 1 "ReportOnly | AgedOst=$($files.Count); Reason=RemoveFilesDisabled" }
    if (Test-OutlookRunning) { Exit-Script 1 "Deferred | AgedOst=$($files.Count); Reason=OutlookOrWordRunning" }
    $removed = 0
    $review = 0
    $changed = 0
    $blocked = 0
    [int64]$bytes = 0
    foreach ($file in $files) {
        $approval = @($ApprovedOstFiles | Where-Object { $_.Name -eq $file.Name })
        if ($approval.Count -eq 0) { $review++; continue }
        try {
            $state = Remove-ApprovedOst -File $file -ExpectedHash $approval[0].SHA256 -Cutoff $cutoff
            switch ($state) {
                'Removed' { $removed++; $bytes += $file.Length }
                'Changed' { $changed++ }
                default { $blocked++ }
            }
        } catch { $blocked++ }
    }
    $remaining = @(Get-ChildItem -LiteralPath $root -Filter '*.ost' -File -Force -ErrorAction Stop |
        Where-Object { $_.LastWriteTimeUtc -lt $cutoff }).Count
    $mib = [math]::Round($bytes / 1MB)
    $summary = "Removed=$removed; Remaining=$remaining; Review=$review; Changed=$changed; Blocked=$blocked; RemovedMiB=$mib"
    if ($remaining -gt 0 -or $blocked -gt 0 -or $changed -gt 0) { Exit-Script 1 "NeedsReview | $summary" }
    Exit-Script 0 "Fixed | $summary"
} catch { Exit-Script 1 "Error: Failed | Type=$($_.Exception.GetType().Name)" }
