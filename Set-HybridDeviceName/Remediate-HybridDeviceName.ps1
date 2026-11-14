<#
.SYNOPSIS
  Remediation script for approved hybrid device names.

.DESCRIPTION
  Renames approved hybrid workstations using delegated domain credentials.
  Disabled by default. Verifies the staged name without restarting Windows.
  Exits 0 when healthy or successfully staged and 1 when blocked or failed.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $false
$ExpectedDomain = ''
$ApprovedNames = @{}
$NamePattern = '^PC-[A-Z0-9]{1,12}$'
$DomainCredentialPath = ''

$PackageName = 'HybridDeviceName'
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
function Test-EntraDeviceJoin {
    if (-not ('IRTHybridJoin' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class IRTHybridJoin {
    [DllImport("netapi32.dll", CharSet = CharSet.Unicode)]
    public static extern int NetGetAadJoinInformation(string tenant, out IntPtr info);
    [DllImport("netapi32.dll")]
    public static extern void NetFreeAadJoinInformation(IntPtr info);
}
'@ -ErrorAction Stop
    }
    $info = [IntPtr]::Zero
    try {
        $result = [IRTHybridJoin]::NetGetAadJoinInformation($null, [ref]$info)
        if ($result -ne 0) { throw 'JoinQueryFailed' }
        return ($info -ne [IntPtr]::Zero -and [Runtime.InteropServices.Marshal]::ReadInt32($info) -eq 1)
    }
    finally {
        if ($info -ne [IntPtr]::Zero) { [IRTHybridJoin]::NetFreeAadJoinInformation($info) }
    }
}
function Get-NameState {
    $root = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName'
    $active = (Get-ItemProperty -LiteralPath "$root\ActiveComputerName" -Name ComputerName -ErrorAction Stop).ComputerName
    $configured = (Get-ItemProperty -LiteralPath "$root\ComputerName" -Name ComputerName -ErrorAction Stop).ComputerName
    if (-not $active -or -not $configured) { throw 'NameStateMissing' }
    [pscustomobject]@{ Active = $active; Configured = $configured }
}
function Test-TargetNameAvailable { param([string]$Target)
    $domain = $null
    $root = $null
    $searcher = $null
    try {
        Add-Type -AssemblyName System.DirectoryServices -ErrorAction Stop
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()
        $root = $domain.GetDirectoryEntry()
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.Filter = '(&(objectCategory=computer)(sAMAccountName={0}$))' -f $Target
        $searcher.ClientTimeout = [TimeSpan]::FromSeconds(15)
        $searcher.ServerTimeLimit = [TimeSpan]::FromSeconds(15)
        return ($null -eq $searcher.FindOne())
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
        if ($null -ne $domain) { $domain.Dispose() }
    }
}
try {
    $stage = 'Eligibility'
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or -not $computer.PartOfDomain) { Exit-Script 0 'NotApplicable | HybridWorkstation=False' }
    if (-not (Test-EntraDeviceJoin)) { Exit-Script 0 'NotApplicable | EntraDeviceJoin=False' }
    if ([string]::IsNullOrWhiteSpace($ExpectedDomain) -or $ApprovedNames.Count -eq 0) { Exit-Script 1 'ConfigurationRequired | DomainOrApprovals=Missing' }
    if ($computer.Domain -ine $ExpectedDomain) { Exit-Script 0 'NotApplicable | ApprovedDomain=False' }
    $names = @($ApprovedNames.Values | ForEach-Object { [string]$_ })
    foreach ($name in $names) {
        if ($name.Length -gt 15 -or $name -cnotmatch $NamePattern -or $name -notmatch '^[A-Za-z][A-Za-z0-9-]{0,13}[A-Za-z0-9]$') { Exit-Script 1 'ConfigurationRequired | ApprovedName=Invalid' }
    }
    if (@($names | Sort-Object -Unique).Count -ne $names.Count) { Exit-Script 1 'ConfigurationRequired | DuplicateTargets=True' }
    $uuid = ([string](Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop).UUID).ToUpperInvariant()
    if ($uuid -notmatch '^[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}$' -or $uuid -match '^(0|-)+$|^(F|-)+$') { Exit-Script 1 'Failed | HardwareIdentity=Invalid' }
    if (-not $ApprovedNames.ContainsKey($uuid)) { Exit-Script 0 'NotApplicable | ApprovedDevice=False' }
    $expected = [string]$ApprovedNames[$uuid]
    $state = Get-NameState
    if ($state.Active -ine $state.Configured) {
        if ($state.Configured -ieq $expected) { Exit-Script 0 'PendingReboot | TargetStaged=True; Restart=Manual' }
        Exit-Script 1 'Blocked | ConflictingPendingRename=True'
    }
    if ($state.Active -ieq $expected) { Exit-Script 0 'Healthy | NameMatches=True; PendingRename=False' }
    if (-not $EnableRemediation) { Exit-Script 1 'ReportOnly | NameMatches=False; EnableRemediation=False' }
    if ([string]::IsNullOrWhiteSpace($DomainCredentialPath) -or -not (Test-Path -LiteralPath $DomainCredentialPath -PathType Leaf)) { Exit-Script 1 'Blocked | DomainCredential=Missing' }
    $stage = 'DomainPreflight'
    if (-not (Test-ComputerSecureChannel -ErrorAction Stop)) { Exit-Script 1 'Blocked | SecureChannel=False' }
    if (-not (Test-TargetNameAvailable -Target $expected)) { Exit-Script 1 'Blocked | TargetNameInAD=True' }
    $stage = 'CredentialImport'
    $credential = Import-Clixml -LiteralPath $DomainCredentialPath -ErrorAction Stop
    if ($credential -isnot [System.Management.Automation.PSCredential]) { Exit-Script 1 'Blocked | DomainCredential=Invalid' }
    $stage = 'Rename'
    try {
        $result = Rename-Computer -NewName $expected -DomainCredential $credential -Force -PassThru -WarningAction SilentlyContinue -ErrorAction Stop
    }
    finally {
        if ($null -ne $credential) { $credential.Password.Dispose(); $credential = $null }
    }
    $stage = 'Verification'
    $verified = Get-NameState
    if (-not $result.HasSucceeded -or $verified.Configured -ine $expected) { Exit-Script 1 'Failed | TargetStaged=False; ReviewAD=True' }
    Exit-Script 0 'PendingReboot | TargetStaged=True; Restart=Manual'
}
catch { Exit-Script 1 ('Error: Failed | Stage={0}; HResult={1}' -f $stage, $_.Exception.HResult) }
