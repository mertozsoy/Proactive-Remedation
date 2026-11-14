<#
.SYNOPSIS
  Remediation script for an outdated Microsoft Defender Antivirus platform.

.DESCRIPTION
  Downloads and installs one applicable KB4052623 update from the configured
  Windows Update source. Verifies AMProductVersion after installation. Exits 0
  only when the minimum is reached without a pending installation restart, or
  when not applicable. Does not change update policies or restart the device.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumPlatformVersion = '4.18.26100.4'
$AcceptUpdateEula = $false
$VerificationAttempts = 12
$VerificationIntervalSeconds = 10

$PackageName = 'DefenderPlatform'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-DefenderPlatformStatus {
    $status = Get-MpComputerStatus -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$status.AMProductVersion)) {
        throw 'Platform version unavailable.'
    }
    $platform = [version]$status.AMProductVersion
    if ($platform.Major -ne 4 -or $platform.Minor -ne 18 -or $platform.Revision -lt 0) {
        throw 'Invalid platform version.'
    }
    [pscustomobject]@{ Platform = $platform; Engine = [string]$status.AMEngineVersion }
}

try {
    $ErrorActionPreference = 'Stop'
    $minimum = [version]$MinimumPlatformVersion
    if ($minimum.Major -ne 4 -or $minimum.Minor -ne 18 -or $minimum.Revision -lt 0) {
        throw 'Invalid minimum platform version.'
    }
    if ($VerificationAttempts -lt 1 -or $VerificationAttempts -gt 60 -or
        $VerificationIntervalSeconds -lt 1 -or $VerificationIntervalSeconds -gt 30) {
        throw 'Invalid verification limits.'
    }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or ([version]$os.Version).Major -lt 10) {
        Exit-Script 0 'NotApplicable | Reason=WindowsClientRequired'
    }
    $service = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($null -eq $service) { Exit-Script 0 'NotApplicable | Reason=DefenderNotInstalled' }
    $before = Get-DefenderPlatformStatus
    if ($before.Platform -ge $minimum) {
        Exit-Script 0 "Healthy | Platform=$($before.Platform); Minimum=$minimum; Engine=$($before.Engine)"
    }
    if ($before.Platform -lt [version]'4.18.2001.10') {
        Exit-Script 1 "Blocked | Reason=PrerequisitePlatformRequired; Platform=$($before.Platform); Required=4.18.2001.10"
    }
    $systemInfo = New-Object -ComObject Microsoft.Update.SystemInfo
    if ($systemInfo.RebootRequired) { Exit-Script 1 'Pending | Reason=ExistingRestartRequired; RestartInitiated=False' }
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'IntuneRemediations.DefenderPlatform'
    $installer = $session.CreateUpdateInstaller()
    if ($installer.IsBusy) { Exit-Script 1 'Pending | Reason=UpdateInstallerBusy' }
    $searcher = $session.CreateUpdateSearcher()
    $searcher.ServerSelection = 0
    $searchResult = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
    if ($searchResult.ResultCode -ne 2) {
        Exit-Script 1 "Failed | Stage=Search; Result=$($searchResult.ResultCode)"
    }
    $candidates = @(
        for ($i = 0; $i -lt $searchResult.Updates.Count; $i++) {
            $update = $searchResult.Updates.Item($i)
            $matchesKb = $false
            for ($k = 0; $k -lt $update.KBArticleIDs.Count; $k++) {
                if ($update.KBArticleIDs.Item($k) -eq '4052623') { $matchesKb = $true }
            }
            if ($matchesKb -and -not $update.IsBeta -and -not $update.InstallationBehavior.CanRequestUserInput) {
                $update
            }
        }
    )
    if ($candidates.Count -eq 0) {
        Exit-Script 1 "Blocked | Reason=NoApplicablePlatformUpdate; Platform=$($before.Platform); Minimum=$minimum; Source=Configured"
    }
    $selected = $candidates | Sort-Object LastDeploymentChangeTime -Descending | Select-Object -First 1
    Write-IRTLog "Selected | UpdateId=$($selected.Identity.UpdateID); Revision=$($selected.Identity.RevisionNumber); KB=4052623"
    if (-not $selected.EulaAccepted) {
        if (-not $AcceptUpdateEula) { Exit-Script 1 'Blocked | Reason=EulaApprovalRequired; KB=4052623' }
        $selected.AcceptEula()
    }
    $updates = New-Object -ComObject Microsoft.Update.UpdateColl
    [void]$updates.Add($selected)
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $updates
    $downloadResult = $downloader.Download()
    $downloadItem = $downloadResult.GetUpdateResult(0)
    if ($downloadResult.ResultCode -ne 2 -or $downloadItem.ResultCode -ne 2 -or -not $selected.IsDownloaded) {
        Exit-Script 1 "Failed | Stage=Download; Result=$($downloadItem.ResultCode); HResult=$($downloadItem.HResult)"
    }
    $installer.Updates = $updates
    $installer.AllowSourcePrompts = $false
    if ($installer.IsBusy) { Exit-Script 1 'Pending | Reason=UpdateInstallerBusy' }
    if ($installer.RebootRequiredBeforeInstallation -or $systemInfo.RebootRequired) {
        Exit-Script 1 'Pending | Reason=ExistingRestartRequired; RestartInitiated=False'
    }
    $installResult = $installer.Install()
    $installItem = $installResult.GetUpdateResult(0)
    Write-IRTLog "Install | Result=$($installResult.ResultCode); ItemResult=$($installItem.ResultCode); HResult=$($installItem.HResult); RebootRequired=$($installResult.RebootRequired)"
    if ($installResult.ResultCode -ne 2 -or $installItem.ResultCode -ne 2) {
        Exit-Script 1 "Failed | Stage=Install; Result=$($installItem.ResultCode); HResult=$($installItem.HResult)"
    }
    if ($installResult.RebootRequired -or $installItem.RebootRequired) {
        Exit-Script 1 'Pending | Reason=InstallationRestartRequired; RestartInitiated=False'
    }
    $after = $before
    for ($attempt = 1; $attempt -le $VerificationAttempts; $attempt++) {
        try {
            $after = Get-DefenderPlatformStatus
            if ($after.Platform -ge $minimum) {
                Exit-Script 0 "Fixed | Before=$($before.Platform); Platform=$($after.Platform); Minimum=$minimum; Engine=$($after.Engine)"
            }
        }
        catch { Write-IRTLog ('VerificationReadFailed | HResult={0}' -f $_.Exception.HResult) 'WARN' }
        if ($attempt -lt $VerificationAttempts) { Start-Sleep -Seconds $VerificationIntervalSeconds }
    }
    Exit-Script 1 "Pending | Reason=MinimumNotVerified; Platform=$($after.Platform); Minimum=$minimum; KB=4052623"
}
catch { Exit-Script 1 ('Error: UpdateFailed | HResult={0}' -f $_.Exception.HResult) }
