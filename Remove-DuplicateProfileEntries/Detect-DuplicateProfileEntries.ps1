<#
.SYNOPSIS
  Detection script for duplicate ProfileList paths and SID backup entries.

.DESCRIPTION
  Reads user SID entries in ProfileList. Flags .bak entries and multiple keys using
  the same normalized ProfileImagePath. Exits 1 for findings or errors, 0 otherwise.
  Findings require investigation and do not prove an upgrade or reset blocker.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ProfileListRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

$PackageName = 'DuplicateProfileEntries'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function ConvertTo-ProfilePath { param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    if ($expanded -notmatch '^[A-Za-z]:\\' -or $expanded.Contains('%')) { return '' }
    return [IO.Path]::GetFullPath($expanded).TrimEnd('\').ToLowerInvariant()
}
function Get-ProfileEntry {
    foreach ($key in @(Get-ChildItem -LiteralPath $ProfileListRoot -ErrorAction Stop)) {
        $name = $key.PSChildName
        if ($name -notmatch '^(S-1-(?:5-21-\d+-\d+-\d+-\d+|12-1-\d+-\d+-\d+-\d+))(\.bak)?$') { continue }
        $sid = $Matches[1]
        $backup = $name.EndsWith('.bak', [StringComparison]::OrdinalIgnoreCase)
        $properties = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
        [pscustomobject]@{
            Name = $name
            Sid = $sid
            Backup = $backup
            Path = ConvertTo-ProfilePath -Value ([string]$properties.ProfileImagePath)
        }
    }
}
function Get-ProfileFinding { param([object[]]$Entries)
    foreach ($entry in $Entries) {
        $samePath = @($Entries | Where-Object { $entry.Path -and $_.Path -eq $entry.Path })
        if ($entry.Backup -or $samePath.Count -gt 1) { $entry }
    }
}
try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if (-not (Test-Path -LiteralPath $ProfileListRoot -ErrorAction Stop)) {
        Exit-Script 0 'NotApplicable | ProfileList=Absent'
    }
    $entries = @(Get-ProfileEntry)
    $findings = @(Get-ProfileFinding -Entries $entries)
    $backups = @($entries | Where-Object Backup).Count
    $groups = @($entries | Where-Object Path | Group-Object Path | Where-Object Count -gt 1).Count
    if ($findings.Count -eq 0) { Exit-Script 0 'Healthy | Findings=0; BackupKeys=0; DuplicatePaths=0' }
    Exit-Script 1 "Drift | Findings=$($findings.Count); BackupKeys=$backups; DuplicatePaths=$groups; Action=ReviewSetupLogs"
}
catch { Exit-Script 1 "Error: Failed | Reason=InspectionFailed; Type=$($_.Exception.GetType().Name)" }
