<#
.SYNOPSIS
  Runs Office Click-to-Run Quick Repair after repeated crashes.

.DESCRIPTION
  Rechecks the crash threshold and runs the signed local repair client when
  explicitly enabled and Office apps are closed. Verifies client exit, service
  and application files. Exit 0 means these checks passed, not proven stability.
  No Office process is terminated. Failed or unverified attempts require review.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $false
$LookbackHours = 24
$CrashThreshold = 3
$CooldownHours = 72
$RepairTimeoutSeconds = 900

$PackageName = 'OfficeQuickRepair'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
$StateFile = Join-Path (Split-Path $LogFile) "IRT_$PackageName.state.json"
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
function Get-RepairState {
    $state = [pscustomobject]@{ LastAttemptUtc = $null; LastReturnedUtc = $null }
    if (Test-Path -LiteralPath $StateFile) {
        $saved = Get-Content -LiteralPath $StateFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($saved.Schema -ne 1 -or -not $saved.LastAttemptUtc) { throw 'InvalidState' }
        foreach ($name in @('LastAttemptUtc', 'LastReturnedUtc')) {
            if ($saved.$name) {
                $value = [datetimeoffset]::Parse($saved.$name, [cultureinfo]::InvariantCulture).UtcDateTime
                if ($value -gt [datetime]::UtcNow.AddMinutes(5)) { throw 'FutureState' }
                $state.$name = $value
            }
        }
        if ($state.LastReturnedUtc -and $state.LastReturnedUtc -lt $state.LastAttemptUtc) { throw 'InvalidStateOrder' }
    }
    return $state
}
function Get-OfficeCrashSummary { param([string]$OfficeRoot, [datetime]$StartTime)
    $counts = @{ 'winword.exe' = 0; 'excel.exe' = 0; 'outlook.exe' = 0 }
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $StartTime.ToLocalTime() } -ErrorAction Stop)
    }
    catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
        $events = @()
    }
    foreach ($crashEvent in $events) {
        $xml = [xml]$crashEvent.ToXml()
        $fields = @{}
        foreach ($node in $xml.Event.EventData.Data) { $fields[[string]$node.Name] = [string]$node.InnerText }
        if (-not $fields.ContainsKey('AppName') -or -not $fields.ContainsKey('AppPath')) { throw 'UnsupportedEventSchema' }
        $app = $fields['AppName'].ToLowerInvariant()
        if ($counts.ContainsKey($app) -and $fields['AppPath'].StartsWith($OfficeRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $counts[$app]++
        }
    }
    $affected = @($counts.Keys | Where-Object { $counts[$_] -ge $CrashThreshold } | Sort-Object)
    $text = (@($counts.Keys | Sort-Object | ForEach-Object { '{0}={1}' -f $_, $counts[$_] }) -join '; ')
    $total = ($counts.Values | Measure-Object -Sum).Sum
    return [pscustomobject]@{ Affected = $affected; Text = $text; Total = $total }
}
function Save-RepairState { param([datetime]$AttemptUtc, $ReturnedUtc)
    $returned = $null
    if ($ReturnedUtc) { $returned = $ReturnedUtc.ToString('o', [cultureinfo]::InvariantCulture) }
    $record = @{ Schema = 1; LastAttemptUtc = $AttemptUtc.ToString('o', [cultureinfo]::InvariantCulture); LastReturnedUtc = $returned }
    $record | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8 -ErrorAction Stop
}

$repairMutex = $null
$hasLock = $false
try {
    $ErrorActionPreference = 'Stop'
    $repairMutex = New-Object System.Threading.Mutex($false, 'Global\IRT_OfficeQuickRepair')
    try { $hasLock = $repairMutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $hasLock = $true }
    if (-not $hasLock) { Exit-Script 1 'Deferred | Reason=AnotherRemediationRunning; Action=RetryLater' }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if ($LookbackHours -lt 1 -or $CrashThreshold -lt 2 -or $CooldownHours -lt $LookbackHours -or $RepairTimeoutSeconds -lt 30 -or $RepairTimeoutSeconds -gt 1200) { throw 'InvalidSettings' }
    $configPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (-not (Test-Path -LiteralPath $configPath)) { Exit-Script 0 'NotApplicable | Reason=NoClickToRun' }
    $config = Get-ItemProperty -LiteralPath $configPath
    if ([string]$config.Platform -notin @('x86', 'x64')) { Exit-Script 0 'NotApplicable | Reason=UnsupportedOfficePlatform' }
    if (-not $config.InstallationPath -or -not [IO.Path]::IsPathRooted($config.InstallationPath)) { throw 'InvalidOfficePath' }
    $officeRoot = [IO.Path]::GetFullPath($config.InstallationPath).TrimEnd('\') + '\'
    $state = Get-RepairState
    $start = [datetime]::UtcNow.AddHours(-$LookbackHours)
    if ($state.LastReturnedUtc -and $state.LastReturnedUtc -gt $start) { $start = $state.LastReturnedUtc }
    $crashes = Get-OfficeCrashSummary -OfficeRoot $officeRoot -StartTime $start
    if ($state.LastAttemptUtc -and -not $state.LastReturnedUtc) {
        Exit-Script 1 'Pending | Reason=PreviousAttemptUnverified; Action=ReviewRepairBeforeResettingState'
    }
    if ($crashes.Affected.Count -eq 0) { Exit-Script 0 "Healthy | Reason=BelowThreshold; $($crashes.Text)" }
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | Reason=ApprovalRequired; $($crashes.Text)" }
    if ($state.LastAttemptUtc -and [datetime]::UtcNow -lt $state.LastAttemptUtc.AddHours($CooldownHours)) {
        Exit-Script 1 'Pending | Reason=RepairCooldown; Action=InvestigateRecurrence'
    }
    $processes = @(Get-CimInstance -ClassName Win32_Process)
    $officeNames = @('winword.exe', 'excel.exe', 'outlook.exe', 'powerpnt.exe', 'onenote.exe', 'msaccess.exe', 'mspub.exe', 'visio.exe', 'winproj.exe')
    if (@($processes | Where-Object { $officeNames -contains $_.Name }).Count -gt 0) {
        Exit-Script 1 'Deferred | Reason=OfficeAppsOpen; Action=SaveAndCloseOffice'
    }
    if (@($processes | Where-Object { $_.Name -in @('OfficeC2RClient.exe', 'IntegratedOffice.exe', 'msiexec.exe') -or ($_.Name -eq 'OfficeClickToRun.exe' -and $_.CommandLine -notmatch '(?i)\s/service(?:\s|$)') }).Count -gt 0) {
        Exit-Script 1 'Deferred | Reason=InstallerBusy; Action=RetryLater'
    }
    if ((Get-Service -Name ClickToRunSvc).Status -ne 'Running') { throw 'ClickToRunServiceNotRunning' }
    $repairExe = Join-Path $env:CommonProgramFiles 'Microsoft Shared\ClickToRun\OfficeClickToRun.exe'
    if (-not (Test-Path -LiteralPath $repairExe -PathType Leaf)) { throw 'RepairClientMissing' }
    $signature = Get-AuthenticodeSignature -LiteralPath $repairExe
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') { throw 'UntrustedRepairClient' }
    $appFiles = @()
    foreach ($app in $crashes.Affected) {
        $paths = @((Join-Path $officeRoot "root\Office16\$app"), (Join-Path $officeRoot "Office16\$app"))
        $file = @($paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
        if ($file.Count -eq 0) { throw 'OfficeApplicationMissing' }
        $appFiles += $file[0]
    }
    $attempt = [datetime]::UtcNow
    Save-RepairState -AttemptUtc $attempt -ReturnedUtc $null
    $arguments = "scenario=Repair platform=$($config.Platform) RepairType=QuickRepair DisplayLevel=False forceappshutdown=False"
    Write-IRTLog "Starting QuickRepair | Platform=$($config.Platform); $($crashes.Text)"
    $client = Start-Process -FilePath $repairExe -ArgumentList $arguments -PassThru
    if (-not $client.WaitForExit($RepairTimeoutSeconds * 1000)) {
        Exit-Script 1 'Pending | Reason=RepairClientTimeout; Action=ReviewRepair; Process=LeftRunning'
    }
    $client.WaitForExit()
    if ($client.ExitCode -ne 0) { Exit-Script 1 "Failed | Reason=RepairClientExit; ExitCode=$($client.ExitCode)" }
    if ((Get-Service -Name ClickToRunSvc).Status -ne 'Running') { throw 'PostRepairServiceCheckFailed' }
    foreach ($file in $appFiles) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'PostRepairFileCheckFailed' }
    }
    $after = Get-OfficeCrashSummary -OfficeRoot $officeRoot -StartTime $attempt
    if ($after.Total -gt 0) {
        Exit-Script 1 "Failed | Reason=CrashDuringRepair; $($after.Text)"
    }
    Save-RepairState -AttemptUtc $attempt -ReturnedUtc ([datetime]::UtcNow)
    Exit-Script 0 'RepairReturned | ClientExitCode=0; Service=Running; AppFiles=Present; Stability=NotProven'
}
catch { Exit-Script 1 "Failed | Reason=RepairError; ErrorType=$($_.Exception.GetType().Name)" }
finally {
    if ($hasLock) { $repairMutex.ReleaseMutex() }
    if ($repairMutex) { $repairMutex.Dispose() }
}
