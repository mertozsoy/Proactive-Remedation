<#
.SYNOPSIS
  Remediation script for AD secure channel failures on hybrid workstations.

.DESCRIPTION
  Rechecks prerequisites and calls Test-ComputerSecureChannel -Repair using the
  current SYSTEM identity. Verifies the channel after repair. Exits 0 only when
  healthy or inapplicable, 1 when deferred, disabled or unsuccessful.
  Domain credential failures require an authorized AD administrator.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $true
$DomainController = ''

$PackageName = 'AdSecureChannel'
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
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($null -eq $computer.PartOfDomain -or $null -eq $computer.DomainRole) {
        Exit-Script 1 'Unknown | Reason=DomainMembershipUnavailable'
    }
    if (-not $computer.PartOfDomain) { Exit-Script 0 'NotApplicable | DomainJoined=False' }
    if ($computer.DomainRole -ne 1) { Exit-Script 0 'NotApplicable | Reason=NotMemberWorkstation' }
    $netlogon = Get-Service -Name Netlogon -ErrorAction Stop
    if ($netlogon.Status -ne 'Running') { Exit-Script 1 'Deferred | Reason=NetlogonNotRunning; Changed=False' }
    $nltest = Join-Path $env:SystemRoot 'System32\nltest.exe'
    if (-not (Test-Path -LiteralPath $nltest)) { Exit-Script 1 'Deferred | Reason=NltestMissing; Changed=False' }
    & $nltest "/dsgetdc:$($computer.Domain)" /force /writable 2>&1 | Out-Null
    $discoveryCode = $LASTEXITCODE
    if ($discoveryCode -ne 0) {
        Exit-Script 1 "Deferred | Reason=DcDiscoveryFailed; NativeCode=$discoveryCode; Changed=False"
    }
    $testParameters = @{ ErrorAction = 'Stop'; Verbose = $false }
    if (-not [string]::IsNullOrWhiteSpace($DomainController)) { $testParameters.Server = $DomainController.Trim() }
    $healthy = Test-ComputerSecureChannel @testParameters
    if ($healthy -eq $true) { Exit-Script 0 'Healthy | SecureChannel=True; RepairAttempted=False' }
    if ($healthy -ne $false) { Exit-Script 1 'Unknown | Reason=NoBooleanTestResult' }
    if (-not $EnableRemediation) { Exit-Script 1 'Drift | SecureChannel=False; RepairEnabled=False' }
    Write-IRTLog 'Repair | Identity=System; Attempt=1'
    try {
        $repaired = Test-ComputerSecureChannel -Repair -Confirm:$false @testParameters
        Write-IRTLog ('Repair | CmdletResult={0}' -f $repaired)
    }
    catch {
        Exit-Script 1 ('Failed | Reason=RepairRejected; Action=ReviewDcConnectivityAndAdPermissions; HResult={0}' -f $_.Exception.HResult)
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $healthy = Test-ComputerSecureChannel @testParameters
            if ($healthy -eq $true) { Exit-Script 0 'Fixed | SecureChannel=True; RepairAttempted=True' }
        }
        catch { Write-IRTLog ('Verification | Attempt={0}; HResult={1}' -f $attempt, $_.Exception.HResult) 'WARN' }
        if ($attempt -lt 3) { Start-Sleep -Seconds 5 }
    }
    Exit-Script 1 'Failed | SecureChannel=NotVerified; Action=AuthorizedAdRepairRequired'
}
catch { Exit-Script 1 ('Error | Reason=CheckFailed; HResult={0}' -f $_.Exception.HResult) }
