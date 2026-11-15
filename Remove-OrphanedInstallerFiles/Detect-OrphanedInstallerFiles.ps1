<#
.SYNOPSIS
  Detection script for orphaned MSI and MSP files in the Windows Installer cache.

.DESCRIPTION
  Reads the cached package path of every registered product and patch through the Windows Installer API. Compares that list with the files in C:\Windows\Installer and reports MSI and MSP files that no product or patch references and that are older than the age limit. Exits 1 if such files are found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeDays = 7
$MinimumOrphanMB = 1
$InstallerFolder = Join-Path $env:windir 'Installer'
$PackageExtensions = @('.msi', '.msp')
$SampleLimit = 8

$PackageName = 'OrphanedInstallerFiles'
$Phase       = 'Detect'
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

try {
    $ErrorActionPreference = 'Stop'
    if ($MinimumAgeDays -lt 1 -or $MinimumAgeDays -gt 3650 -or $MinimumOrphanMB -lt 0 -or $SampleLimit -lt 1) {
        Exit-Script 1 'Failed | Reason=InvalidConfiguration'
    }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if (-not (Test-Path -LiteralPath $InstallerFolder -PathType Container)) {
        Exit-Script 0 'NotApplicable | Reason=InstallerFolderMissing'
    }

    $references = @(Get-ReferencedPackagePath)
    if ($references.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=NoRegisteredPackages' }

    $inventory = Get-InstallerFileInventory -Folder $InstallerFolder -Extensions $PackageExtensions
    $cutoff = [DateTime]::UtcNow.AddDays(-$MinimumAgeDays)
    $orphans = @(Get-OrphanFileList -Files $inventory.Files -References $references -Cutoff $cutoff)

    [long]$orphanBytes = 0
    foreach ($file in $orphans) { $orphanBytes += $file.Length }
    $orphanMB = [math]::Floor($orphanBytes / 1MB)
    [int]$oldestDays = 0
    foreach ($file in $orphans) {
        $age = [int][math]::Floor(([DateTime]::UtcNow - $file.LastWriteTimeUtc).TotalDays)
        if ($age -gt $oldestDays) { $oldestDays = $age }
    }
    $sample = 'None'
    if ($orphans.Count -gt 0) {
        $sample = (@($orphans | Sort-Object Length -Descending | Select-Object -First $SampleLimit | ForEach-Object { $_.Name }) -join ',')
    }

    $summary = 'Files={0}; FolderMB={1}; References={2}; OrphanFiles={3}; OrphanMB={4}; OldestDays={5}; Sample={6}; MinAgeDays={7}' -f $inventory.Files.Count, [math]::Floor($inventory.TotalBytes / 1MB), $references.Count, $orphans.Count, $orphanMB, $oldestDays, $sample, $MinimumAgeDays

    if ($orphans.Count -gt 0 -and $orphanMB -ge $MinimumOrphanMB) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Error | Reason=ScanFailed; Type={0}' -f $_.Exception.GetType().Name) }
