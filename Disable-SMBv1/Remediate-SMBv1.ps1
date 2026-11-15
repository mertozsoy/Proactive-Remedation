<#
.SYNOPSIS
  Remediation script for SMBv1 on the client and the server side.

.DESCRIPTION
  Backs up the service keys, sets the SMBv1 client driver to disabled, removes MRxSMB10 from the
  LanmanWorkstation dependency list and turns off the SMBv1 server. Optionally removes the SMB1Protocol
  optional feature. Verifies both sides and exits 0 when SMBv1 is off, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $true
$RemoveSmb1Feature = $false
$BackupRoot        = Join-Path $env:ProgramData 'IntuneRemediations\Backup\SMBv1'

$PackageName = 'SMBv1'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

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

$DisabledStart   = 4
$Smb1DriverName  = 'MRxSMB10'
$Smb1FeatureName = 'SMB1Protocol'
$ClientDriverKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10'
$WorkstationKey  = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation'
$ServerParamsKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'

function Get-Smb1State {
    $state = [pscustomobject]@{
        ClientDriver     = 'Missing'
        ClientDependency = $false
        ServerEnabled    = $false
        FeatureState     = 'Unknown'
    }

    if (Test-Path -LiteralPath $ClientDriverKey) {
        $start = (Get-ItemProperty -LiteralPath $ClientDriverKey -Name 'Start' -ErrorAction SilentlyContinue).Start
        if ($null -ne $start) { $state.ClientDriver = [int]$start }
    }

    $depends = @((Get-ItemProperty -LiteralPath $WorkstationKey -Name 'DependOnService' -ErrorAction SilentlyContinue).DependOnService)
    foreach ($dep in $depends) {
        if ($dep -and $dep.Trim() -ieq $Smb1DriverName) { $state.ClientDependency = $true }
    }

    $smbCommand = Get-Command -Name Get-SmbServerConfiguration -ErrorAction SilentlyContinue
    if ($null -ne $smbCommand) {
        $state.ServerEnabled = [bool](Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol
    }
    else {
        $value = (Get-ItemProperty -LiteralPath $ServerParamsKey -Name 'SMB1' -ErrorAction SilentlyContinue).SMB1
        if ($null -ne $value) { $state.ServerEnabled = ([int]$value -ne 0) }
    }

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $Smb1FeatureName -ErrorAction Stop
        $state.FeatureState = [string]$feature.State
    }
    catch { }

    return $state
}

function Test-Smb1Drift { param($State)
    $drift = @()
    if ([string]$State.ClientDriver -ne 'Missing' -and [int]$State.ClientDriver -ne $DisabledStart) { $drift += 'ClientDriver' }
    if ($State.ClientDependency) { $drift += 'ClientDependency' }
    if ($State.ServerEnabled) { $drift += 'Server' }
    return $drift
}

function Save-RegistryBackup {
    if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $keys = @(
        @{ Name = 'mrxsmb10'; Key = 'HKLM\SYSTEM\CurrentControlSet\Services\mrxsmb10' },
        @{ Name = 'LanmanWorkstation'; Key = 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation' },
        @{ Name = 'LanmanServerParameters'; Key = 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' }
    )
    foreach ($item in $keys) {
        $target = Join-Path $BackupRoot ("{0}-{1}.reg" -f $item.Name, $stamp)
        & reg.exe export $item.Key $target /y | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-IRTLog "reg export $($item.Name) failed with code $LASTEXITCODE" 'WARN' }
    }
}

function Disable-Smb1Client {
    $changed = $false

    if (Test-Path -LiteralPath $ClientDriverKey) {
        $start = (Get-ItemProperty -LiteralPath $ClientDriverKey -Name 'Start' -ErrorAction SilentlyContinue).Start
        if ($null -ne $start -and [int]$start -ne $DisabledStart) {
            Set-ItemProperty -LiteralPath $ClientDriverKey -Name 'Start' -Value $DisabledStart -Type DWord -ErrorAction Stop
            $changed = $true
            Write-IRTLog "Set mrxsmb10 Start to $DisabledStart, previous value $start"
        }
    }

    $depends = @((Get-ItemProperty -LiteralPath $WorkstationKey -Name 'DependOnService' -ErrorAction SilentlyContinue).DependOnService)
    $kept = @($depends | Where-Object { $_ -and $_.Trim() -ine $Smb1DriverName })
    if ($kept.Count -gt 0 -and $kept.Count -ne $depends.Count) {
        Set-ItemProperty -LiteralPath $WorkstationKey -Name 'DependOnService' -Value $kept -Type MultiString -ErrorAction Stop
        $changed = $true
        Write-IRTLog "Removed $Smb1DriverName from the LanmanWorkstation dependency list"
    }

    return $changed
}

function Disable-Smb1Server {
    $changed = $false
    $smbCommand = Get-Command -Name Get-SmbServerConfiguration -ErrorAction SilentlyContinue

    if ($null -ne $smbCommand) {
        $config = Get-SmbServerConfiguration -ErrorAction Stop
        if ($config.EnableSMB1Protocol) {
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Confirm:$false -ErrorAction Stop
            $changed = $true
            Write-IRTLog 'Disabled the SMBv1 server'
        }
        return $changed
    }

    $value = (Get-ItemProperty -LiteralPath $ServerParamsKey -Name 'SMB1' -ErrorAction SilentlyContinue).SMB1
    if ($null -ne $value -and [int]$value -ne 0) {
        Set-ItemProperty -LiteralPath $ServerParamsKey -Name 'SMB1' -Value 0 -Type DWord -ErrorAction Stop
        $changed = $true
        Write-IRTLog 'Set the LanmanServer SMB1 value to 0'
    }

    return $changed
}

function Remove-Smb1Feature {
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $Smb1FeatureName -ErrorAction Stop
        if ($feature.State -eq 'Enabled') {
            Disable-WindowsOptionalFeature -Online -FeatureName $Smb1FeatureName -NoRestart -ErrorAction Stop | Out-Null
            Write-IRTLog "Disabled the $Smb1FeatureName optional feature"
            return $true
        }
    }
    catch {
        Write-IRTLog "Disable $Smb1FeatureName feature: $($_.Exception.Message)" 'WARN'
    }
    return $false
}

try {
    $state = Get-Smb1State
    $summary = "ClientDriver=$($state.ClientDriver); ClientDependency=$($state.ClientDependency); Server=$($state.ServerEnabled); Feature=$($state.FeatureState)"

    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | $summary" }

    $drift = @(Test-Smb1Drift -State $state)
    if ($drift.Count -eq 0) { Exit-Script 0 "Healthy | $summary" }

    Write-IRTLog "Drift found: $($drift -join ',')"
    Save-RegistryBackup

    $clientChanged  = Disable-Smb1Client
    $serverChanged  = Disable-Smb1Server
    $featureChanged = $false
    if ($RemoveSmb1Feature) { $featureChanged = Remove-Smb1Feature }

    $after = Get-Smb1State
    $left  = @(Test-Smb1Drift -State $after)

    $restart = 'NotRequired'
    if ($clientChanged -or $featureChanged) { $restart = 'Required' }

    $result = "ClientDriver=$($after.ClientDriver); ClientDependency=$($after.ClientDependency); Server=$($after.ServerEnabled); Restart=$restart"
    if ($left.Count -eq 0) { Exit-Script 0 "Fixed | $result" }
    Exit-Script 1 "Failed | Left=$($left -join ','); $result"
}
catch {
    Exit-Script 1 ('Error: RemediationFailed | Type={0}; HResult={1}' -f $_.Exception.GetType().Name, $_.Exception.HResult)
}
