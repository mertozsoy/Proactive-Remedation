<#
.SYNOPSIS
  Remediation script for the default printer setting.

.DESCRIPTION
  Turns off Windows default printer management for the signed-in user, sets the approved printer as default and verifies both values. Exits 0 when the default printer is stable, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedDefaultPrinter                 = ''
$AcceptedDefaultPrinters                = @()
$DisableWindowsDefaultPrinterManagement = $true
$BackupRegistryKey                      = $true
$WindowsKey                             = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'
$WindowsKeyRegPath                      = 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows'
$ManagementValueName                    = 'LegacyDefaultPrinterMode'
$BackupFolder                           = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup'

$PackageName = 'DefaultPrinter'
$Phase       = 'Remediate'
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

function Backup-PrinterKey {
    if (-not $BackupRegistryKey) { return 'Skipped' }
    if (-not (Test-Path -LiteralPath $WindowsKey)) { return 'KeyMissing' }
    if (-not (Test-Path -LiteralPath $BackupFolder)) { New-Item -ItemType Directory -Path $BackupFolder -Force -ErrorAction Stop | Out-Null }
    $backupFile = Join-Path $BackupFolder ('DefaultPrinter_{0}.reg' -f (Get-Date -Format 'yyyyMMddHHmmss'))
    $arguments = @('export', $WindowsKeyRegPath, $backupFile, '/y')
    $process = Start-Process -FilePath 'reg.exe' -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) { throw "reg export failed with exit code $($process.ExitCode)" }
    Write-IRTLog "Backup written to $backupFile"
    return 'Yes'
}

function Set-ManagementOff {
    if (-not (Test-Path -LiteralPath $WindowsKey)) { throw 'Windows key is missing.' }
    New-ItemProperty -LiteralPath $WindowsKey -Name $ManagementValueName -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
}

function Set-ApprovedDefaultPrinter {
    param([string]$PrinterName)
    $printer = Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop |
        Where-Object { $_.Name -eq $PrinterName } |
        Select-Object -First 1
    if ($null -eq $printer) { throw 'Approved printer is not installed.' }
    try {
        $result = Invoke-CimMethod -InputObject $printer -MethodName SetDefaultPrinter -ErrorAction Stop
        if ([int]$result.ReturnValue -eq 0) { return }
        Write-IRTLog "SetDefaultPrinter returned $($result.ReturnValue)" 'WARN'
    }
    catch { Write-IRTLog "SetDefaultPrinter failed: $($_.Exception.HResult)" 'WARN' }
    $network = New-Object -ComObject WScript.Network
    $network.SetDefaultPrinter($PrinterName)
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
    $managementOk = (-not $DisableWindowsDefaultPrinterManagement) -or ($management -eq 'Off')
    $defaultOk = $state.Defaults.Count -eq 1 -and $targets -contains $state.Defaults[0]
    if ($managementOk -and $defaultOk) {
        Exit-Script 0 "Healthy | Default=Approved; Management=$management; Printers=$($state.Count); Action=None"
    }

    $backup = Backup-PrinterKey

    if (-not $managementOk) {
        Set-ManagementOff
        Write-IRTLog 'Windows default printer management set to off'
    }

    $changed = $false
    if (-not $defaultOk) {
        $currentDefault = ''
        if ($state.Defaults.Count -eq 1) { $currentDefault = $state.Defaults[0] }
        if (-not ($currentDefault -and $installedTargets -contains $currentDefault)) {
            Set-ApprovedDefaultPrinter -PrinterName $installedTargets[0]
            $changed = $true
            Write-IRTLog 'Approved default printer set'
        }
    }

    $afterState = Get-PrinterState
    $afterManagement = Get-ManagementState
    $problems = @()
    if ($DisableWindowsDefaultPrinterManagement -and $afterManagement -ne 'Off') { $problems += 'ManagementOn' }
    if ($afterState.Defaults.Count -eq 0) { $problems += 'DefaultMissing' }
    elseif ($afterState.Defaults.Count -gt 1) { $problems += 'DefaultMultiple' }
    elseif ($targets -notcontains $afterState.Defaults[0]) { $problems += 'DefaultMismatch' }

    if ($problems.Count -gt 0) {
        Exit-Script 1 "Failed | Issues=$($problems -join ','); Management=$afterManagement; Printers=$($afterState.Count); Backup=$backup"
    }
    Exit-Script 0 "Fixed | Default=Approved; Management=$afterManagement; Changed=$changed; Backup=$backup"
}
catch { Exit-Script 1 ('Error: Remediation | Stage=Apply; HResult={0}' -f $_.Exception.HResult) }
