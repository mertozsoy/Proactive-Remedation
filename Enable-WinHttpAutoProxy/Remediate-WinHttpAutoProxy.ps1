<#
.SYNOPSIS
  Remediation script that puts the WinHTTP Auto-Proxy service back to Manual and starts the connection manager.

.DESCRIPTION
  Exports the service key, sets the start type of WinHttpAutoProxySvc to Manual, starts the service and Windows Connection Manager, then verifies the result. Exits 0 when the start type is Manual and the connection manager runs, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceName            = 'WinHttpAutoProxySvc'
$ConnectionsServiceName = 'WcmSvc'
$RequireDependency      = $true
$CheckConnectionManager = $true
$ManagedByPolicy        = $false
$StartAutoProxyService  = $true
$StartConnectionManager = $true
$BackupRoot             = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'WinHttpAutoProxy'
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

function Get-ServiceRecord {
    param([string]$Name)
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($null -eq $service) { return $null }
    return [pscustomobject]@{ StartMode = [string]$service.StartMode; State = [string]$service.State }
}

function Get-DependencyPresent {
    $value = $null
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$ConnectionsServiceName"
        $value = (Get-ItemProperty -LiteralPath $path -Name 'DependOnService' -ErrorAction Stop).DependOnService
    }
    catch { return $false }
    if ($null -eq $value) { return $false }
    return (@($value) -contains $ServiceName)
}

function Backup-ServiceKey {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    if (-not (Test-Path -LiteralPath $BackupRoot)) { $null = New-Item -Path $BackupRoot -ItemType Directory -Force -ErrorAction Stop }
    $file = Join-Path $BackupRoot "$ServiceName-$stamp.reg"
    $null = & reg.exe export "HKLM\SYSTEM\CurrentControlSet\Services\$ServiceName" $file /y
    if ($LASTEXITCODE -ne 0) { Write-IRTLog "Service key export returned $LASTEXITCODE" 'WARN' }
    else { Write-IRTLog "Service key exported to $file" }
}

try {
    if ($ManagedByPolicy) { Exit-Script 0 'NotApplicable | Reason=ManagedByPolicy; Action=None' }

    $service = Get-ServiceRecord -Name $ServiceName
    if ($null -eq $service) { Exit-Script 0 "NotApplicable | Reason=ServiceMissing; Service=$ServiceName" }

    $connection = Get-ServiceRecord -Name $ConnectionsServiceName
    $connectionState = 'Missing'
    if ($null -ne $connection) { $connectionState = $connection.State }

    $dependency = Get-DependencyPresent

    $fixStartType = $service.StartMode -eq 'Disabled'
    $fixConnection = $CheckConnectionManager -and $null -ne $connection -and $dependency -and $connection.State -ne 'Running'

    if ($fixStartType -and $RequireDependency -and -not $dependency) {
        Exit-Script 0 "NotApplicable | Service=Disabled; Wcm=$connectionState; Dependency=False; Reason=NoDependency"
    }

    if (-not $fixStartType -and -not $fixConnection) {
        Exit-Script 0 "Healthy | Service=$($service.StartMode); Wcm=$connectionState; Dependency=$dependency"
    }

    $changes = @()
    $autoProxyAction = 'NotNeeded'
    $connectionAction = 'NotNeeded'

    if ($fixStartType) {
        Backup-ServiceKey
        Set-Service -Name $ServiceName -StartupType Manual -ErrorAction Stop
        $changes += 'StartType'
        Write-IRTLog 'Start type set to Manual'
    }

    if ($StartAutoProxyService) {
        $current = Get-ServiceRecord -Name $ServiceName
        if ($null -ne $current -and $current.State -ne 'Running') {
            try {
                Start-Service -Name $ServiceName -ErrorAction Stop
                $autoProxyAction = 'Started'
                $changes += 'Service'
                Write-IRTLog 'Auto-Proxy service started'
            }
            catch {
                $autoProxyAction = 'Failed'
                Write-IRTLog "Auto-Proxy service start failed: $($_.Exception.Message)" 'WARN'
            }
        }
    }

    if ($fixConnection -and $StartConnectionManager) {
        try {
            Start-Service -Name $ConnectionsServiceName -ErrorAction Stop
            $connectionAction = 'Started'
            $changes += 'ConnectionManager'
            Write-IRTLog 'Windows Connection Manager started'
        }
        catch {
            $connectionAction = 'Failed'
            Write-IRTLog "Connection Manager start failed: $($_.Exception.Message)" 'WARN'
        }
    }

    $after = Get-ServiceRecord -Name $ServiceName
    $connectionAfter = Get-ServiceRecord -Name $ConnectionsServiceName
    $connectionAfterState = 'Missing'
    if ($null -ne $connectionAfter) { $connectionAfterState = $connectionAfter.State }

    $changed = 'None'
    if ($changes.Count -gt 0) { $changed = $changes -join ',' }

    $startModeAfter = 'Missing'
    if ($null -ne $after) { $startModeAfter = $after.StartMode }

    if ($startModeAfter -eq 'Disabled' -or $startModeAfter -eq 'Missing') {
        Exit-Script 1 "Failed | Service=$startModeAfter; Wcm=$connectionAfterState; Changed=$changed; AutoProxy=$autoProxyAction; WcmAction=$connectionAction"
    }

    if ($fixConnection -and $connectionAction -eq 'Failed') {
        Exit-Script 1 "Failed | Service=$startModeAfter; Wcm=$connectionAfterState; Changed=$changed; AutoProxy=$autoProxyAction; WcmAction=$connectionAction"
    }

    Exit-Script 0 "Fixed | Service=$startModeAfter; Wcm=$connectionAfterState; Dependency=$dependency; Changed=$changed; AutoProxy=$autoProxyAction; WcmAction=$connectionAction"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
