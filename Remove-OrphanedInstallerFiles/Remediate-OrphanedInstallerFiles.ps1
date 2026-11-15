<#
.SYNOPSIS
  Remediation script for orphaned MSI and MSP files in the Windows Installer cache.

.DESCRIPTION
  Rebuilds the reference list from the Windows Installer API and deletes MSI and MSP files in C:\Windows\Installer that no product or patch references and that are older than the age limit. Rescans afterwards and exits 0 when no eligible orphan is left, 1 when files are blocked or removal failed.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeDays    = 7
$MinimumOrphanMB   = 1
$MaxFilesPerRun    = 200
$EnableRemediation = $false
$InstallerFolder   = Join-Path $env:windir 'Installer'
$PackageExtensions = @('.msi', '.msp')
$SampleLimit       = 8

$PackageName = 'OrphanedInstallerFiles'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
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

$InstallerSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class IrtInstallerCache
{
    const uint ContextUserManaged = 1;
    const uint ContextMachine = 4;
    const uint FilterAll = 15;
    const uint ErrorNoMoreItems = 259;
    const uint ErrorMoreData = 234;

    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    static extern uint MsiEnumProductsEx(string productCode, string userSid, uint context, uint index, StringBuilder installedProductCode, out uint installedContext, StringBuilder sid, ref uint sidSize);

    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    static extern uint MsiGetProductInfoEx(string productCode, string userSid, uint context, string property, StringBuilder value, ref uint valueSize);

    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    static extern uint MsiEnumPatchesEx(string productCode, string userSid, uint context, uint filter, uint index, StringBuilder patchCode, StringBuilder targetProductCode, out uint targetContext, StringBuilder targetUserSid, ref uint targetUserSidSize);

    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    static extern uint MsiGetPatchInfoEx(string patchCode, string productCode, string userSid, uint context, string property, StringBuilder value, ref uint valueSize);

    static string ReadProductValue(string productCode, string userSid, uint context, string property)
    {
        int capacity = 1024;
        for (int attempt = 0; attempt < 3; attempt++)
        {
            StringBuilder buffer = new StringBuilder(capacity);
            uint size = (uint)capacity;
            uint result = MsiGetProductInfoEx(productCode, userSid, context, property, buffer, ref size);
            if (result == 0) return buffer.ToString();
            if (result != ErrorMoreData) return null;
            capacity = (int)size + 1;
        }
        return null;
    }

    static string ReadPatchValue(string patchCode, string productCode, string userSid, uint context, string property)
    {
        int capacity = 1024;
        for (int attempt = 0; attempt < 3; attempt++)
        {
            StringBuilder buffer = new StringBuilder(capacity);
            uint size = (uint)capacity;
            uint result = MsiGetPatchInfoEx(patchCode, productCode, userSid, context, property, buffer, ref size);
            if (result == 0) return buffer.ToString();
            if (result != ErrorMoreData) return null;
            capacity = (int)size + 1;
        }
        return null;
    }

    static void AddPatches(string productCode, string userSid, uint context, List<string> target)
    {
        for (uint index = 0; ; index++)
        {
            StringBuilder patch = new StringBuilder(39);
            StringBuilder product = new StringBuilder(39);
            StringBuilder userSidBuffer = new StringBuilder(200);
            uint userSidSize = 200;
            uint targetContext;
            uint result = MsiEnumPatchesEx(productCode, userSid, context, FilterAll, index, patch, product, out targetContext, userSidBuffer, ref userSidSize);
            if (result == ErrorNoMoreItems) return;
            if (result != 0) return;
            string sidText = userSidBuffer.ToString();
            string querySid = targetContext == ContextMachine ? null : (sidText.Length > 0 ? sidText : null);
            string local = ReadPatchValue(patch.ToString(), product.ToString(), querySid, targetContext, "LocalPackage");
            if (!string.IsNullOrEmpty(local)) target.Add(local);
        }
    }

    static void AddProducts(string userSid, uint context, List<string> target)
    {
        for (uint index = 0; ; index++)
        {
            StringBuilder product = new StringBuilder(39);
            StringBuilder userSidBuffer = new StringBuilder(200);
            uint userSidSize = 200;
            uint installedContext;
            uint result = MsiEnumProductsEx(null, userSid, context, index, product, out installedContext, userSidBuffer, ref userSidSize);
            if (result == ErrorNoMoreItems) return;
            if (result != 0) return;
            string sidText = userSidBuffer.ToString();
            string querySid = installedContext == ContextMachine ? null : (sidText.Length > 0 ? sidText : null);
            string local = ReadProductValue(product.ToString(), querySid, installedContext, "LocalPackage");
            if (!string.IsNullOrEmpty(local)) target.Add(local);
            AddPatches(product.ToString(), querySid, installedContext, target);
        }
    }

    public static string[] GetReferencedPackages()
    {
        List<string> packages = new List<string>();
        AddProducts(null, ContextMachine, packages);
        AddProducts("S-1-1-0", ContextUserManaged, packages);
        return packages.ToArray();
    }
}
'@

function Get-ReferencedPackagePath {
    if (-not ('IrtInstallerCache' -as [type])) {
        Add-Type -TypeDefinition $InstallerSource -Language CSharp -ErrorAction Stop
    }
    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($raw in [IrtInstallerCache]::GetReferencedPackages()) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $value = $raw.Trim().Trim('"')
        try { $paths.Add([IO.Path]::GetFullPath($value)) } catch { }
    }
    $paths
}

function Get-InstallerFileInventory {
    param([string]$Folder, [string[]]$Extensions)
    $items = New-Object 'System.Collections.Generic.List[object]'
    [long]$totalBytes = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $Folder -File -Force -ErrorAction SilentlyContinue)) {
        if ($Extensions -notcontains $file.Extension.ToLowerInvariant()) { continue }
        $totalBytes += $file.Length
        $items.Add($file)
    }
    [pscustomobject]@{ Files = $items.ToArray(); TotalBytes = $totalBytes }
}

function Get-OrphanFileList {
    param([object[]]$Files, [string[]]$References, [datetime]$Cutoff)
    $referenceSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $References) { $null = $referenceSet.Add($path) }
    $orphans = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in $Files) {
        if ($file.LastWriteTimeUtc -ge $Cutoff) { continue }
        if ($referenceSet.Contains($file.FullName)) { continue }
        $orphans.Add($file)
    }
    $orphans
}

function Remove-OrphanInstallerFile {
    param([object]$File)
    try {
        Remove-Item -LiteralPath $File.FullName -Force -ErrorAction Stop
        return (Test-Path -LiteralPath $File.FullName)
    }
    catch { return $true }
}

try {
    $ErrorActionPreference = 'Stop'
    if ($MinimumAgeDays -lt 1 -or $MinimumAgeDays -gt 3650 -or $MinimumOrphanMB -lt 0 -or $MaxFilesPerRun -lt 1 -or $SampleLimit -lt 1) {
        Exit-Script 1 'Failed | Reason=InvalidConfiguration'
    }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') {
        Exit-Script 1 'Failed | Reason=RequiresSystem'
    }
    if (-not (Test-Path -LiteralPath $InstallerFolder -PathType Container)) {
        Exit-Script 0 'NotApplicable | Reason=InstallerFolderMissing'
    }

    $references = @(Get-ReferencedPackagePath)
    if ($references.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=NoRegisteredPackages' }

    $cutoff = [DateTime]::UtcNow.AddDays(-$MinimumAgeDays)
    $inventory = Get-InstallerFileInventory -Folder $InstallerFolder -Extensions $PackageExtensions
    $orphans = @(Get-OrphanFileList -Files $inventory.Files -References $references -Cutoff $cutoff)
    [long]$orphanBytes = 0
    foreach ($file in $orphans) { $orphanBytes += $file.Length }
    $orphanMB = [math]::Floor($orphanBytes / 1MB)

    $baseText = 'Files={0}; FolderMB={1}; References={2}; OrphanFiles={3}; OrphanMB={4}' -f $inventory.Files.Count, [math]::Floor($inventory.TotalBytes / 1MB), $references.Count, $orphans.Count, $orphanMB

    if ($orphans.Count -eq 0 -or $orphanMB -lt $MinimumOrphanMB) { Exit-Script 0 "Healthy | $baseText" }

    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | $baseText; EnableRemediation=False; Deleted=0"
    }

    $setup = @(Get-Process -Name 'msiexec' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
    if ($setup.Count -gt 0) {
        Exit-Script 1 "Blocked | Reason=InteractiveInstallerRunning; $baseText; Deleted=0"
    }

    $targets = @($orphans | Sort-Object Length -Descending | Select-Object -First $MaxFilesPerRun)
    $deleted = 0
    $failed = 0
    [long]$deletedBytes = 0
    $deletedNames = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in $targets) {
        $remains = Remove-OrphanInstallerFile -File $file
        if ($remains) {
            $failed++
            Write-IRTLog "Removal failed: $($file.Name)" 'WARN'
            continue
        }
        $deleted++
        $deletedBytes += $file.Length
        if ($deletedNames.Count -lt $SampleLimit) { $deletedNames.Add($file.Name) }
        Write-IRTLog "Removed: $($file.Name); MB=$([math]::Floor($file.Length / 1MB))"
    }

    $after = Get-InstallerFileInventory -Folder $InstallerFolder -Extensions $PackageExtensions
    $remaining = @(Get-OrphanFileList -Files $after.Files -References $references -Cutoff $cutoff)
    [long]$remainingBytes = 0
    foreach ($file in $remaining) { $remainingBytes += $file.Length }

    $nameText = 'None'
    if ($deletedNames.Count -gt 0) { $nameText = $deletedNames -join ',' }
    $common = 'Deleted={0}; DeletedMB={1}; Failed={2}; Remaining={3}; RemainingMB={4}; Names={5}; {6}' -f $deleted, [math]::Floor($deletedBytes / 1MB), $failed, $remaining.Count, [math]::Floor($remainingBytes / 1MB), $nameText, $baseText

    if ($failed -gt 0) { Exit-Script 1 "Failed | $common" }
    if ($remaining.Count -gt 0) { Exit-Script 0 "Fixed | $common; Note=MoreFilesNextRun" }
    Exit-Script 0 "Fixed | $common"
}
catch { Exit-Script 1 ('Error: Operation=None; HResult=0x{0:X8}; Changed=Unknown' -f $_.Exception.HResult) }
