<#
.SYNOPSIS
  Remediation script for new Teams versions below an approved minimum.

.DESCRIPTION
  Defaults to report mode. When enabled, runs an administrator-staged, SHA256-pinned Teams bootstrapper with -p and verifies all returned MSTeams versions. Exits 0 only for verified success or no applicable work, 1 for report-only drift, deferral, configuration errors or failed verification.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumVersion = ''
$EnableRemediation = $false
$BootstrapperPath = ''
$BootstrapperSha256 = ''

$PackageName = 'NewTeams'
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

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Error | Reason=Requires64BitPowerShell' }
    if ($MinimumVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { Exit-Script 1 'Error | Reason=ConfigureMinimumVersion' }
    $minimum = [version]$MinimumVersion
    $apps = @(Get-AppxPackage -AllUsers -Name 'MSTeams' -PackageTypeFilter Main -ErrorAction Stop)
    if ($apps.Count -eq 0) { Exit-Script 0 'NotApplicable | App=MSTeams; Registrations=0' }
    $below = @($apps | Where-Object { [version]$_.Version -lt $minimum }).Count
    if ($below -eq 0) { Exit-Script 0 "Healthy | App=MSTeams; Minimum=$minimum; BelowMinimum=0" }
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | App=MSTeams; Minimum=$minimum; BelowMinimum=$below; Action=Disabled" }
    $running = @(Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -in @('ms-teams', 'teamsbootstrapper') })
    if ($running.Count -gt 0) { Exit-Script 1 'Deferred | App=MSTeams; Reason=TeamsOrInstallerRunning; Action=None' }
    if ($BootstrapperPath -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetFileName($BootstrapperPath) -ne 'teamsbootstrapper.exe') {
        Exit-Script 1 'Error | Reason=ConfigureLocalBootstrapperPath'
    }
    if ($BootstrapperSha256 -notmatch '^[A-Fa-f0-9]{64}$') { Exit-Script 1 'Error | Reason=ConfigureBootstrapperSha256' }
    if (-not (Test-Path -LiteralPath $BootstrapperPath -PathType Leaf -ErrorAction Stop)) { Exit-Script 1 'Error | Reason=BootstrapperMissing' }
    $hash = Get-FileHash -LiteralPath $BootstrapperPath -Algorithm SHA256 -ErrorAction Stop
    if ($hash.Hash -ne $BootstrapperSha256) { Exit-Script 1 'Error | Reason=BootstrapperHashMismatch' }
    Write-IRTLog "Update requested | Minimum=$minimum; BelowMinimum=$below"
    $process = Start-Process -FilePath $BootstrapperPath -ArgumentList '-p' -WindowStyle Hidden -PassThru -ErrorAction Stop
    if (-not $process.WaitForExit(600000)) { Exit-Script 1 'Pending | App=MSTeams; Reason=InstallerTimeout; Action=NotTerminated' }
    $process.Refresh()
    $installerCode = $process.ExitCode
    if ($installerCode -ne 0) { Exit-Script 1 "Failed | App=MSTeams; InstallerExit=$installerCode; Action=ReviewDeploymentLogs" }
    $after = @(Get-AppxPackage -AllUsers -Name 'MSTeams' -PackageTypeFilter Main -ErrorAction Stop)
    if ($after.Count -eq 0) { Exit-Script 1 'Failed | App=MSTeams; Reason=MissingAfterUpdate' }
    $remaining = @($after | Where-Object { [version]$_.Version -lt $minimum }).Count
    if ($remaining -gt 0) { Exit-Script 1 "Pending | App=MSTeams; Minimum=$minimum; BelowMinimum=$remaining; InstallerExit=$installerCode" }
    Exit-Script 0 "Fixed | App=MSTeams; Minimum=$minimum; BelowMinimum=0; InstallerExit=$installerCode"
}
catch { Exit-Script 1 ('Error | Operation=TeamsUpdate; HResult={0}' -f $_.Exception.HResult) }
