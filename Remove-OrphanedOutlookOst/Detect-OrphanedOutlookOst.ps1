<#
.SYNOPSIS
  Detection script for reviewed orphaned Outlook OST files.

.DESCRIPTION
  Reports aged OST review candidates in the current user's default Outlook folder.
  Only an administrator-approved name and SHA256 pair is eligible for removal.
  Age and numbered filenames do not prove that a file is orphaned or duplicated.
  Exits 1 for aged files requiring review or removal, 0 when none are found.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$MinimumAgeDays = 30
$ApprovedOstFiles = @()
$RemoveFiles = $false

$PackageName = 'OrphanedOutlookOst'
$Phase = 'Detect'
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

function Get-OstState { param([IO.FileInfo]$File)
    if (-not (Test-PlainPath -Path $File.FullName)) { throw 'ReparsePoint' }
    $approval = @($ApprovedOstFiles | Where-Object { $_.Name -eq $File.Name })
    if ($approval.Count -eq 0) { return 'Review' }
    $hash = Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256 -ErrorAction Stop
    if ($hash.Hash -ne $approval[0].SHA256) { return 'Changed' }
    return 'Approved'
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
    if (Test-OutlookRunning) { Exit-Script 1 "Deferred | AgedOst=$($files.Count); Reason=OutlookOrWordRunning" }
    $approved = 0
    $review = 0
    $changed = 0
    $blocked = 0
    [int64]$bytes = 0
    foreach ($file in $files) {
        $bytes += $file.Length
        try {
            $state = Get-OstState -File $file
            switch ($state) {
                'Approved' { $approved++ }
                'Review' { $review++ }
                'Changed' { $changed++ }
            }
        } catch { $blocked++ }
    }
    $mib = [math]::Round($bytes / 1MB)
    Exit-Script 1 "Drift | AgedOst=$($files.Count); Approved=$approved; Review=$review; Changed=$changed; Blocked=$blocked; CandidateMiB=$mib"
} catch { Exit-Script 1 "Error: Failed | Type=$($_.Exception.GetType().Name)" }
