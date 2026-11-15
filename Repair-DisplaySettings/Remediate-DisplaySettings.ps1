<#
.SYNOPSIS
  Remediation script that restores the Connected Devices Platform start types so Display settings load again.

.DESCRIPTION
  Backs up the service keys, sets CDPSvc, the CDPUserSvc template and every CDPUserSvc_* instance to Automatic and starts CDPSvc when it is stopped. The EnableCdp policy is reported and only removed when the switch is on. Exits 0 when no start type drift is left, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RequiredStartType = 2
$ServiceNames      = @('CDPSvc', 'CDPUserSvc')
$ServiceKeyRoot    = 'HKLM:\SYSTEM\CurrentControlSet\Services'
$InstancePrefix    = 'CDPUserSvc_'
$PolicyKeyPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
$PolicyValueName   = 'EnableCdp'
$BackupPath        = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
$StartCdpService   = $true
$ClearCdpPolicy    = $false

$PackageName = 'DisplaySettings'
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

function Get-StartType { param([string]$ServiceName)
    $path = Join-Path $ServiceKeyRoot $ServiceName
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $path -Name Start -ErrorAction SilentlyContinue
    if ($null -eq $item) { return -1 }
    return [int]$item.Start
}

function Get-CdpInstanceName {
    @(Get-ChildItem -LiteralPath $ServiceKeyRoot -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName.StartsWith($InstancePrefix) } |
        ForEach-Object { $_.PSChildName })
}

function Get-CdpPolicyState {
    $item = Get-ItemProperty -LiteralPath $PolicyKeyPath -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 'NotConfigured' }
    if ($null -eq $item.PSObject.Properties[$PolicyValueName]) { return 'NotConfigured' }
    if ([int]$item.PSObject.Properties[$PolicyValueName].Value -eq 0) { return 'Disallowed' }
    return 'Allowed'
}

function Backup-RegistryKey { param([string]$KeyPath)
    if (-not (Test-Path -LiteralPath $KeyPath)) { return $false }
    if (-not (Test-Path -LiteralPath $BackupPath)) {
        $null = New-Item -Path $BackupPath -ItemType Directory -Force -ErrorAction Stop
    }
    $regPath = $KeyPath -replace '^HKLM:\\', 'HKLM\'
    $name = ($regPath -replace '[\\:]', '_')
    $file = Join-Path $BackupPath ('{0}_{1}.reg' -f $name, (Get-Date -Format 'yyyyMMddHHmmss'))
    $null = & reg.exe export $regPath $file /y 2>&1
    if ($LASTEXITCODE -ne 0) { Write-IRTLog "BackupFailed | Key=$regPath; ExitCode=$LASTEXITCODE" 'WARN' }
    return ($LASTEXITCODE -eq 0)
}

function Set-ServiceStartType { param([string]$ServiceName, [int]$Value)
    $path = Join-Path $ServiceKeyRoot $ServiceName
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    Set-ItemProperty -LiteralPath $path -Name Start -Value $Value -Type DWord -ErrorAction Stop
    return $true
}

try {
    $serviceDrift = @()
    foreach ($name in $ServiceNames) {
        $start = Get-StartType -ServiceName $name
        if ($null -eq $start) { continue }
        if ($start -ne $RequiredStartType) { $serviceDrift += $name }
    }

    $instances = @(Get-CdpInstanceName)
    $instanceDrift = @()
    foreach ($instance in $instances) {
        $start = Get-StartType -ServiceName $instance
        if ($start -ne $RequiredStartType) { $instanceDrift += $instance }
    }

    $policy = Get-CdpPolicyState
    $cdpService = Get-Service -Name 'CDPSvc' -ErrorAction SilentlyContinue
    $serviceStopped = ($null -ne $cdpService -and $cdpService.Status -ne 'Running')

    if ($serviceDrift.Count -eq 0 -and $instanceDrift.Count -eq 0 -and -not $serviceStopped -and $policy -ne 'Disallowed') {
        Exit-Script 0 "Healthy | Services=Automatic; Instances=$($instances.Count); Policy=$policy"
    }

    $changed = 0
    foreach ($name in $serviceDrift) {
        $null = Backup-RegistryKey -KeyPath (Join-Path $ServiceKeyRoot $name)
        if (Set-ServiceStartType -ServiceName $name -Value $RequiredStartType) {
            $changed++
            Write-IRTLog "StartTypeSet | Name=$name; Value=$RequiredStartType"
        }
    }

    foreach ($instance in $instanceDrift) {
        if (Set-ServiceStartType -ServiceName $instance -Value $RequiredStartType) {
            $changed++
            Write-IRTLog "InstanceStartTypeSet | Name=$instance; Value=$RequiredStartType"
        }
    }

    if ($StartCdpService -and $serviceStopped) {
        try {
            Start-Service -Name 'CDPSvc' -ErrorAction Stop
            $changed++
            Write-IRTLog 'ServiceStarted | Name=CDPSvc'
        }
        catch {
            Write-IRTLog "ServiceStartFailed | Name=CDPSvc; HResult=$($_.Exception.HResult)" 'WARN'
        }
    }

    if ($policy -eq 'Disallowed' -and $ClearCdpPolicy) {
        $null = Backup-RegistryKey -KeyPath $PolicyKeyPath
        Remove-ItemProperty -LiteralPath $PolicyKeyPath -Name $PolicyValueName -ErrorAction Stop
        $changed++
        Write-IRTLog 'PolicyCleared | Name=EnableCdp'
    } elseif ($policy -eq 'Disallowed') {
        Write-IRTLog 'PolicyBlocked | Name=EnableCdp; Action=None' 'WARN'
    }

    $remaining = @()
    foreach ($name in $ServiceNames) {
        $start = Get-StartType -ServiceName $name
        if ($null -ne $start -and $start -ne $RequiredStartType) { $remaining += ('{0}={1}' -f $name, $start) }
    }
    $instanceRemaining = 0
    foreach ($instance in @(Get-CdpInstanceName)) {
        $start = Get-StartType -ServiceName $instance
        if ($start -ne $RequiredStartType) { $instanceRemaining++ }
    }

    $policyAfter = Get-CdpPolicyState
    $summary = 'Changed={0}; Instances={1}; Policy={2}' -f $changed, @(Get-CdpInstanceName).Count, $policyAfter
    if ($remaining.Count -gt 0 -or $instanceRemaining -gt 0) {
        Exit-Script 1 "Failed | $summary; Remaining=$(@($remaining) -join ','); InstanceDrift=$instanceRemaining"
    }
    if ($policyAfter -eq 'Disallowed') {
        Exit-Script 0 "Fixed | $summary; Action=CheckCdpPolicy; Restart=Required"
    }
    Exit-Script 0 "Fixed | $summary; Restart=Required"
}
catch { Exit-Script 1 "Error: Failed | Operation=Remediate; HResult=$($_.Exception.HResult)" }
