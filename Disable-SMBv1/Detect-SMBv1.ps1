<#
.SYNOPSIS
  Detection script for SMBv1 on the client and the server side.

.DESCRIPTION
  Reads the SMBv1 client driver start type, the LanmanWorkstation dependency list and the SMBv1 state
  of the SMB server. Reports the SMB1Protocol optional feature state as information.
  Exits 1 if SMBv1 is still available on either side, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$CheckClient = $true
$CheckServer = $true

$PackageName = 'SMBv1'
$Phase       = 'Detect'
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

try {
    $state = Get-Smb1State

    $drift = @()
    if ($CheckClient) {
        if ([string]$state.ClientDriver -ne 'Missing' -and [int]$state.ClientDriver -ne $DisabledStart) { $drift += 'ClientDriver' }
        if ($state.ClientDependency) { $drift += 'ClientDependency' }
    }
    if ($CheckServer -and $state.ServerEnabled) { $drift += 'Server' }

    $summary = "ClientDriver=$($state.ClientDriver); ClientDependency=$($state.ClientDependency); Server=$($state.ServerEnabled); Feature=$($state.FeatureState)"
    if ($drift.Count -gt 0) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch {
    Exit-Script 1 ('Error: AssessmentFailed | Type={0}; HResult={1}' -f $_.Exception.GetType().Name, $_.Exception.HResult)
}
