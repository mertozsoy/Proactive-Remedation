<#
.SYNOPSIS
  Remediation script for approved Point and Print servers and secure driver settings.

.DESCRIPTION
  After explicit confirmation that these settings have no active GPO or MDM owner, exports the existing printer policy key, applies the approved server baseline and verifies every value. Exits 1 if blocked or not verified, 0 when healthy or fixed. Never relaxes administrator-only driver installation or restarts services.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedPrintServers = @()
$ConfirmNoCentralPolicy = $false

$PackageName = 'PointAndPrintSecurity'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Get-ApprovedServer {
    if ($ApprovedPrintServers.Count -eq 0) { throw 'ApprovedPrintServers must contain approved FQDNs.' }
    foreach ($server in $ApprovedPrintServers) {
        $name = ([string]$server).Trim().ToLowerInvariant()
        if ($name.Length -gt 253 -or $name -notmatch '^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$') {
            throw 'ApprovedPrintServers contains an invalid FQDN. Do not use UNC paths, IPs or wildcards.'
        }
        $name
    }
}
function Get-ExpectedValue {
    param([string[]]$Servers)
    $point = 'SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'
    $package = 'SOFTWARE\Policies\Microsoft\Windows NT\Printers\PackagePointAndPrint'
    foreach ($entry in @(
        @{ Name = 'RestrictDriverInstallationToAdministrators'; Data = 1 }
        @{ Name = 'NoWarningNoElevationOnInstall'; Data = 0 }
        @{ Name = 'UpdatePromptSettings'; Data = 0 }
        @{ Name = 'Restricted'; Data = 1 }
        @{ Name = 'TrustedServers'; Data = 1 }
        @{ Name = 'InForest'; Data = 0 }
    )) {
        [pscustomobject]@{ Key = $point; Name = $entry.Name; Kind = 'DWord'; Data = $entry.Data }
    }
    [pscustomobject]@{ Key = $point; Name = 'ServerList'; Kind = 'String'; Data = ($Servers -join ';') }
    [pscustomobject]@{ Key = $package; Name = 'PackagePointAndPrintServerList'; Kind = 'DWord'; Data = 1 }
    foreach ($server in $Servers) {
        [pscustomobject]@{ Key = "$package\ListofServers"; Name = $server; Kind = 'String'; Data = $server }
    }
}
function Get-BaselineDrift {
    param([Microsoft.Win32.RegistryKey]$Root, [object[]]$Expected)
    foreach ($entry in $Expected) {
        $key = $Root.OpenSubKey($entry.Key)
        try {
            if ($null -eq $key -or $key.GetValueNames() -notcontains $entry.Name) {
                [pscustomobject]@{ Key = $entry.Key; Name = $entry.Name; Action = 'Set'; Kind = $entry.Kind; Data = $entry.Data }
                continue
            }
            $kind = [string]$key.GetValueKind($entry.Name)
            $data = $key.GetValue($entry.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $isMatch = $kind -eq $entry.Kind -and ([string]$data -ieq [string]$entry.Data)
            if ($entry.Name -eq 'ServerList' -and $kind -eq 'String') {
                $actual = @(([string]$data -split ';') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Sort-Object -Unique)
                $wanted = @(([string]$entry.Data -split ';') | Sort-Object -Unique)
                $isMatch = ($actual -join ';') -ceq ($wanted -join ';')
            }
            if (-not $isMatch) {
                [pscustomobject]@{ Key = $entry.Key; Name = $entry.Name; Action = 'Set'; Kind = $entry.Kind; Data = $entry.Data }
            }
        }
        finally { if ($null -ne $key) { $key.Dispose() } }
    }
    $listPath = 'SOFTWARE\Policies\Microsoft\Windows NT\Printers\PackagePointAndPrint\ListofServers'
    $names = @($Expected | Where-Object { $_.Key -eq $listPath } | ForEach-Object { $_.Name })
    $key = $Root.OpenSubKey($listPath)
    try {
        if ($null -ne $key) {
            foreach ($name in $key.GetValueNames()) {
                if ($names -notcontains $name) {
                    [pscustomobject]@{ Key = $listPath; Name = $name; Action = 'Remove'; Kind = ''; Data = $null }
                }
            }
        }
    }
    finally { if ($null -ne $key) { $key.Dispose() } }
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [version]$os.Version -lt [version]'10.0.14393') {
        Exit-Script 0 'NotApplicable | Reason=RequiresPatchedWindowsClient'
    }
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if (-not $computer.PartOfDomain) { Exit-Script 0 'NotApplicable | Reason=PointAndPrintRestrictionsRequireDomain' }
    if ($ApprovedPrintServers.Count -eq 0) { Exit-Script 1 'Failed | Reason=ConfigureApprovedPrintServers' }
    $servers = @(Get-ApprovedServer | Sort-Object -Unique)
    if (($servers -join ';').Length -gt 8192) { throw 'Approved server list exceeds the supported length.' }
    $expected = @(Get-ExpectedValue -Servers $servers)
    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $drift = @(Get-BaselineDrift -Root $root -Expected $expected)
        if ($drift.Count -eq 0) { Exit-Script 0 "Healthy | Changes=0; ApprovedServers=$($servers.Count); AdminOnly=1" }
        if (-not $ConfirmNoCentralPolicy) {
            Exit-Script 1 "Blocked | Changes=$($drift.Count); Reason=ConfirmNoCentralPolicyRequired"
        }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            if ($identity.User.Value -ne 'S-1-5-18') { Exit-Script 1 'Failed | Reason=RequiresSystem' }
        }
        finally { $identity.Dispose() }
        $parentPath = 'SOFTWARE\Policies\Microsoft\Windows NT\Printers'
        $existing = $root.OpenSubKey($parentPath)
        $backupRequired = $null -ne $existing
        if ($null -ne $existing) { $existing.Dispose() }
        if ($backupRequired) {
            $backupDir = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
            New-Item -Path $backupDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $backupFile = Join-Path $backupDir ('PointAndPrintSecurity_{0}_{1}.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmssfff'), [guid]::NewGuid().ToString('N'))
            $reg = Join-Path $env:SystemRoot 'System32\reg.exe'
            & $reg export "HKLM\$parentPath" $backupFile /y 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupFile)) { throw 'Registry backup failed.' }
            Write-IRTLog 'Registry backup completed.'
        }
        foreach ($entry in $drift) {
            $key = $root.CreateSubKey($entry.Key)
            try {
                if ($entry.Action -eq 'Remove') {
                    $key.DeleteValue($entry.Name, $false)
                }
                else {
                    $kind = [Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind], $entry.Kind)
                    $key.SetValue($entry.Name, $entry.Data, $kind)
                }
            }
            finally { if ($null -ne $key) { $key.Dispose() } }
        }
        $remaining = @(Get-BaselineDrift -Root $root -Expected $expected)
        if ($remaining.Count -gt 0) { Exit-Script 1 "Failed | Remaining=$($remaining.Count); Reason=VerificationFailed" }
        Exit-Script 0 "Fixed | Changes=$($drift.Count); ApprovedServers=$($servers.Count); AdminOnly=1"
    }
    finally { $root.Dispose() }
}
catch { Exit-Script 1 "Failed | Reason=RemediationError; ErrorType=$($_.Exception.GetType().Name)" }
