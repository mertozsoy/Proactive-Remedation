<#
.SYNOPSIS
  Detection script for a disabled Microsoft Account Sign-in Assistant service.

.DESCRIPTION
  Windows Update needs the Microsoft Account Sign-in Assistant service (wlidsvc) to offer feature updates. Reads the service start mode and the PolicyManager value that Intune writes for the Microsoft account sign-in assistant. Exits 1 if the service is disabled without an active policy, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceName     = 'wlidsvc'
$PolicyKey       = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Accounts'
$PolicyValueName = 'AllowMicrosoftAccountSignInAssistant'

$PackageName = 'Wlidsvc'
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

function Get-WlidsvcInfo {
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if (-not $svc) { return $null }
    [pscustomobject]@{
        StartMode = [string]$svc.StartMode
        State     = [string]$svc.State
        StartName = [string]$svc.StartName
    }
}

function Get-MsaPolicyValue {
    $value = (Get-ItemProperty -LiteralPath $PolicyKey -Name $PolicyValueName -ErrorAction SilentlyContinue).$PolicyValueName
    if ($null -eq $value) { return $null }
    return [int]$value
}

try {
    $info = Get-WlidsvcInfo
    if ($null -eq $info) { Exit-Script 0 "NotApplicable | Service=$ServiceName; Reason=NotFound" }

    $policy = Get-MsaPolicyValue
    if ($null -ne $policy -and $policy -eq 0) {
        Exit-Script 0 "PolicyManaged | Service=$ServiceName; StartMode=$($info.StartMode); Policy=Disabled"
    }

    if ($info.StartMode -eq 'Disabled') {
        Exit-Script 1 "Drift | Service=$ServiceName; StartMode=Disabled; State=$($info.State); FeatureUpdates=Blocked"
    }

    Exit-Script 0 "Healthy | Service=$ServiceName; StartMode=$($info.StartMode); State=$($info.State)"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
