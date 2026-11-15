<#
.SYNOPSIS
  Remediation script for legacy Microsoft LAPS remnants.

.DESCRIPTION
  Removes legacy MSI software and approved remnants after migration approval and native Windows LAPS backup evidence. Exits 0 after verified cleanup, 1 when blocked or incomplete. Never rotates a password or restarts the device.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$LegacyPolicyRetiredConfirmed = $false
$RemoveStalePolicy = $false
$RemoveManualCse = $false
$ApprovedManualDllPaths = @()
$ExpectedBackupDirectory = 1
$BackupEvidenceMaxAgeDays = 45

$PackageName = 'LegacyLaps'
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
function Get-LegacyLapsProduct {
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path -LiteralPath $root -ErrorAction Stop)) { continue }
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction Stop) {
            $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            if ($item.DisplayName -eq 'Local Administrator Password Solution' -and $item.Publisher -eq 'Microsoft Corporation') {
                [pscustomobject]@{ Code = $key.PSChildName; Msi = ([int]$item.WindowsInstaller -eq 1) }
            }
        }
    }
}
function Get-NativeLapsPolicy {
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Policies\LAPS', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\LAPS\Config')) {
        if (-not (Test-Path -LiteralPath $root -ErrorAction Stop)) { continue }
        $key = Get-Item -LiteralPath $root -ErrorAction Stop
        if ($key.GetValueNames().Count -gt 0) {
            return [int]$key.GetValue('BackupDirectory', 0)
        }
    }
    return 0
}
function Test-NativeBackupEvidence {
    $configId = 10022
    $backupId = 10029
    if ($ExpectedBackupDirectory -eq 2) { $configId = 10021; $backupId = 10018 }
    $events = @(Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-LAPS/Operational'
        Id = @(10003, 10004, 10005, 10020, 10021, 10022, 10023, 10018, 10029)
        StartTime = (Get-Date).AddDays(-$BackupEvidenceMaxAgeDays)
    } -MaxEvents 10000 -ErrorAction Stop | Sort-Object RecordId)
    $inCycle = $false
    $native = $false
    $backup = $false
    $localUpdate = $false
    foreach ($lapsEvent in $events) {
        if ($lapsEvent.Id -eq 10003) {
            $inCycle = $true; $native = $false; $backup = $false; $localUpdate = $false
        }
        if (-not $inCycle) { continue }
        if ($lapsEvent.Id -in @(10021, 10022, 10023)) { $native = ($lapsEvent.Id -eq $configId) }
        if ($lapsEvent.Id -eq $backupId) { $backup = $true }
        if ($lapsEvent.Id -eq 10020) { $localUpdate = $true }
        if ($lapsEvent.Id -eq 10004 -and $native -and $backup -and $localUpdate) { return $true }
        if ($lapsEvent.Id -in @(10004, 10005)) { $inCycle = $false }
    }
    return $false
}
function Backup-RegistryKey { param([string]$Path, [string]$Name)
    $destination = Join-Path $BackupFolder "$Name.reg"
    $nativePath = $Path -replace '^HKLM:', 'HKEY_LOCAL_MACHINE'
    $process = Start-Process -FilePath "$env:SystemRoot\System32\reg.exe" -ArgumentList "export `"$nativePath`" `"$destination`" /y" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $destination -ErrorAction Stop)) { throw 'RegistryBackupFailed' }
}
try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $csePath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\GPExtensions\{D76B9641-3288-4f75-942D-087DE603E3EA}'
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft Services\AdmPwd'
    $products = @(Get-LegacyLapsProduct)
    $cse = Test-Path -LiteralPath $csePath -ErrorAction Stop
    $policy = Test-Path -LiteralPath $policyPath -ErrorAction Stop
    if ($products.Count -eq 0 -and -not $cse -and -not $policy) { Exit-Script 0 'Healthy | Products=0; CseRegistered=False; LegacyPolicy=False' }
    if (-not $LegacyPolicyRetiredConfirmed) { Exit-Script 1 'Blocked | Reason=ConfirmLegacyPolicyAndDeploymentRetired' }
    if ($ExpectedBackupDirectory -notin @(1, 2) -or $BackupEvidenceMaxAgeDays -lt 1 -or $BackupEvidenceMaxAgeDays -gt 365) { Exit-Script 1 'Blocked | Reason=InvalidConfiguration' }
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($computer.DomainRole -ge 4) { Exit-Script 0 'NotApplicable | Reason=DomainController' }
    if ((Get-NativeLapsPolicy) -ne $ExpectedBackupDirectory) { Exit-Script 1 'Blocked | Reason=NativeBackupTargetMismatch' }
    if (-not (Test-NativeBackupEvidence)) { Exit-Script 1 'Blocked | Reason=NativeBackupEvidenceMissing' }
    if ($policy -and -not $RemoveStalePolicy) { Exit-Script 1 'Blocked | Reason=StalePolicyRemovalNotApproved' }
    foreach ($product in $products) {
        if (-not $product.Msi -or $product.Code -notmatch '^\{[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}$') {
            Exit-Script 1 'Blocked | Reason=UnsupportedProductRegistration'
        }
    }
    $BackupFolder = Join-Path $env:ProgramData ('IntuneRemediations\Backup\LegacyLaps\' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $BackupFolder -ItemType Directory -Force -ErrorAction Stop
    if ($policy) { Backup-RegistryKey -Path $policyPath -Name 'AdmPwdPolicy' }
    if ($cse) { Backup-RegistryKey -Path $csePath -Name 'AdmPwdCse' }
    if ($products.Count -eq 0 -and $cse -and -not $RemoveManualCse) { Exit-Script 1 'Blocked | Reason=ManualCseRemovalNotApproved' }
    foreach ($product in $products) {
        $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/x $($product.Code) /qn /norestart REBOOT=ReallySuppress" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        Write-IRTLog "MsiExitCode=$($process.ExitCode)"
        if ($process.ExitCode -eq 3010) { Exit-Script 1 'Pending | Reason=MsiRebootRequired; RestartInitiated=False' }
        if ($process.ExitCode -notin @(0, 1605, 1614)) { Exit-Script 1 "Failed | Reason=MsiUninstallFailed; ExitCode=$($process.ExitCode)" }
    }
    $remainingProducts = @(Get-LegacyLapsProduct)
    if ($remainingProducts.Count -gt 0) { Exit-Script 1 "Failed | Reason=ProductStillRegistered; Products=$($remainingProducts.Count)" }
    if (Test-Path -LiteralPath $csePath -ErrorAction Stop) {
        if (-not $RemoveManualCse) { Exit-Script 1 'Blocked | Reason=ManualCseRemovalNotApproved' }
        Backup-RegistryKey -Path $csePath -Name 'AdmPwdCseBeforeUnregister'
        $dll = [Environment]::ExpandEnvironmentVariables([string](Get-ItemProperty -LiteralPath $csePath -ErrorAction Stop).DllName).Trim('"')
        if (-not [IO.Path]::IsPathRooted($dll) -or [IO.Path]::GetFileName($dll) -ine 'AdmPwd.dll' -or $ApprovedManualDllPaths -notcontains $dll) {
            Exit-Script 1 'Blocked | Reason=ManualDllPathNotApproved'
        }
        if (Test-Path -LiteralPath $dll -PathType Leaf -ErrorAction Stop) {
            $file = Get-Item -LiteralPath $dll -ErrorAction Stop
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Exit-Script 1 'Blocked | Reason=DllReparsePoint' }
            $signature = Get-AuthenticodeSignature -LiteralPath $dll -ErrorAction Stop
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
                Exit-Script 1 'Blocked | Reason=DllSignatureNotTrusted'
            }
            Copy-Item -LiteralPath $dll -Destination (Join-Path $BackupFolder 'AdmPwd.dll') -ErrorAction Stop
            $process = Start-Process -FilePath "$env:SystemRoot\System32\regsvr32.exe" -ArgumentList "/s /u `"$dll`"" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
            if ($process.ExitCode -ne 0) { Exit-Script 1 "Failed | Reason=CseUnregisterFailed; ExitCode=$($process.ExitCode)" }
            Remove-Item -LiteralPath $dll -Force -ErrorAction Stop
            if (Test-Path -LiteralPath $dll -ErrorAction Stop) { Exit-Script 1 'Failed | Reason=DllStillPresent' }
        }
        if (Test-Path -LiteralPath $csePath -ErrorAction Stop) {
            Backup-RegistryKey -Path $csePath -Name 'AdmPwdCseBeforeDelete'
            Remove-Item -LiteralPath $csePath -Recurse -Force -ErrorAction Stop
        }
    }
    if (Test-Path -LiteralPath $policyPath -ErrorAction Stop) {
        if (-not $RemoveStalePolicy) { Exit-Script 1 'Blocked | Reason=StalePolicyRemovalNotApproved' }
        Backup-RegistryKey -Path $policyPath -Name 'AdmPwdPolicyBeforeDelete'
        Remove-Item -LiteralPath $policyPath -Recurse -Force -ErrorAction Stop
    }
    $products = @(Get-LegacyLapsProduct)
    $cse = Test-Path -LiteralPath $csePath -ErrorAction Stop
    $policy = Test-Path -LiteralPath $policyPath -ErrorAction Stop
    $summary = "Products=$($products.Count); CseRegistered=$cse; LegacyPolicy=$policy"
    if ($products.Count -gt 0 -or $cse -or $policy) { Exit-Script 1 "Failed | $summary" }
    if ((Get-NativeLapsPolicy) -ne $ExpectedBackupDirectory) { Exit-Script 1 'Failed | Reason=NativePolicyChangedDuringCleanup' }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 ('Error | Reason=CleanupFailed; HResult={0}' -f $_.Exception.HResult) }
