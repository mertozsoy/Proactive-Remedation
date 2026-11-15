<#
.SYNOPSIS
  Remediation script that removes a leftover Delivery Optimization Bypass or Simple mode.

.DESCRIPTION
  Backs up the Delivery Optimization policy key, deletes the DownloadMode value when it is 99 or 100, restarts the Delivery Optimization service and verifies the value is gone. Exits 0 when removed, 1 when skipped or failed.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$DriftModes             = @(99, 100)
$TreatSimpleModeAsDrift = $true
$RestartDoService       = $true

$PackageName = 'DeliveryOptimizationBypass'
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

$DoPolicyKey  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
$MdmKey       = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeliveryOptimization'
$DoService    = 'DoSvc'
$BackupRoot   = Join-Path $env:ProgramData 'IntuneRemediations\Backup\DeliveryOptimizationBypass'
$NativeKey    = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'

function Get-DoState {
    $policy = Get-ItemProperty -LiteralPath $DoPolicyKey -ErrorAction SilentlyContinue
    $mdm    = Get-ItemProperty -LiteralPath $MdmKey -ErrorAction SilentlyContinue
    $mode   = $null
    if ($null -ne $policy -and $null -ne $policy.DownloadMode) { $mode = [int]$policy.DownloadMode }
    $managed = $false
    if ($null -ne $mdm -and $null -ne $mdm.DODownloadMode) { $managed = $true }
    [pscustomobject]@{ Mode = $mode; MdmManaged = $managed }
}

try {
    $ErrorActionPreference = 'Stop'

    $state = Get-DoState
    if ($null -eq $state.Mode) { Exit-Script 0 'Healthy | DownloadMode=NotSet' }
    if ($DriftModes -notcontains $state.Mode) { Exit-Script 0 "Healthy | DownloadMode=$($state.Mode)" }
    if ($state.Mode -eq 99 -and -not $TreatSimpleModeAsDrift) { Exit-Script 0 'Healthy | DownloadMode=99; Simple=Allowed' }
    if ($state.MdmManaged) { Exit-Script 1 "Skipped | Reason=MdmManaged; DownloadMode=$($state.Mode)" }

    New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop | Out-Null
    $backup = Join-Path $BackupRoot ('DeliveryOptimization-{0}.reg' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
    & $regExe export $NativeKey $backup /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backup -ErrorAction Stop)) { throw 'Registry export failed.' }
    if ((Get-Item -LiteralPath $backup -ErrorAction Stop).Length -eq 0) { throw 'Registry export is empty.' }

    $current = Get-DoState
    if ($null -eq $current.Mode -or $current.Mode -ne $state.Mode) { throw 'DownloadMode changed before removal.' }

    Remove-ItemProperty -LiteralPath $DoPolicyKey -Name 'DownloadMode' -Force -ErrorAction Stop
    Write-IRTLog "Removed DownloadMode=$($state.Mode); Backup=$([IO.Path]::GetFileName($backup))"

    $after = Get-DoState
    if ($null -ne $after.Mode) { Exit-Script 1 "Failed | DownloadMode=$($after.Mode); Backup=$([IO.Path]::GetFileName($backup))" }

    $restarted = 'No'
    if ($RestartDoService) {
        $svc = Get-Service -Name $DoService -ErrorAction SilentlyContinue
        if ($null -ne $svc) {
            try { Restart-Service -Name $DoService -Force -ErrorAction Stop; $restarted = 'Yes' }
            catch { Write-IRTLog "Restart-Service $DoService : $($_.Exception.Message)" 'WARN'; $restarted = 'Failed' }
        }
    }

    Exit-Script 0 "Fixed | RemovedMode=$($state.Mode); DownloadMode=NotSet; ServiceRestarted=$restarted"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
