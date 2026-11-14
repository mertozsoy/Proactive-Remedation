<#
.SYNOPSIS
  Remediation script for disabled Microsoft Store deployment services.

.DESCRIPTION
  Changes disabled InstallService, ClipSVC and AppXSvc services to Manual and requests an InstallService start after repairs. Leaves other enabled start modes and policy-managed exclusions unchanged. Exits 0 when configuration is verified and 1 on failure or blocked repair. Does not bypass protected-service permissions.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PolicyManagedServices = @()
$CimTimeoutSeconds = 30

$PackageName = 'StoreServices'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
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

try {
    $ErrorActionPreference = 'Stop'
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec $CimTimeoutSeconds
    if ($os.ProductType -ne 1 -or [version]$os.Version -lt [version]'10.0') {
        Exit-Script 0 'NotApplicable | Reason=UnsupportedOS'
    }
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try { $isSystem = $identity.User.Value -eq 'S-1-5-18' } finally { $identity.Dispose() }
    if (-not $isSystem) { Exit-Script 1 'Failed | Reason=SystemContextRequired' }
    $serviceNames = @('InstallService', 'ClipSVC', 'AppXSvc')
    $filter = "Name='InstallService' OR Name='ClipSVC' OR Name='AppXSvc'"
    $services = @(Get-CimInstance -ClassName Win32_Service -Filter $filter -OperationTimeoutSec $CimTimeoutSeconds)
    $changed = @()
    $blocked = @()
    $errors = @()
    foreach ($name in $serviceNames) {
        $service = $services | Where-Object { $_.Name -eq $name }
        if ($null -eq $service) { continue }
        Write-IRTLog ('Service={0}; StartMode={1}; State={2}' -f $name, $service.StartMode, $service.State)
        if ($service.StartMode -ne 'Disabled') { continue }
        if ($PolicyManagedServices -contains $name) {
            $blocked += $name
            Write-IRTLog "Service=$name; Action=PolicyManagedSkipped" 'WARN'
            continue
        }
        try {
            Set-Service -Name $name -StartupType Manual -ErrorAction Stop
            $changed += $name
            Write-IRTLog "Service=$name; Action=SetManual"
        }
        catch {
            $errors += $name
            Write-IRTLog ('Service={0}; Action=SetManualFailed; HResult={1}' -f $name, $_.Exception.HResult) 'ERROR'
        }
    }
    $startRequested = $false
    if ($changed.Count -gt 0 -and $PolicyManagedServices -notcontains 'InstallService') {
        $installService = Get-CimInstance -ClassName Win32_Service -Filter "Name='InstallService'" -OperationTimeoutSec $CimTimeoutSeconds
        if ($null -ne $installService -and $installService.StartMode -ne 'Disabled') {
            try {
                Start-Service -Name 'InstallService' -ErrorAction Stop -WarningAction SilentlyContinue
                $startRequested = $true
                Write-IRTLog 'Service=InstallService; Action=StartAccepted'
            }
            catch {
                $errors += 'InstallServiceStart'
                Write-IRTLog ('Service=InstallService; Action=StartFailed; HResult={0}' -f $_.Exception.HResult) 'ERROR'
            }
        }
    }
    $verified = @(Get-CimInstance -ClassName Win32_Service -Filter $filter -OperationTimeoutSec $CimTimeoutSeconds)
    $remaining = @($verified | Where-Object { $_.StartMode -eq 'Disabled' } | Select-Object -ExpandProperty Name)
    $missing = @($serviceNames | Where-Object { $verified.Name -notcontains $_ })
    $wrongMode = @($verified | Where-Object { $changed -contains $_.Name -and $_.StartMode -ne 'Manual' } | Select-Object -ExpandProperty Name)
    if ($remaining.Count -gt 0 -or $missing.Count -gt 0 -or $wrongMode.Count -gt 0 -or $errors.Count -gt 0 -or $blocked.Count -gt 0) {
        Exit-Script 1 "Failed | Changed=$($changed -join ','); Disabled=$($remaining -join ','); Missing=$($missing -join ','); PolicyManaged=$($blocked -join ','); Errors=$($errors -join ','); WrongMode=$($wrongMode -join ',')"
    }
    if ($changed.Count -eq 0) { Exit-Script 0 'Healthy | Disabled=0; Missing=0; Checked=3' }
    Exit-Script 0 "Fixed | Changed=$($changed -join ','); Disabled=0; InstallStartRequested=$startRequested"
}
catch { Exit-Script 1 ('Error: Failed | Reason=ServiceRepairFailed; HResult={0}' -f $_.Exception.HResult) }
