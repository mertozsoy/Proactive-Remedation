<#
.SYNOPSIS
  Remediation script that deletes known-bad files from fixed folders.

.DESCRIPTION
  Scans every entry in $Targets, copies each match to a backup folder, stops the configured services and deletes the files. The delete step is off by default and only runs when $EnableRemediation is set to $true. Exits 0 when no match is left, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $false
$Targets = @()
$StopService      = $true
$ServiceNames     = @('CSFalconService')
$BackupFiles      = $true
$BackupRoot       = Join-Path $env:ProgramData 'IntuneRemediations\Backup\KnownBadFile'
$MaxFilesInOutput = 5

$PackageName = 'KnownBadFile'
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

function Get-TargetFile {
    foreach ($target in $Targets) {
        if (-not $target.Path -or -not [System.IO.Path]::IsPathRooted([string]$target.Path)) { continue }
        if (-not $target.Pattern -and -not $target.Hash) { continue }
        if (-not (Test-Path -LiteralPath $target.Path -PathType Container)) { continue }

        foreach ($file in @(Get-ChildItem -LiteralPath $target.Path -File -ErrorAction SilentlyContinue)) {
            if ($target.Pattern -and $file.Name -notlike $target.Pattern) { continue }
            if ($target.Hash) {
                try { $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash }
                catch { continue }
                if ($hash -ne $target.Hash) { continue }
            }
            [pscustomobject]@{
                Name     = $file.Name
                FullName = $file.FullName
                Folder   = $target.Path
                SizeKB   = [int][math]::Round($file.Length / 1KB)
            }
        }
    }
}

function Stop-TargetService {
    $result = @()
    if (-not $StopService) { return @('Skipped') }
    foreach ($name in $ServiceNames) {
        if (-not $name) { continue }
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $service) { $result += "$name=Absent"; continue }
        if ($service.Status -eq 'Stopped') { $result += "$name=Stopped"; continue }
        try {
            Stop-Service -Name $name -Force -ErrorAction Stop
            $deadline = (Get-Date).AddSeconds(30)
            while ((Get-Service -Name $name -ErrorAction SilentlyContinue).Status -ne 'Stopped' -and (Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 2
            }
            if ((Get-Service -Name $name -ErrorAction SilentlyContinue).Status -eq 'Stopped') {
                $result += "$name=Stopped"
                Write-IRTLog "Service stopped: $name"
            } else {
                $result += "$name=StopTimeout"
                Write-IRTLog "Service did not stop in time: $name" 'WARN'
            }
        }
        catch {
            $result += "$name=StopFailed"
            Write-IRTLog "Stop failed for $($name): $($_.Exception.Message)" 'WARN'
        }
    }
    if ($result.Count -eq 0) { $result += 'Skipped' }
    $result
}

function Save-TargetFile {
    param($File)
    if (-not $BackupFiles) { return }
    if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop
    }
    $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
    $subPath = Join-Path $BackupRoot $stamp
    if (-not (Test-Path -LiteralPath $subPath -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $subPath -Force -ErrorAction Stop
    }
    Copy-Item -LiteralPath $File.FullName -Destination (Join-Path $subPath $File.Name) -Force -ErrorAction Stop
    Write-IRTLog "Backup taken: $($File.FullName) -> $subPath"
}

try {
    $present = @($Targets | Where-Object { $_.Path -and (Test-Path -LiteralPath $_.Path -PathType Container) })
    if ($present.Count -eq 0) {
        Exit-Script 0 "NotApplicable | Targets=$($Targets.Count); Present=0"
    }

    $files = @(Get-TargetFile)
    if ($files.Count -eq 0) {
        Exit-Script 0 "Healthy | Targets=$($present.Count); Matches=0"
    }

    $sample = (($files | Sort-Object Name | Select-Object -First $MaxFilesInOutput | ForEach-Object { $_.Name }) -join ',')
    $folders = (($files | Select-Object -ExpandProperty Folder -Unique | Select-Object -First $MaxFilesInOutput) -join ';')

    if (-not $EnableRemediation) {
        Exit-Script 0 "ReportOnly | Matches=$($files.Count); Files=$sample; Folders=$folders; Toggle=EnableRemediation"
    }

    $serviceState = (Stop-TargetService) -join ','

    $removed = 0
    $failed  = 0
    foreach ($file in $files) {
        try {
            try { Save-TargetFile -File $file }
            catch { Write-IRTLog "Backup failed for $($file.FullName): $($_.Exception.Message)" 'WARN' }

            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removed++
            Write-IRTLog "Removed: $($file.FullName)"
        }
        catch {
            $failed++
            Write-IRTLog "Delete failed for $($file.FullName): $($_.Exception.Message)" 'WARN'
        }
    }

    $left = @(Get-TargetFile)
    if ($left.Count -eq 0) {
        Exit-Script 0 "Fixed | Removed=$removed; Failed=$failed; Service=$serviceState; Files=$sample; Backup=$BackupRoot"
    }
    if ($removed -gt 0) {
        Exit-Script 1 "Partial | Removed=$removed; Failed=$failed; Remaining=$($left.Count); Service=$serviceState; Note=file in use"
    }
    Exit-Script 1 "Failed | Removed=0; Failed=$failed; Remaining=$($left.Count); Service=$serviceState; Note=file in use, safe mode may be needed"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
