<#
.SYNOPSIS
  Remediation script for a missing or damaged machine-wide WebView2 Runtime.

.DESCRIPTION
  Runs a Microsoft-signed Evergreen installer as SYSTEM and verifies registration
  and runtime files. An optional registration reset is disabled by default.
  Exits 0 after verification, 1 if installation is blocked or checks still fail.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RuntimeRoots = @()
$InstallerPath = ''
$BootstrapperUri = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'
$InstallTimeoutSeconds = 600
$VerificationSeconds = 60
$ResetBrokenRegistration = $false

$PackageName = 'WebView2Runtime'
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
function Get-RuntimeState {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry32)
    try {
        $key = $base.OpenSubKey('SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}')
        $raw = ''
        if ($null -ne $key) {
            try { $raw = [string]$key.GetValue('pv', '') } finally { $key.Dispose() }
        }
    } finally { $base.Dispose() }
    $version = $null
    if ($raw -notmatch '^\d+\.\d+\.\d+\.\d+$' -or -not [version]::TryParse($raw, [ref]$version) -or $version -le [version]'0.0.0.0') {
        return [pscustomobject]@{ Healthy = $false; Reason = 'RegistrationMissing'; Version = 'None'; Registered = $false }
    }
    foreach ($root in $RuntimeRoots) {
        $directory = Join-Path $root $raw
        $executable = Join-Path $directory 'msedgewebview2.exe'
        $library = Join-Path $directory 'msedge.dll'
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf -ErrorAction Stop)) { continue }
        if (-not (Test-Path -LiteralPath $library -PathType Leaf -ErrorAction Stop)) { continue }
        if ((Get-Item -LiteralPath $library -ErrorAction Stop).Length -eq 0) { continue }
        $signature = Get-AuthenticodeSignature -LiteralPath $executable -ErrorAction Stop
        if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate) {
            return [pscustomobject]@{ Healthy = $false; Reason = "Signature$($signature.Status)"; Version = $raw; Registered = $true }
        }
        $publisher = $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
        if ($publisher -ne 'Microsoft Corporation') {
            return [pscustomobject]@{ Healthy = $false; Reason = 'UnexpectedPublisher'; Version = $raw; Registered = $true }
        }
        return [pscustomobject]@{ Healthy = $true; Reason = 'FilesVerified'; Version = $raw; Registered = $true }
    }
    return [pscustomobject]@{ Healthy = $false; Reason = 'RuntimeFilesMissing'; Version = $raw; Registered = $true }
}
function Get-ServicingPolicy {
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
    if (-not (Test-Path -LiteralPath $policyPath)) { return }
    $policy = Get-ItemProperty -LiteralPath $policyPath -ErrorAction Stop
    $names = @('InstallDefault', 'UpdateDefault')
    foreach ($property in $policy.PSObject.Properties) {
        if ($names -contains $property.Name -or $property.Name -match '\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5\}$') {
            return 'EdgeUpdatePolicy'
        }
    }
}
function Test-MicrosoftInstaller { param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop)) { throw 'InstallerMissing' }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate) { throw 'InstallerSignatureInvalid' }
    $publisher = $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    if ($publisher -ne 'Microsoft Corporation') { throw 'InstallerPublisherInvalid' }
    $product = (Get-Item -LiteralPath $Path -ErrorAction Stop).VersionInfo.ProductName
    if ($product -notmatch 'Microsoft Edge') { throw 'InstallerProductInvalid' }
}
function Invoke-RuntimeInstall { param([string]$Path)
    Test-MicrosoftInstaller -Path $Path
    $process = Start-Process -FilePath $Path -ArgumentList '/silent /install' -PassThru -ErrorAction Stop
    try {
        if (-not $process.WaitForExit($InstallTimeoutSeconds * 1000)) { throw 'InstallerTimeout' }
        $process.WaitForExit()
        $code = $process.ExitCode
        Write-IRTLog "InstallerExitCode=$code"
        return $code
    } finally { $process.Dispose() }
}
function Wait-RuntimeVerification {
    $deadline = (Get-Date).AddSeconds($VerificationSeconds)
    do {
        $current = Get-RuntimeState
        if ($current.Healthy) { return $current }
        if ((Get-Date) -ge $deadline) { return $current }
        Start-Sleep -Seconds 5
    } while ($true)
}

try {
    $ErrorActionPreference = 'Stop'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    if (-not [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { Exit-Script 1 'Failed | Reason=SystemContextRequired' }
    if ($RuntimeRoots.Count -eq 0) {
        $programFiles = $env:ProgramFiles
        if ([Environment]::Is64BitOperatingSystem) { $programFiles = ${env:ProgramFiles(x86)} }
        $RuntimeRoots = @(Join-Path $programFiles 'Microsoft\EdgeWebView\Application')
    }
    $state = Get-RuntimeState
    if ($state.Healthy) { Exit-Script 0 "Healthy | Version=$($state.Version); Check=FilesVerified" }
    if (Get-ServicingPolicy) { Exit-Script 1 "PolicyManaged | Reason=EdgeUpdatePolicy; Version=$($state.Version)" }
    if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
        $downloadDirectory = Join-Path $env:ProgramFiles ('IntuneRemediations\WebView2Runtime\' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $downloadDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $InstallerPath = Join-Path $downloadDirectory 'MicrosoftEdgeWebview2Setup.exe'
        $oldProtocol = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = $oldProtocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $BootstrapperUri -OutFile $InstallerPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop | Out-Null
        } finally { [Net.ServicePointManager]::SecurityProtocol = $oldProtocol }
    }
    $installerCode = Invoke-RuntimeInstall -Path $InstallerPath
    $state = Wait-RuntimeVerification
    if ($state.Healthy) { Exit-Script 0 "Fixed | Version=$($state.Version); InstallerExitCode=$installerCode; Check=FilesVerified" }
    if (-not $ResetBrokenRegistration -or -not $state.Registered -or $state.Reason -ne 'RuntimeFilesMissing') {
        Exit-Script 1 "Failed | Reason=$($state.Reason); InstallerExitCode=$installerCode; RegistrationReset=False"
    }
    if (@(Get-Process -Name 'msedgewebview2', 'MicrosoftEdgeUpdate', 'setup' -ErrorAction SilentlyContinue).Count -gt 0) {
        Exit-Script 1 'Deferred | Reason=RuntimeOrInstallerInUse; RegistrationReset=False'
    }
    if (Get-ServicingPolicy) { Exit-Script 1 'PolicyManaged | Reason=EdgeUpdatePolicy; RegistrationReset=False' }
    Test-MicrosoftInstaller -Path $InstallerPath
    $state = Get-RuntimeState
    if ($state.Healthy) { Exit-Script 0 "Healthy | Version=$($state.Version); Check=FilesVerified" }
    if (-not $state.Registered -or $state.Reason -ne 'RuntimeFilesMissing') { Exit-Script 1 'Deferred | Reason=RuntimeStateChanged; RegistrationReset=False' }
    $backupDirectory = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
    New-Item -Path $backupDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $backupFile = Join-Path $backupDirectory ('WebView2Runtime_' + [guid]::NewGuid().ToString('N') + '.reg')
    $registryKey = 'HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    $reg = Join-Path $env:SystemRoot 'System32\reg.exe'
    & $reg export $registryKey $backupFile /y /reg:32 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupFile -PathType Leaf)) { throw 'RegistryBackupFailed' }
    $providerKey = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    if ([Environment]::Is64BitOperatingSystem) {
        $providerKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    }
    Remove-Item -LiteralPath $providerKey -Recurse -Force -ErrorAction Stop
    Write-IRTLog 'RegistrationReset=True; BackupCreated=True'
    try {
        $installerCode = Invoke-RuntimeInstall -Path $InstallerPath
        $state = Wait-RuntimeVerification
        if ($state.Healthy) { Exit-Script 0 "Fixed | Version=$($state.Version); InstallerExitCode=$installerCode; RegistrationReset=True" }
    } catch { Write-IRTLog "ReinstallErrorHResult=$($_.Exception.HResult)" 'ERROR' }
    $state = Get-RuntimeState
    if (-not $state.Registered -and @(Get-Process -Name 'MicrosoftEdgeUpdate', 'setup' -ErrorAction SilentlyContinue).Count -eq 0) {
        & $reg import $backupFile /reg:32 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Exit-Script 1 'Failed | Reason=ReinstallAndRegistrationRestoreFailed; BackupCreated=True' }
        Exit-Script 1 'Failed | Reason=ReinstallFailed; RegistrationRestored=True; BackupCreated=True'
    }
    Exit-Script 1 "Failed | Reason=$($state.Reason); RegistrationReset=True; BackupCreated=True"
} catch { Exit-Script 1 "Error: Failed | Reason=ServicingError; HResult=$($_.Exception.HResult)" }
