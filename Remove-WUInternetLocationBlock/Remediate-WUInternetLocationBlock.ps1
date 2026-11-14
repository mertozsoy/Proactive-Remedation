<#
.SYNOPSIS
  Remediation script for Windows Update policy values that block Microsoft Store and Company Portal installs.

.DESCRIPTION
  Removes DoNotConnectToWindowsUpdateInternetLocations and DisableWindowsUpdateAccess when the device does not use WSUS, then restarts the running update and Store install services. Exits 0 when the values are gone, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$BlockingValues          = @('DoNotConnectToWindowsUpdateInternetLocations', 'DisableWindowsUpdateAccess')
$RemoveWhenWsusConfigured = $false

$PackageName = 'WUInternetLocationBlock'
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

$WuPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$MdmKey      = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update'

function Get-BlockState {
    $wu = Get-ItemProperty -LiteralPath $WuPolicyKey -ErrorAction SilentlyContinue
    $au = Get-ItemProperty -LiteralPath (Join-Path $WuPolicyKey 'AU') -ErrorAction SilentlyContinue
    $mdm = Get-ItemProperty -LiteralPath $MdmKey -ErrorAction SilentlyContinue
    $active = @($BlockingValues | Where-Object { $wu.$_ -eq 1 })
    [pscustomobject]@{
        Active     = $active
        MdmManaged = @($active | Where-Object { $null -ne $mdm.$_ })
        WsusInUse  = ($au.UseWUServer -eq 1 -and -not [string]::IsNullOrWhiteSpace($wu.WUServer))
    }
}

try {
    $state = Get-BlockState
    if ($state.Active.Count -eq 0) { Exit-Script 0 'NoAction | Blocking=None' }
    if ($state.MdmManaged.Count -gt 0) { Exit-Script 1 "Skipped | Reason=MdmManaged; Blocking=$($state.Active -join ',')" }
    if ($state.WsusInUse -and -not $RemoveWhenWsusConfigured) { Exit-Script 1 "Skipped | Reason=WsusInUse; Blocking=$($state.Active -join ',')" }

    foreach ($name in $state.Active) {
        Remove-ItemProperty -LiteralPath $WuPolicyKey -Name $name -Force -ErrorAction Stop
        Write-IRTLog "Removed policy value: $name"
    }

    $restarted = New-Object System.Collections.Generic.List[string]
    foreach ($svcName in 'wuauserv', 'InstallService') {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            try { Restart-Service -Name $svcName -Force -ErrorAction Stop; $restarted.Add($svcName) }
            catch { Write-IRTLog "Restart-Service $svcName : $($_.Exception.Message)" 'WARN' }
        }
    }

    $after = Get-BlockState
    $summary = 'Removed={0}; Restarted={1}' -f ($state.Active -join ','), ($(if ($restarted.Count) { $restarted -join ',' } else { 'None' }))
    if ($after.Active.Count -gt 0) { Exit-Script 1 "Failed (StillSet=$($after.Active -join ',')) | $summary" }
    Exit-Script 0 "Remediated | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
