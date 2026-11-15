<#
.SYNOPSIS
  Detection script for the default printer setting.

.DESCRIPTION
  Compares the default printer of the signed-in user and the Windows default printer management state with the approved target. Exits 1 if the default printer can drift again, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedDefaultPrinter                 = ''
$AcceptedDefaultPrinters                = @()
$DisableWindowsDefaultPrinterManagement = $true
$WindowsKey                             = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'
$ManagementValueName                    = 'LegacyDefaultPrinterMode'

$PackageName = 'DefaultPrinter'
$Phase       = 'Detect'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-TargetPrinterList {
    $list = @()
    $primary = [string]$ExpectedDefaultPrinter
    if (-not [string]::IsNullOrWhiteSpace($primary)) { $list += $primary.Trim() }
    foreach ($name in $AcceptedDefaultPrinters) {
        $candidate = ([string]$name).Trim()
        if ($candidate -and $list -notcontains $candidate) { $list += $candidate }
    }
    return $list
}

function Get-PrinterState {
    $printers = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop)
    $names = @($printers | ForEach-Object { [string]$_.Name })
    $defaults = @($printers | Where-Object { $_.Default -eq $true } | ForEach-Object { [string]$_.Name })
    return [pscustomobject]@{ Count = $names.Count; Names = $names; Defaults = $defaults }
}

function Get-ManagementState {
    $value = (Get-ItemProperty -LiteralPath $WindowsKey -Name $ManagementValueName -ErrorAction SilentlyContinue).$ManagementValueName
    if ($null -eq $value) { return 'Unset' }
    if ([int]$value -eq 1) { return 'Off' }
    return 'On'
}

try {
    $ErrorActionPreference = 'Stop'

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User'
    }

    $targets = @(Get-TargetPrinterList)
    if ($targets.Count -eq 0) { Exit-Script 0 'NotApplicable | Targets=None' }

    $state = Get-PrinterState
    if ($state.Count -eq 0) { Exit-Script 0 'NotApplicable | Printers=0' }

    $installedTargets = @($targets | Where-Object { $state.Names -contains $_ })
    if ($installedTargets.Count -eq 0) {
        Exit-Script 0 "NotApplicable | Reason=TargetPrinterNotInstalled; Printers=$($state.Count)"
    }

    $management = Get-ManagementState
    $issues = @()
    if ($DisableWindowsDefaultPrinterManagement -and $management -ne 'Off') { $issues += 'ManagementOn' }

    if ($state.Defaults.Count -eq 0) {
        $issues += 'DefaultMissing'
        $defaultLabel = 'Missing'
    }
    elseif ($state.Defaults.Count -gt 1) {
        $issues += 'DefaultMultiple'
        $defaultLabel = 'Multiple'
    }
    elseif ($targets -notcontains $state.Defaults[0]) {
        $issues += 'DefaultMismatch'
        $defaultLabel = 'Other'
    }
    else {
        $defaultLabel = 'Approved'
    }

    if ($issues.Count -eq 0) {
        Exit-Script 0 "Healthy | Default=$defaultLabel; Management=$management; Printers=$($state.Count)"
    }
    Exit-Script 1 "Drift | Issues=$($issues -join ','); Default=$defaultLabel; Management=$management; Printers=$($state.Count)"
}
catch { Exit-Script 1 ('Error: Detection | Stage=Read; HResult={0}' -f $_.Exception.HResult) }
