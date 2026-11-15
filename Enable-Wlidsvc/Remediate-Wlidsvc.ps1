<#
.SYNOPSIS
  Remediation script that restores the Microsoft Account Sign-in Assistant service.

.DESCRIPTION
  Windows Update does not offer feature updates while the Microsoft Account Sign-in Assistant service (wlidsvc) is disabled. Sets the startup mode back to Manual, starts the service and verifies the result. Leaves the service untouched when the PolicyManager value shows an active Intune policy. Exits 0 when the service is enabled again, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceName       = 'wlidsvc'
$ExpectedStartMode = 'Manual'
$StartService      = $true
$PolicyKey         = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Accounts'
$PolicyValueName   = 'AllowMicrosoftAccountSignInAssistant'

$PackageName = 'Wlidsvc'
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
        Exit-Script 0 "PolicyManaged | Service=$ServiceName; StartMode=$($info.StartMode); Policy=Disabled; Action=None"
    }

    $before = $info.StartMode
    if ($before -eq 'Disabled') {
        Set-Service -Name $ServiceName -StartupType $ExpectedStartMode -ErrorAction Stop
        Write-IRTLog "Startup mode changed from $before to $ExpectedStartMode"
    }

    if ($StartService) {
        $current = Get-WlidsvcInfo
        if ($null -ne $current -and $current.State -ne 'Running' -and $current.StartMode -ne 'Disabled') {
            try { Start-Service -Name $ServiceName -ErrorAction Stop }
            catch { Write-IRTLog "Start-Service failed: $($_.Exception.Message)" 'WARN' }
        }
    }

    $after = $null
    for ($i = 0; $i -lt 10; $i++) {
        $after = Get-WlidsvcInfo
        if ($null -eq $after) { break }
        if ($after.StartMode -ne 'Disabled' -and $after.State -eq 'Running') { break }
        Start-Sleep -Seconds 1
    }

    if ($null -eq $after) { Exit-Script 1 "Failed | Service=$ServiceName; Reason=ServiceDisappeared" }
    if ($after.StartMode -eq 'Disabled') {
        Exit-Script 1 "Failed | Service=$ServiceName; StartMode=$($after.StartMode); Expected=$ExpectedStartMode"
    }
    if ($after.State -ne 'Running') {
        Exit-Script 1 "Failed | Service=$ServiceName; StartMode=$($after.StartMode); State=$($after.State); Expected=Running"
    }

    if ($before -eq $after.StartMode) {
        Exit-Script 0 "Healthy | Service=$ServiceName; StartMode=$($after.StartMode); State=$($after.State)"
    }
    Exit-Script 0 "Fixed | Service=$ServiceName; StartMode=$before->$($after.StartMode); State=$($after.State)"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
