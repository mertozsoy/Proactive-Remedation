<#
.SYNOPSIS
  Remediation script that turns Windows Defender Firewall profiles back on.

.DESCRIPTION
  Turns local profiles on and starts MpsSvc when needed. Optional confirmed stale EnableFirewall=0 cleanup requires a registry backup and a non-domain device. Domain policy values are never removed. Verifies ActiveStore and exits 0 only when all profiles are on and MpsSvc is running, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ProfileNames            = @('Domain', 'Private', 'Public')
$PolicyRoot              = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall'
$PolicyKeyNames          = @{ Domain = 'DomainProfile'; Private = 'PrivateProfile'; Public = 'PublicProfile' }
$ServiceName             = 'MpsSvc'
$RemoveLocalPolicyValue  = $false
$BackupRoot              = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'FirewallState'
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

function Get-FirewallServiceState {
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
    if ($null -eq $service) { return 'Missing' }
    if ($service.StartMode -eq 'Disabled') { return 'Disabled' }
    if ($service.State -ne 'Running') { return [string]$service.State }
    'Running'
}

function Get-FirewallState {
    $profileObjects = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    foreach ($name in $ProfileNames) {
        $profileItem = $profileObjects | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        $enabled = 'Unknown'
        if ($profileItem) { $enabled = [string]$profileItem.Enabled }
        if ($enabled -notin @('True', 'False')) { throw "Profile state unavailable: $name" }

        $key = Join-Path $PolicyRoot $PolicyKeyNames[$name]
        $policyValue = $null
        if (Test-Path -LiteralPath $key) {
            $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            if ($null -ne $item.EnableFirewall) { $policyValue = [int]$item.EnableFirewall }
        }

        $source = 'Unspecified'
        if ($null -ne $policyValue -and $policyValue -eq 0) { $source = 'Policy' }

        [pscustomobject]@{
            Name        = $name
            Enabled     = $enabled
            Off         = ($enabled -eq 'False')
            Source      = $source
            PolicyKey   = $key
            PolicyValue = $policyValue
        }
    }
}

function Format-FirewallState {
    param($State)
    (@($State | ForEach-Object {
        if ($_.Off) { '{0}=Off({1})' -f $_.Name, $_.Source } else { '{0}={1}' -f $_.Name, $_.Enabled }
    }) -join '; ')
}

try {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($null -eq $computerSystem.PartOfDomain) { throw 'Domain membership unavailable' }
    $isDomainJoined = [bool]$computerSystem.PartOfDomain
    $serviceState = Get-FirewallServiceState
    if ($serviceState -eq 'Missing') { Exit-Script 1 'Failed | Service=MpsSvc missing' }
    $serviceChanged = ($serviceState -ne 'Running')
    if ($serviceState -eq 'Disabled' -or $serviceState -eq 'Stopped') {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
        if ($service.StartMode -eq 'Disabled') {
            Set-Service -Name $ServiceName -StartupType Automatic -ErrorAction Stop
            Write-IRTLog 'Service start mode set to Automatic'
        }
        if ($service.State -ne 'Running') {
            Start-Service -Name $ServiceName -ErrorAction Stop
            Write-IRTLog 'Service started'
        }
    }

    $serviceState = Get-FirewallServiceState
    if ($serviceState -ne 'Running') { Exit-Script 1 "Failed | Profiles=NotQueried; Service=$serviceState" }
    $initial = @(Get-FirewallState)
    if (@($initial | Where-Object { $_.Off }).Count -eq 0) {
        if ($serviceChanged) { Exit-Script 0 "Fixed | $(Format-FirewallState -State $initial); Service=$serviceState" }
        Exit-Script 0 "Healthy | $(Format-FirewallState -State $initial); Service=$serviceState"
    }

    $removed = @()
    $blocked = @()
    foreach ($name in $ProfileNames) {
        if (-not ($initial | Where-Object { $_.Name -eq $name -and $_.Off })) { continue }
        $key = Join-Path $PolicyRoot $PolicyKeyNames[$name]
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        if ($null -eq $item.EnableFirewall) { continue }
        if ([int]$item.EnableFirewall -ne 0) { continue }

        $mayRemove = $RemoveLocalPolicyValue
        if ($isDomainJoined) { $mayRemove = $false }
        if (-not $mayRemove) {
            $blocked += $name
            Write-IRTLog "Policy value preserved for $name; DomainJoined=$isDomainJoined; CleanupEnabled=$RemoveLocalPolicyValue"
            continue
        }

        if (-not (Test-Path -LiteralPath $BackupRoot)) { $null = New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop }
        $file = Join-Path $BackupRoot ('FirewallPolicy-{0}-{1}.reg' -f $name, [guid]::NewGuid().ToString('N'))
        & reg.exe export ('HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\' + $PolicyKeyNames[$name]) $file /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
            $blocked += $name
            Write-IRTLog "reg export failed for $name with exit code $LASTEXITCODE" 'WARN'
            continue
        }

        Remove-ItemProperty -LiteralPath $key -Name 'EnableFirewall' -ErrorAction Stop
        $removed += $name
        Write-IRTLog "EnableFirewall value removed for $name, backup $file"
    }

    foreach ($state in $initial) {
        if (-not $state.Off) { continue }
        if ($blocked -contains $state.Name) { continue }
        Set-NetFirewallProfile -PolicyStore PersistentStore -Name $state.Name -Enabled True -ErrorAction Stop
    }

    $final        = @(Get-FirewallState)
    $serviceState = Get-FirewallServiceState
    $detail       = ''
    if ($removed.Count -gt 0) { $detail += "; PolicyRemoved=$($removed -join '/')" }
    if ($blocked.Count -gt 0) { $detail += "; PolicyBlocked=$($blocked -join '/')" }

    if (@($final | Where-Object { $_.Off }).Count -eq 0 -and $serviceState -eq 'Running') {
        Exit-Script 0 "Fixed | $(Format-FirewallState -State $final); Service=$serviceState$detail; Backup=%ProgramData%\IntuneRemediations\Backup"
    }
    Exit-Script 1 "Failed | $(Format-FirewallState -State $final); Service=$serviceState$detail"
}
catch { Exit-Script 1 ('Error | Detail=' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
