<#
.SYNOPSIS
  Remediation script for requesting a Microsoft Store app update scan.

.DESCRIPTION
  Invokes the documented MDM bridge UpdateScanMethod in the device context. Exits 0 when the method returns zero, in report mode or when not applicable. Exits 1 on failure. Request acceptance does not prove app installation or vulnerability resolution.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableUpdateScan = $true
$CimTimeoutSeconds = 60

$PackageName = 'StoreApps'
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
    $os = Get-CimInstance -Namespace 'root\cimv2' -ClassName Win32_OperatingSystem -OperationTimeoutSec $CimTimeoutSeconds
    if ($os.ProductType -ne 1 -or [version]$os.Version -lt [version]'10.0.10586') {
        Exit-Script 0 'NotApplicable | Reason=UnsupportedOS'
    }
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try { $isSystem = $identity.User.Value -eq 'S-1-5-18' } finally { $identity.Dispose() }
    if (-not $isSystem) { Exit-Script 1 'Failed | Reason=SystemContextRequired' }
    $instances = @(Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' -Filter "InstanceID='AppManagement'" -OperationTimeoutSec $CimTimeoutSeconds)
    if ($instances.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=AppManagementInstanceMissing' }
    if ($instances.Count -ne 1) { Exit-Script 1 'Failed | Reason=AmbiguousAppManagementInstance' }
    if (-not $EnableUpdateScan) { Exit-Script 0 'ReportOnly | ScanRequested=False' }
    $result = Invoke-CimMethod -InputObject $instances[0] -MethodName 'UpdateScanMethod' -OperationTimeoutSec $CimTimeoutSeconds
    if ($null -eq $result -or $null -eq $result.ReturnValue) {
        Exit-Script 1 'Failed | Reason=MissingMethodReturnValue; Completion=Unknown'
    }
    $returnValue = [uint32]$result.ReturnValue
    if ($returnValue -ne 0) { Exit-Script 1 "Failed | ReturnValue=$returnValue; Completion=Unknown" }
    Exit-Script 0 'Requested | ReturnValue=0; Completion=NotVerified; Scope=Device'
}
catch { Exit-Script 1 ('Error: Failed | HResult={0}; Reason=ScanRequestFailed; Completion=Unknown' -f $_.Exception.HResult) }
