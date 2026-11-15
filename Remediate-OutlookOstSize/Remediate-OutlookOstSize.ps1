<#
.SYNOPSIS
  Remediation script for large Outlook OST files and shared mailbox caching.

.DESCRIPTION
  Writes the shared folder cache policy for loaded user profiles that do not have the value yet and can remove OST files that are near the size limit. Existing policy values are reported and left unchanged. Exits 0 when an action succeeds or nothing is actionable, 1 when an action fails.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$DisableSharedMailboxCaching = $true
$RemoveOstFiles = $false
$RemoveOstMinPercent = 80
$WarnPercent = 80
$CriticalPercent = 95
$DefaultLimitMB = 51200

$PackageName = 'OutlookOstSize'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message)
    try {
        $directory = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Message) -ErrorAction Stop
    }
    catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 2000) }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-PolicyValue {
    param([string]$KeyPath, [string]$Name)
    $result = [pscustomobject]@{ Exists = $false; Value = $null }
    if (-not (Test-Path -LiteralPath $KeyPath)) { return $result }
    $key = Get-Item -LiteralPath $KeyPath -ErrorAction SilentlyContinue
    if ($null -eq $key) { return $result }
    try {
        if ($key.GetValueNames() -contains $Name) {
            $result.Exists = $true
            $result.Value = $key.GetValue($Name)
        }
    }
    finally { $key.Close() }
    $result
}

function Set-PolicyDword {
    param([string]$KeyPath, [string]$Name, [int]$Value)
    if (-not (Test-Path -LiteralPath $KeyPath)) {
        New-Item -Path $KeyPath -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -LiteralPath $KeyPath -Name $Name -PropertyType DWord -Value $Value -Force -ErrorAction Stop | Out-Null
}

function Get-OstFiles {
    param([string]$LocalPath)
    $folder = Join-Path $LocalPath 'AppData\Local\Microsoft\Outlook'
    if (-not (Test-Path -LiteralPath $folder)) { return @() }
    @(Get-ChildItem -LiteralPath $folder -Filter '*.ost' -File -ErrorAction SilentlyContinue)
}

function Test-FileInUse {
    param([string]$Path)
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $stream.Close()
        return $false
    }
    catch { return $true }
}

try {
    $ErrorActionPreference = 'Stop'
    $userProfiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter 'Loaded=True AND Special=False' -ErrorAction Stop)
    if ($userProfiles.Count -eq 0) { Exit-Script 0 'NotApplicable | LoadedProfiles=0' }

    $facts = @()
    $profileIndex = 0
    foreach ($userProfile in $userProfiles) {
        $sid = [string]$userProfile.SID
        $localPath = [string]$userProfile.LocalPath
        if (-not $sid -or -not $localPath) { continue }
        $hive = 'Registry::HKEY_USERS\' + $sid
        if (-not (Test-Path -LiteralPath ($hive + '\Software\Microsoft\Office\16.0\Outlook'))) { continue }
        $profileIndex++

        $cacheKey = $hive + '\Software\Policies\Microsoft\Office\16.0\Outlook\Cached Mode'
        $cache = Get-PolicyValue -KeyPath $cacheKey -Name 'DownloadSharedFolders'

        $limitMB = $DefaultLimitMB
        $limitValue = Get-PolicyValue -KeyPath ($hive + '\Software\Policies\Microsoft\Office\16.0\Outlook\PST') -Name 'MaxLargeFileSize'
        if ($limitValue.Exists) {
            $candidate = 0
            if ([int]::TryParse([string]$limitValue.Value, [ref]$candidate)) {
                if ($candidate -ge 1024 -and $candidate -le $DefaultLimitMB) { $limitMB = $candidate }
            }
        }

        $files = @(Get-OstFiles -LocalPath $localPath)
        $maxBytes = 0
        foreach ($file in $files) {
            if ([int64]$file.Length -gt $maxBytes) { $maxBytes = [int64]$file.Length }
        }
        $percent = 0
        if ($maxBytes -gt 0) {
            $percent = [int][math]::Round(($maxBytes * 100.0) / ($limitMB * 1MB))
        }

        $facts += [pscustomobject]@{
            Index       = $profileIndex
            CacheKey    = $cacheKey
            CacheExists = $cache.Exists
            CacheValue  = $cache.Value
            Files       = $files
            Percent     = $percent
            LimitMB     = $limitMB
        }
    }

    if ($facts.Count -eq 0) { Exit-Script 0 'NotApplicable | ClassicOutlook=0' }

    $policySet = 0
    $managedProfiles = 0
    $missingProfiles = 0
    $writeFailed = 0
    $overWarn = 0
    $overCritical = 0
    $maxPercent = 0
    $minLimitMB = $DefaultLimitMB

    foreach ($fact in $facts) {
        if ($fact.Percent -gt $maxPercent) { $maxPercent = $fact.Percent }
        if ($fact.Percent -ge $WarnPercent) { $overWarn++ }
        if ($fact.Percent -ge $CriticalPercent) { $overCritical++ }
        if ($fact.LimitMB -lt $minLimitMB) { $minLimitMB = $fact.LimitMB }

        if ($fact.CacheExists) {
            if ([int]$fact.CacheValue -eq 0) { continue }
            $managedProfiles++
            Write-IRTLog "Profile $($fact.Index): shared folder cache value exists and was left unchanged"
            continue
        }

        $missingProfiles++
        if (-not $DisableSharedMailboxCaching) { continue }
        try {
            Set-PolicyDword -KeyPath $fact.CacheKey -Name 'DownloadSharedFolders' -Value 0
            $policySet++
            Write-IRTLog "Profile $($fact.Index): DownloadSharedFolders set to 0"
        }
        catch {
            $writeFailed++
            Write-IRTLog "Profile $($fact.Index): policy write failed with HResult $($_.Exception.HResult)"
        }
    }

    $removed = 0
    $inUse = 0
    $removeFailed = 0
    if ($RemoveOstFiles) {
        foreach ($fact in $facts) {
            if ($fact.Percent -lt $RemoveOstMinPercent) { continue }
            foreach ($file in $fact.Files) {
                if (Test-FileInUse -Path $file.FullName) {
                    $inUse++
                    Write-IRTLog "Profile $($fact.Index): OST file is in use and was skipped"
                    continue
                }
                try {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    if (Test-Path -LiteralPath $file.FullName) { throw 'File still present after delete' }
                    $removed++
                    Write-IRTLog "Profile $($fact.Index): OST file removed"
                }
                catch {
                    $removeFailed++
                    Write-IRTLog "Profile $($fact.Index): OST file delete failed with HResult $($_.Exception.HResult)"
                }
            }
        }
    }

    $verifyFailed = 0
    foreach ($fact in $facts) {
        if (-not $fact.CacheExists -and $DisableSharedMailboxCaching) {
            $check = Get-PolicyValue -KeyPath $fact.CacheKey -Name 'DownloadSharedFolders'
            if (-not $check.Exists -or [int]$check.Value -ne 0) { $verifyFailed++ }
        }
    }

    $limitGB = [int][math]::Round($minLimitMB / 1024.0)
    $summary = "Profiles=$($facts.Count); PolicySet=$policySet; Managed=$managedProfiles; OstRemoved=$removed; InUse=$inUse; OverWarn=$overWarn; OverCritical=$overCritical; MaxUsedPct=$maxPercent; LimitGB=$limitGB"

    if ($writeFailed -gt 0 -or $removeFailed -gt 0 -or $verifyFailed -gt 0) {
        Exit-Script 1 "Failed | $summary; WriteFailed=$writeFailed; RemoveFailed=$removeFailed; VerifyFailed=$verifyFailed"
    }
    if ($policySet -gt 0 -or $removed -gt 0) {
        Exit-Script 0 "Fixed | $summary; RemoveOst=$RemoveOstFiles; Effective=NextOutlookStart"
    }
    if ($inUse -gt 0) {
        Exit-Script 0 "Deferred | $summary; RemoveOst=$RemoveOstFiles; Reason=OstInUse"
    }
    if ($missingProfiles -gt 0 -and -not $DisableSharedMailboxCaching) {
        Exit-Script 0 "ReportOnly | $summary; Toggle=DisableSharedMailboxCaching"
    }
    if ($managedProfiles -gt 0) {
        Exit-Script 0 "PolicyManaged | $summary; Toggle=RemoveOstFiles"
    }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Error: Failed | Operation=Remediate; HResult={0}' -f $_.Exception.HResult) }
