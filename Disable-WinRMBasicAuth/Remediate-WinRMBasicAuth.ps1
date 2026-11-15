<#
.SYNOPSIS
  Remediation script for WinRM Basic authentication and unencrypted traffic.

.DESCRIPTION
  Backs up the WinRM policy keys, sets AllowBasic and AllowUnencryptedTraffic to 0 for the client and the service, applies the same values to the live WinRM configuration and verifies the result. Exits 0 when Basic authentication and unencrypted traffic are blocked, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $true
$ApplyLiveConfig   = $true
$BackupRoot        = Join-Path $env:ProgramData 'IntuneRemediations\Backup\WinRMBasicAuth'
$ClientPolicyKey   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client'
$ServicePolicyKey  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service'

$PackageName = 'WinRMBasicAuth'
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

function Get-PolicyValue { param([string]$Key, [string]$Name)
    try { $value = (Get-ItemProperty -LiteralPath $Key -Name $Name -ErrorAction Stop).$Name }
    catch { return $null }
    if ($null -eq $value) { return $null }
    return [int]$value
}

function Get-LiveValue { param([string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return $null }
        $value = (Get-Item -LiteralPath $Path -ErrorAction Stop).Value
    }
    catch { return $null }
    if ($null -eq $value) { return $null }
    if ([string]$value -ieq 'true') { return $true }
    if ([string]$value -ieq 'false') { return $false }
    return $null
}

function Test-ServiceRunning {
    $service = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    if ($null -eq $service) { return $false }
    return ($service.Status -eq 'Running')
}

function Get-WinRMState {
    [pscustomobject]@{
        ServiceRunning           = (Test-ServiceRunning)
        ClientBasicPolicy        = (Get-PolicyValue -Key $ClientPolicyKey -Name 'AllowBasic')
        ServiceBasicPolicy       = (Get-PolicyValue -Key $ServicePolicyKey -Name 'AllowBasic')
        ClientUnencryptedPolicy  = (Get-PolicyValue -Key $ClientPolicyKey -Name 'AllowUnencryptedTraffic')
        ServiceUnencryptedPolicy = (Get-PolicyValue -Key $ServicePolicyKey -Name 'AllowUnencryptedTraffic')
        ClientBasicLive          = (Get-LiveValue -Path 'WSMan:\localhost\Client\Auth\Basic')
        ServiceBasicLive         = (Get-LiveValue -Path 'WSMan:\localhost\Service\Auth\Basic')
        ClientUnencryptedLive    = (Get-LiveValue -Path 'WSMan:\localhost\Client\AllowUnencrypted')
        ServiceUnencryptedLive   = (Get-LiveValue -Path 'WSMan:\localhost\Service\AllowUnencrypted')
    }
}

function Get-PolicyText { param($Value)
    if ($null -eq $Value) { return 'Unset' }
    return [string]$Value
}

function Get-LiveText { param($Value)
    if ($null -eq $Value) { return 'Unreadable' }
    if ($Value) { return 'Allowed' }
    return 'Blocked'
}

function Get-ServiceText { param($Running)
    if ($Running) { return 'Running' }
    return 'Stopped'
}

function Format-WinRMState { param($State)
    $policy = 'ClientBasic={0}; ServiceBasic={1}; ClientUnencrypted={2}; ServiceUnencrypted={3}' -f `
        (Get-PolicyText $State.ClientBasicPolicy), (Get-PolicyText $State.ServiceBasicPolicy), `
        (Get-PolicyText $State.ClientUnencryptedPolicy), (Get-PolicyText $State.ServiceUnencryptedPolicy)
    $live = 'LiveBasic={0}/{1}; LiveUnencrypted={2}/{3}' -f `
        (Get-LiveText $State.ClientBasicLive), (Get-LiveText $State.ServiceBasicLive), `
        (Get-LiveText $State.ClientUnencryptedLive), (Get-LiveText $State.ServiceUnencryptedLive)
    return "$policy; $live; Service=$(Get-ServiceText $State.ServiceRunning)"
}

function Test-WinRMDrift { param($State)
    $drift = @()
    if ($null -eq $State.ClientBasicPolicy -or [int]$State.ClientBasicPolicy -ne 0) { $drift += 'ClientBasicPolicy' }
    if ($null -eq $State.ServiceBasicPolicy -or [int]$State.ServiceBasicPolicy -ne 0) { $drift += 'ServiceBasicPolicy' }
    if ($null -eq $State.ClientUnencryptedPolicy -or [int]$State.ClientUnencryptedPolicy -ne 0) { $drift += 'ClientUnencryptedPolicy' }
    if ($null -eq $State.ServiceUnencryptedPolicy -or [int]$State.ServiceUnencryptedPolicy -ne 0) { $drift += 'ServiceUnencryptedPolicy' }
    if ($State.ClientBasicLive -eq $true) { $drift += 'ClientBasicLive' }
    if ($State.ClientUnencryptedLive -eq $true) { $drift += 'ClientUnencryptedLive' }
    if ($State.ServiceRunning -and $State.ServiceBasicLive -eq $true) { $drift += 'ServiceBasicLive' }
    if ($State.ServiceRunning -and $State.ServiceUnencryptedLive -eq $true) { $drift += 'ServiceUnencryptedLive' }
    return $drift
}

function Save-RegistryBackup {
    if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $keys = @(
        @{ Name = 'Client'; Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client' },
        @{ Name = 'Service'; Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service' }
    )
    foreach ($item in $keys) {
        $target = Join-Path $BackupRoot ('{0}-{1}.reg' -f $item.Name, $stamp)
        & reg.exe export $item.Path $target /y | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-IRTLog "Backup of $($item.Name) skipped, key not present" 'WARN' }
    }
}

function Set-PolicyValue { param([string]$Key, [string]$Name)
    if (-not (Test-Path -LiteralPath $Key)) { New-Item -Path $Key -Force | Out-Null }
    $current = (Get-ItemProperty -LiteralPath $Key -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -ne $current -and [int]$current -eq 0) { return $false }
    Set-ItemProperty -LiteralPath $Key -Name $Name -Value 0 -Type DWord -ErrorAction Stop
    Write-IRTLog "Set $Name under $Key to 0, previous value $(Get-PolicyText $current)"
    return $true
}

function Invoke-LiveConfig {
    if ($null -eq (Get-Command -Name winrm.exe -ErrorAction SilentlyContinue)) { return 'WinRMExecMissing' }

    $failed = @()
    $authOff = '@{Basic="false"}'
    $unencryptedOff = '@{AllowUnencrypted="false"}'

    & winrm.exe set 'winrm/config/client/auth' $authOff 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $failed += 'ClientBasic' }

    & winrm.exe set 'winrm/config/client' $unencryptedOff 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $failed += 'ClientUnencrypted' }

    $serviceSkipped = $false
    if (Test-ServiceRunning) {
        & winrm.exe set 'winrm/config/service/auth' $authOff 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { $failed += 'ServiceBasic' }

        & winrm.exe set 'winrm/config/service' $unencryptedOff 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { $failed += 'ServiceUnencrypted' }
    }
    else { $serviceSkipped = $true }

    if ($failed.Count -eq 0 -and -not $serviceSkipped) { return 'Applied' }
    if ($failed.Count -eq 0) { return 'AppliedClientOnly' }
    return ('Partial=' + ($failed -join ','))
}

try {
    $state = Get-WinRMState
    $summary = Format-WinRMState -State $state

    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | $summary" }

    $drift = @(Test-WinRMDrift -State $state)
    if ($drift.Count -eq 0) { Exit-Script 0 "Healthy | $summary" }

    Write-IRTLog "Drift found: $($drift -join ',')"
    Save-RegistryBackup

    $changed = @()
    if (Set-PolicyValue -Key $ClientPolicyKey -Name 'AllowBasic') { $changed += 'ClientBasic' }
    if (Set-PolicyValue -Key $ServicePolicyKey -Name 'AllowBasic') { $changed += 'ServiceBasic' }
    if (Set-PolicyValue -Key $ClientPolicyKey -Name 'AllowUnencryptedTraffic') { $changed += 'ClientUnencrypted' }
    if (Set-PolicyValue -Key $ServicePolicyKey -Name 'AllowUnencryptedTraffic') { $changed += 'ServiceUnencrypted' }

    $liveResult = 'NotRequested'
    if ($ApplyLiveConfig) { $liveResult = Invoke-LiveConfig }

    $after = Get-WinRMState
    $left  = @(Test-WinRMDrift -State $after)

    $result = "Changed=$($changed.Count); LiveApply=$liveResult; $(Format-WinRMState -State $after)"
    if ($left.Count -eq 0) { Exit-Script 0 "Fixed | $result" }
    Exit-Script 1 "Failed | Left=$($left -join ','); $result"
}
catch {
    Exit-Script 1 ('Error: RemediationFailed | Type={0}; HResult={1}' -f $_.Exception.GetType().Name, $_.Exception.HResult)
}
