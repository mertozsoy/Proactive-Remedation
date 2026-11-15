<#
.SYNOPSIS
  Detection script for AD secure channel failures on hybrid workstations.

.DESCRIPTION
  Checks domain membership, Netlogon and DC discovery before testing the channel.
  Exits 1 for a failed test or an inconclusive check, 0 for healthy or inapplicable devices.
  Assign only to hybrid joined Windows workstation groups.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$DomainController = ''

$PackageName = 'AdSecureChannel'
$Phase = 'Detect'
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
    if ($healthy -eq $true) { Exit-Script 0 'Healthy | SecureChannel=True' }
    if ($healthy -eq $false) { Exit-Script 1 'Drift | SecureChannel=False; DcDiscovery=Passed' }
    Exit-Script 1 'Unknown | Reason=NoBooleanTestResult'
}
catch { Exit-Script 1 ('Error | Reason=CheckFailed; HResult={0}' -f $_.Exception.HResult) }
