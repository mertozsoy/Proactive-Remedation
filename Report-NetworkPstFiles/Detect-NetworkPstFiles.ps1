<#
.SYNOPSIS
  Detection script for Outlook PST files stored on network shares.

.DESCRIPTION
  Scans the configured UNC share roots and the mapped network drives of the signed-in user for .pst files. Reports the file count, total size, the largest file and stale files. Exits 1 if at least one PST file is found on a network share, 0 otherwise. Report only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ShareRoots          = @()
$IncludeMappedDrives = $true
$MaxDepth            = 3
$MaxFolders          = 3000
$MaxListedFiles      = 5
$StaleDays           = 180
$ShowFullPaths       = $false
$SmbTimeoutMs        = 3000
$SkipFolderNames     = @('$RECYCLE.BIN', 'System Volume Information', '~snapshot')

$PackageName = 'NetworkPstFiles'
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

function Test-SmbPort { param([string]$Server)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect($Server, 445, $null, $null)
        return ($pending.AsyncWaitHandle.WaitOne($SmbTimeoutMs) -and $client.Connected)
    }
    catch { return $false }
    finally { $client.Close() }
}

function Get-ShareRoot {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $ShareRoots) {
        $value = "$entry".Trim().TrimEnd('\')
        if ($value -like '\\*\*' -and -not $roots.Contains($value)) { $roots.Add($value) }
    }
    if (-not $IncludeMappedDrives) { return $roots }

    $drives = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=4' -ErrorAction SilentlyContinue)
    foreach ($drive in $drives) {
        $value = "$($drive.ProviderName)".Trim().TrimEnd('\')
        if ($value -like '\\*\*' -and -not $roots.Contains($value)) { $roots.Add($value) }
    }
    $saved = @(Get-ItemProperty -Path 'HKCU:\Network\*' -ErrorAction SilentlyContinue)
    foreach ($map in $saved) {
        $value = "$($map.RemotePath)".Trim().TrimEnd('\')
        if ($value -like '\\*\*' -and -not $roots.Contains($value)) { $roots.Add($value) }
    }
    return $roots
}

function Get-PstFile {
    param([string]$Root)
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue([pscustomobject]@{ Path = $Root; Depth = 0 })
    while ($queue.Count -gt 0) {
        if ($script:FolderCount -ge $MaxFolders) { $script:Truncated = $true; break }
        $current = $queue.Dequeue()
        $script:FolderCount++
        try { $entries = @(Get-ChildItem -LiteralPath $current.Path -Force -ErrorAction Stop) }
        catch { Write-IRTLog "Skip $($current.Path): $($_.Exception.Message)" -Level 'WARN'; continue }
        foreach ($entry in $entries) {
            if ($entry.PSIsContainer) {
                if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if ($SkipFolderNames -contains $entry.Name) { continue }
                if ($current.Depth -lt $MaxDepth) { $queue.Enqueue([pscustomobject]@{ Path = $entry.FullName; Depth = $current.Depth + 1 }) }
                continue
            }
            if ($entry.Extension -ne '.pst') { continue }
            [pscustomobject]@{
                Path     = $entry.FullName
                Name     = $entry.Name
                SizeMB   = [math]::Round($entry.Length / 1MB)
                Modified = $entry.LastWriteTime
            }
        }
    }
}

$script:FolderCount = 0
$script:Truncated   = $false

try {
    $roots = @(Get-ShareRoot)
    if ($roots.Count -eq 0) { Exit-Script 0 'NotApplicable | NoShareRoots' }

    $files   = New-Object System.Collections.Generic.List[object]
    $scanned = 0
    $offline = 0
    foreach ($root in $roots) {
        $server = ([uri]$root).Host
        if ($server -and -not (Test-SmbPort -Server $server)) { Write-IRTLog "Unreachable $root" -Level 'WARN'; $offline++; continue }
        $scanned++
        foreach ($file in @(Get-PstFile -Root $root)) { $files.Add($file) }
        Write-IRTLog ('Scanned {0} | Files={1} | Folders={2}' -f $root, $files.Count, $script:FolderCount)
    }

    if ($scanned -eq 0) { Exit-Script 0 "NotApplicable | SharesOffline=$offline" }

    $folders = $script:FolderCount
    $truncated = if ($script:Truncated) { 'Yes' } else { 'No' }
    if ($files.Count -eq 0) {
        Exit-Script 0 ('None | Shares={0}; Offline={1}; Folders={2}; PstFiles=0; Truncated={3}' -f $scanned, $offline, $folders, $truncated)
    }

    foreach ($file in ($files | Sort-Object SizeMB -Descending)) {
        Write-IRTLog ('PST {0} | {1} MB | {2:yyyy-MM-dd}' -f $file.Path, $file.SizeMB, $file.Modified)
    }

    $totalMB = [math]::Round((($files | Measure-Object -Property SizeMB -Sum).Sum), 0)
    $stale   = 0
    if ($StaleDays -gt 0) {
        $limit = (Get-Date).AddDays(-$StaleDays)
        $stale = @($files | Where-Object { $_.Modified -lt $limit }).Count
    }

    $listed = @($files | Sort-Object SizeMB -Descending | Select-Object -First $MaxListedFiles)
    $items  = @()
    foreach ($file in $listed) {
        if ($ShowFullPaths) { $items += ('{0}({1}MB)' -f $file.Path, $file.SizeMB) }
        else { $items += ('{0}({1}MB)' -f $file.Name, $file.SizeMB) }
    }
    $more = [math]::Max(0, $files.Count - $MaxListedFiles)
    $itemText = if ($items.Count -gt 0) { $items -join ',' } else { 'None' }
    if ($more -gt 0) { $itemText += ",+$more" }

    $summary = 'Shares={0}; Offline={1}; Folders={2}; PstFiles={3}; TotalMB={4}; Stale={5}; Truncated={6}; Files={7}' -f $scanned, $offline, $folders, $files.Count, $totalMB, $stale, $truncated, $itemText
    Exit-Script 1 "PstOnShare ($($files.Count)) | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
