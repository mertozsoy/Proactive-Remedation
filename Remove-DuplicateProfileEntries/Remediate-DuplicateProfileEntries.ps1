<#
.SYNOPSIS
  Remediation script for explicitly approved duplicate ProfileList entries.

.DESCRIPTION
  With approval enabled, exports ProfileList and removes selected duplicate keys
  only when a retained plain SID key uses the same existing local profile path.
  Loaded, special, roaming and unhealthy profiles are protected. No profile files
  are deleted. Exits 0 only when no findings remain, 1 for unresolved findings or errors.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $false
$ApprovedRepairs = @()
$ProfileListRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$BackupDirectory = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'DuplicateProfileEntries'
$Phase = 'Remediate'
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
function Test-RepairSafety { param([object]$RemoveEntry, [object]$KeepEntry, [object[]]$Entries)
    if ($RemoveEntry.Name -eq $KeepEntry.Name -or $KeepEntry.Backup) { return $false }
    if (-not $RemoveEntry.Path -or $RemoveEntry.Path -ne $KeepEntry.Path) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $KeepEntry.Path 'NTUSER.DAT') -PathType Leaf -ErrorAction Stop)) { return $false }
    $directory = Get-Item -LiteralPath $KeepEntry.Path -Force -ErrorAction Stop
    if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    $related = @($Entries | Where-Object { $_.Path -eq $KeepEntry.Path -or $_.Sid -eq $RemoveEntry.Sid -or $_.Sid -eq $KeepEntry.Sid })
    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop)
    $keeper = @($profiles | Where-Object { $_.SID -eq $KeepEntry.Sid -and (ConvertTo-ProfilePath -Value $_.LocalPath) -eq $KeepEntry.Path })
    if ($keeper.Count -ne 1) { return $false }
    foreach ($profileInfo in $profiles) {
        $path = ConvertTo-ProfilePath -Value $profileInfo.LocalPath
        if ($profileInfo.SID -in $related.Sid -or ($path -and $path -eq $KeepEntry.Path)) {
            if ($profileInfo.Loaded -ne $false -or $profileInfo.Special -ne $false -or $profileInfo.RoamingConfigured -ne $false -or $null -eq $profileInfo.Status -or $profileInfo.Status -ne 0) { return $false }
        }
    }
    foreach ($entry in $related) {
        foreach ($hive in @($entry.Sid, ($entry.Sid + '_Classes'))) {
            if (Test-Path -LiteralPath "Registry::HKEY_USERS\$hive" -ErrorAction Stop) { return $false }
        }
    }
    return $true
}
try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if (-not (Test-Path -LiteralPath $ProfileListRoot -ErrorAction Stop)) { Exit-Script 0 'NotApplicable | ProfileList=Absent' }
    $entries = @(Get-ProfileEntry)
    $findings = @(Get-ProfileFinding -Entries $entries)
    if ($findings.Count -eq 0) { Exit-Script 0 'Healthy | Findings=0; Removed=0' }
    if (-not $EnableRemediation) { Exit-Script 1 "Blocked | Findings=$($findings.Count); Reason=ApprovalDisabled; Removed=0" }
    if ($ApprovedRepairs.Count -eq 0) { Exit-Script 1 "Blocked | Findings=$($findings.Count); Reason=NoApprovedRepairs; Removed=0" }
    $removeNames = @($ApprovedRepairs | ForEach-Object { [string]$_.RemoveKey })
    $keepNames = @($ApprovedRepairs | ForEach-Object { [string]$_.KeepKey })
    if (@($removeNames | Sort-Object -Unique).Count -ne $removeNames.Count -or @($keepNames | Where-Object { $_ -in $removeNames }).Count -gt 0) {
        Exit-Script 1 'Failed | Reason=ConflictingApprovals; Removed=0'
    }
    $removed = 0
    $blocked = 0
    foreach ($repair in $ApprovedRepairs) {
        $entries = @(Get-ProfileEntry)
        $remove = @($entries | Where-Object Name -eq ([string]$repair.RemoveKey))
        $keep = @($entries | Where-Object Name -eq ([string]$repair.KeepKey))
        if ($remove.Count -eq 0) { continue }
        if ($keep.Count -ne 1 -or -not (Test-RepairSafety -RemoveEntry $remove[0] -KeepEntry $keep[0] -Entries $entries)) { $blocked++; continue }
        if (@(Get-Process -Name 'setup', 'setuphost', 'setupprep', 'systemreset' -ErrorAction SilentlyContinue).Count -gt 0) { $blocked++; continue }
        New-Item -ItemType Directory -Path $BackupDirectory -Force -ErrorAction Stop | Out-Null
        $backupFile = Join-Path $BackupDirectory ('ProfileList_{0}.reg' -f [guid]::NewGuid().ToString('N'))
        $nativeRoot = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        & "$env:windir\System32\reg.exe" export $nativeRoot $backupFile /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupFile -PathType Leaf -ErrorAction Stop)) { throw 'BackupFailed' }
        if ((Get-Item -LiteralPath $backupFile -ErrorAction Stop).Length -eq 0) { throw 'BackupEmpty' }
        $fresh = @(Get-ProfileEntry)
        $currentRemove = @($fresh | Where-Object Name -eq $remove[0].Name)
        $currentKeep = @($fresh | Where-Object Name -eq $keep[0].Name)
        if ($currentRemove.Count -ne 1 -or $currentKeep.Count -ne 1) { $blocked++; continue }
        if ($currentRemove[0].Path -ne $remove[0].Path -or $currentKeep[0].Path -ne $keep[0].Path) { $blocked++; continue }
        if (-not (Test-RepairSafety -RemoveEntry $currentRemove[0] -KeepEntry $currentKeep[0] -Entries $fresh)) { $blocked++; continue }
        $target = Join-Path $ProfileListRoot $currentRemove[0].Name
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $target -ErrorAction Stop) { throw 'RemovalNotVerified' }
        $verified = @(Get-ProfileEntry | Where-Object Name -eq $currentKeep[0].Name)
        if ($verified.Count -ne 1 -or $verified[0].Path -ne $currentKeep[0].Path) { throw 'RetainedEntryChanged' }
        $removed++
        Write-IRTLog "Approved duplicate removed; Removed=$removed"
    }
    $remaining = @(Get-ProfileFinding -Entries @(Get-ProfileEntry)).Count
    if ($remaining -gt 0 -or $blocked -gt 0) { Exit-Script 1 "Failed | Removed=$removed; Remaining=$remaining; Blocked=$blocked; Action=ManualReview" }
    Exit-Script 0 "Fixed | Removed=$removed; Remaining=0; Blocked=0"
}
catch { Exit-Script 1 "Error: Failed | Reason=RemediationFailed; Type=$($_.Exception.GetType().Name)" }
