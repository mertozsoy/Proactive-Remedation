<#
.SYNOPSIS
  Detection script for WinRM Basic authentication and unencrypted traffic.

.DESCRIPTION
  Reads the WinRM client and service policy values and the live WinRM configuration. Exits 1 if Basic authentication or unencrypted traffic is allowed on either side, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ClientPolicyKey  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client'
$ServicePolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service'

$PackageName = 'WinRMBasicAuth'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
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

try {
    $state   = Get-WinRMState
    $summary = Format-WinRMState -State $state
    $drift   = @(Test-WinRMDrift -State $state)

    if ($drift.Count -gt 0) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
