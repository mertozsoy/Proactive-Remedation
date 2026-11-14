<#
.SYNOPSIS
  Repairs a local Microsoft 365 Apps update source and restarts update detection.

.DESCRIPTION
  Preserves centrally managed installations. Backs up local configuration before
  correcting an approved source, clears the detection timestamp and runs the Office
  update task. Verifies task completion and any configured minimum installed build.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedUpdateUrl = ''
$MinimumVersion = ''
$MaxTaskAgeDays = 7
$TaskTimeoutSeconds = 180

$PackageName = 'OfficeC2RUpdates'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}
function Backup-OfficeRegistry { param([string]$NativePath, [string]$Label)
    $backupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
    New-Item -Path $backupRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $backupFile = Join-Path $backupRoot ('OfficeC2RUpdates_{0}_{1}.reg' -f $Label, [guid]::NewGuid().ToString('N'))
    & "$env:SystemRoot\System32\reg.exe" export $NativePath $backupFile /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupFile)) { throw 'RegistryBackupFailed' }
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if ($MaxTaskAgeDays -lt 1 -or $TaskTimeoutSeconds -lt 10 -or $TaskTimeoutSeconds -gt 300) { Exit-Script 1 'Failed | Reason=InvalidTiming' }
    if ($MinimumVersion -and $MinimumVersion -notmatch '^16\.0\.\d+\.\d+$') { Exit-Script 1 'Failed | Reason=InvalidMinimumVersion' }
    if ($ApprovedUpdateUrl) {
        $approvedUri = [uri]$ApprovedUpdateUrl
        if (-not $approvedUri.IsAbsoluteUri -or $approvedUri.Scheme -ne 'https' -or $approvedUri.UserInfo -or $approvedUri.Query -or $approvedUri.Fragment) {
            Exit-Script 1 'Failed | Reason=ApprovedSourceMustBeHttpsWithoutCredentialsOrQuery'
        }
    }
    $configPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $inventoryPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Inventory\Office\16.0'
    $updatesPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Updates'
    if (-not (Test-Path -LiteralPath $configPath)) { Exit-Script 0 'NotApplicable | Reason=NoClickToRun' }
    $config = Get-ItemProperty -LiteralPath $configPath
    $policyPaths = @('HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate', 'HKLM:\SOFTWARE\Policies\Microsoft\cloud\office\16.0\Common\officeupdate')
    foreach ($path in $policyPaths) {
        if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Property.Count -gt 0) {
            Exit-Script 0 'NotApplicable | Reason=ManagedOfficePolicy; Action=ReviewCentralManagement'
        }
    }
    if ([string]$config.OfficeMgmtCOM -match '^(true|1)$' -or (Get-Service -Name CcmExec -ErrorAction SilentlyContinue)) {
        Exit-Script 0 'NotApplicable | Reason=ConfigurationManager; Action=ReviewCentralManagement'
    }
    if (-not (Test-Path -LiteralPath $inventoryPath)) { Exit-Script 1 'Failed | Reason=OfficeInventoryMissing' }
    $inventory = Get-ItemProperty -LiteralPath $inventoryPath
    if (($inventory.OfficeProductReleaseIds -join ',') -notmatch '(^|[,;\s])(O365ProPlusRetail|O365BusinessRetail)($|[,;\s])') {
        Exit-Script 0 'NotApplicable | Reason=NotMicrosoft365Apps'
    }
    if ([string]$inventory.OfficePackageVersion -notmatch '^16\.0\.\d+\.\d+$') { Exit-Script 1 'Failed | Reason=OfficeInventoryVersionInvalid' }
    $task = Get-ScheduledTask -TaskPath '\Microsoft\Office\' -TaskName 'Office Automatic Updates 2.0'
    if ($task.State -eq 'Running') { Exit-Script 1 'Pending | Reason=OfficeTaskAlreadyRunning; Action=RetryLater' }
    $service = Get-Service -Name ClickToRunSvc
    if ($service.Status -ne 'Running') { Exit-Script 1 'Failed | Reason=ClickToRunServiceStopped; Action=RepairServiceSeparately' }
    $sourceChanged = $false
    if ($ApprovedUpdateUrl -and ([string]$config.UpdateUrl).TrimEnd('/') -ne $ApprovedUpdateUrl.TrimEnd('/')) {
        Backup-OfficeRegistry 'HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' 'Configuration'
        New-ItemProperty -LiteralPath $configPath -Name UpdateUrl -Value $ApprovedUpdateUrl -PropertyType String -Force | Out-Null
        $sourceChanged = $true
    }
    if (Test-Path -LiteralPath $updatesPath) {
        $updatesKey = Get-Item -LiteralPath $updatesPath
        if ($updatesKey.Property -contains 'UpdateDetectionLastRunTime') {
            Backup-OfficeRegistry 'HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Updates' 'Updates'
            Set-ItemProperty -LiteralPath $updatesPath -Name UpdateDetectionLastRunTime -Value ''
        }
    }
    if ($task.State -eq 'Disabled') { $task | Enable-ScheduledTask | Out-Null }
    $beforeRun = ($task | Get-ScheduledTaskInfo).LastRunTime
    $task | Start-ScheduledTask
    $deadline = (Get-Date).AddSeconds($TaskTimeoutSeconds)
    $completed = $false
    do {
        Start-Sleep -Seconds 3
        $task = Get-ScheduledTask -TaskPath '\Microsoft\Office\' -TaskName 'Office Automatic Updates 2.0'
        $info = $task | Get-ScheduledTaskInfo
        if ($info.LastRunTime -gt $beforeRun -and $task.State -ne 'Running' -and $task.State -ne 'Queued') {
            $completed = $true
            break
        }
    } while ((Get-Date) -lt $deadline)
    if (-not $completed) { Exit-Script 1 "Pending | Reason=TaskCompletionNotObserved; SourceChanged=$sourceChanged; Action=RetryLater" }
    if ($info.LastTaskResult -ne 0 -or $task.State -eq 'Disabled') { Exit-Script 1 "Failed | Reason=OfficeTaskFailure; TaskResult=$($info.LastTaskResult)" }
    $config = Get-ItemProperty -LiteralPath $configPath
    if ($ApprovedUpdateUrl -and ([string]$config.UpdateUrl).TrimEnd('/') -ne $ApprovedUpdateUrl.TrimEnd('/')) { Exit-Script 1 'Failed | Reason=SourceVerificationFailed' }
    $inventory = Get-ItemProperty -LiteralPath $inventoryPath
    if ([string]$inventory.OfficePackageVersion -notmatch '^16\.0\.\d+\.\d+$') { Exit-Script 1 'Failed | Reason=OfficeInventoryVersionInvalid' }
    $version = [version]$inventory.OfficePackageVersion
    if ($MinimumVersion -and $version -lt [version]$MinimumVersion) { Exit-Script 1 "Pending | Version=$version; Reason=BelowMinimum; Update=NotYetVerified" }
    Exit-Script 0 "Fixed | SourceChanged=$sourceChanged; TaskResult=0; Version=$version; Update=TaskCompletedNotBuildGuarantee"
}
catch { Exit-Script 1 "Failed | Reason=RepairError; ErrorType=$($_.Exception.GetType().Name)" }
