<#
.SYNOPSIS
  Remediation script that rebuilds a corrupt local Registry.pol file.

.DESCRIPTION
  Copies the damaged %SystemRoot%\System32\GroupPolicy\Machine\Registry.pol to a backup folder, replaces it with an empty valid PReg header and runs gpupdate /force so the policy store is filled again from the domain and the local settings that are still valid. Exits 0 if the file is valid after the repair, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PolicyFile          = Join-Path $env:SystemRoot 'System32\GroupPolicy\Machine\Registry.pol'
$BackupRoot          = Join-Path $env:ProgramData 'IntuneRemediations\Backup\RegistryPol'
$KeepBackupFolders   = 5
$EnableRemediation   = $true
$RunGpUpdate         = $true
$GpUpdateWaitSeconds = 120
$EventWindowDays     = 7
$PolicyEventLog      = 'Microsoft-Windows-GroupPolicy/Operational'
$PolicyEventId       = 1096

$PackageName = 'RegistryPol'
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

function Get-PolicyFileState { param([string]$Path)
    $state = [pscustomobject]@{ Exists = $false; Valid = $false; Reason = 'Missing'; Bytes = 0 }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $state }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $state.Exists = $true
    $state.Bytes = $bytes.Length
    if ($bytes.Length -eq 0) { $state.Reason = 'EmptyFile'; return $state }
    if ($bytes.Length -lt 8) { $state.Reason = 'TooShort'; return $state }
    if (-not ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x52 -and $bytes[2] -eq 0x65 -and $bytes[3] -eq 0x67)) {
        $state.Reason = 'BadSignature'
        return $state
    }
    $version = [System.BitConverter]::ToUInt32($bytes, 4)
    if ($version -ne 1) { $state.Reason = "BadVersion=$version"; return $state }
    if (($bytes.Length % 2) -ne 0) { $state.Reason = 'OddLength'; return $state }
    if ($bytes.Length -gt 8) {
        if (-not ($bytes[8] -eq 0x5B -and $bytes[9] -eq 0x00)) { $state.Reason = 'BadRecordStart'; return $state }
        $last = $bytes.Length - 1
        if (-not ($bytes[$last] -eq 0x00 -and $bytes[$last - 1] -eq 0x5D)) { $state.Reason = 'TruncatedRecord'; return $state }
    }
    $state.Valid = $true
    $state.Reason = 'OK'
    $state
}

function Get-PolicyErrorCount { param([datetime]$Since)
    try {
        $filter = @{ LogName = $PolicyEventLog; Id = $PolicyEventId; StartTime = $Since }
        $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
        return $events.Count
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return 0 }
        return -1
    }
}

function Invoke-FileMove { param([string]$Source, [string]$Target)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Move-Item -LiteralPath $Source -Destination $Target -Force -ErrorAction Stop
            return $true
        }
        catch {
            Write-IRTLog "Move attempt $attempt failed: $($_.Exception.Message)" 'WARN'
            Start-Sleep -Seconds 2
        }
    }
    return $false
}

try {
    $startTime = Get-Date
    $before = Get-PolicyFileState -Path $PolicyFile
    Write-IRTLog ("Policy file state: Exists={0} Valid={1} Reason={2} Bytes={3}" -f $before.Exists, $before.Valid, $before.Reason, $before.Bytes)

    if (-not $before.Exists) { Exit-Script 0 "NotApplicable | RegistryPol=missing; Path=$PolicyFile" }
    if ($before.Valid) { Exit-Script 0 "Healthy | RegistryPol=valid; Bytes=$($before.Bytes)" }
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | RegistryPol=corrupt; Reason=$($before.Reason); Bytes=$($before.Bytes)" }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $BackupRoot $stamp
    $null = New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop
    Copy-Item -LiteralPath $PolicyFile -Destination (Join-Path $backupDir 'Registry.pol') -Force -ErrorAction Stop
    $gptIni = Join-Path (Split-Path -Path $PolicyFile -Parent) 'gpt.ini'
    if (Test-Path -LiteralPath $gptIni) {
        Copy-Item -LiteralPath $gptIni -Destination (Join-Path $backupDir 'gpt.ini') -Force -ErrorAction Stop
    }
    Write-IRTLog "Backup written to $backupDir"

    $quarantine = Join-Path $backupDir 'Registry.pol.corrupt'
    if (-not (Invoke-FileMove -Source $PolicyFile -Target $quarantine)) {
        Exit-Script 1 "Failed | RegistryPol=locked; Reason=$($before.Reason); Backup=$stamp"
    }

    $header = [byte[]](0x50, 0x52, 0x65, 0x67, 0x01, 0x00, 0x00, 0x00)
    [System.IO.File]::WriteAllBytes($PolicyFile, $header)
    Write-IRTLog 'Empty PReg header written'

    $gpExit = -1
    if ($RunGpUpdate) {
        $gpupdate = Join-Path $env:SystemRoot 'System32\gpupdate.exe'
        $gpArgs = @('/force', "/wait:$GpUpdateWaitSeconds")
        $proc = Start-Process -FilePath $gpupdate -ArgumentList $gpArgs -WindowStyle Hidden -PassThru -Wait
        $gpExit = $proc.ExitCode
        Write-IRTLog "gpupdate finished with exit code $gpExit"
    }

    $after = Get-PolicyFileState -Path $PolicyFile
    $errors = Get-PolicyErrorCount -Since $startTime
    if (-not $after.Valid) {
        Exit-Script 1 "Failed | RegistryPol=$($after.Reason); Backup=$stamp; GpUpdate=$gpExit"
    }

    $old = @(Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($old.Count -gt $KeepBackupFolders) {
        foreach ($item in ($old | Select-Object -Skip $KeepBackupFolders)) {
            try { Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop } catch { Write-IRTLog "Old backup not removed: $($item.Name)" 'WARN' }
        }
    }

    Exit-Script 0 "Fixed | Previous=$($before.Reason); Bytes=$($after.Bytes); GpUpdate=$gpExit; Policy1096=$errors; Backup=$stamp"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
