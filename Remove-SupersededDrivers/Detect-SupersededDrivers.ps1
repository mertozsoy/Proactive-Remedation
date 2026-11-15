<#
.SYNOPSIS
  Detection script for superseded third-party driver packages in the driver store.

.DESCRIPTION
  Reads third-party drivers with Get-WindowsDriver, groups them by original INF name and reports every older package whose group already has a newer version. Exits 1 if such a package is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeDays    = 30
$MinimumSuperseded = 1
$SkipClasses       = @('Printer', 'System', 'SCSIAdapter')

$PackageName = 'SupersededDrivers'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

$DriverStorePath = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'

function ConvertTo-DriverVersion { param([string]$Value)
    if (-not $Value) { return [version]'0.0.0.0' }
    try { return [version]$Value.Trim() } catch { return [version]'0.0.0.0' }
}

function Get-InUseInfName {
    $set = @{}
    foreach ($device in Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction SilentlyContinue) {
        if ($device.InfName) { $set[([string]$device.InfName).ToLower()] = $true }
    }
    return $set
}

function Get-DriverStoreSizeMB {
    if (-not (Test-Path -LiteralPath $DriverStorePath)) { return 0 }
    $bytes = 0
    try {
        foreach ($file in [System.IO.Directory]::EnumerateFiles($DriverStorePath, '*', [System.IO.SearchOption]::AllDirectories)) {
            try { $bytes += ([System.IO.FileInfo]::new($file)).Length } catch { }
        }
    }
    catch { }
    return [math]::Round($bytes / 1MB, 1)
}

function Get-SupersededDriver { param([hashtable]$InUse)
    $drivers = @(Get-WindowsDriver -Online -ErrorAction Stop | Where-Object { $_.Driver -match '^oem\d+\.inf$' })
    $cutoff  = (Get-Date).AddDays(-$MinimumAgeDays)
    $groups  = $drivers | Group-Object -Property {
        $arch = ''
        if ($_.PSObject.Properties['Architecture']) { $arch = [string]$_.Architecture }
        '{0}|{1}|{2}|{3}' -f ([string]$_.OriginalFileName).ToLower(), ([string]$_.ProviderName).ToLower(), ([string]$_.ClassName).ToLower(), $arch.ToLower()
    }
    $found = @()
    foreach ($group in $groups) {
        if ($group.Count -lt 2) { continue }
        if (-not ([string]$group.Group[0].OriginalFileName)) { continue }
        $ordered = @($group.Group | Sort-Object -Property @{ Expression = { ConvertTo-DriverVersion -Value $_.Version }; Descending = $true }, @{ Expression = { if ($_.Date) { [datetime]$_.Date } else { [datetime]'1900-01-01' } }; Descending = $true })
        for ($i = 1; $i -lt $ordered.Count; $i++) {
            $driver = $ordered[$i]
            if ($InUse.ContainsKey(([string]$driver.Driver).ToLower())) { continue }
            if ($SkipClasses -contains [string]$driver.ClassName) { continue }
            if ([bool]$driver.BootCritical) { continue }
            if ($driver.Date -and ([datetime]$driver.Date) -gt $cutoff) { continue }
            $found += [pscustomobject]@{
                Driver           = [string]$driver.Driver
                OriginalFileName = [string]$driver.OriginalFileName
                ProviderName     = [string]$driver.ProviderName
                ClassName        = [string]$driver.ClassName
                Version          = [string]$driver.Version
                Date             = $driver.Date
            }
        }
    }
    [pscustomobject]@{ Packages = $drivers.Count; Superseded = $found }
}

try {
    $inUse     = Get-InUseInfName
    $scan      = Get-SupersededDriver -InUse $inUse
    $storeMB   = Get-DriverStoreSizeMB
    $superseded = @($scan.Superseded)

    if ($superseded.Count -lt $MinimumSuperseded) { Exit-Script 0 "Healthy | ThirdParty=$($scan.Packages); Superseded=0; StoreMB=$storeMB" }

    $sample = (@($superseded | Sort-Object Driver | Select-Object -First 5 | ForEach-Object { '{0}({1})' -f $_.Driver, $_.OriginalFileName }) -join ',')
    Exit-Script 1 "Drift | ThirdParty=$($scan.Packages); Superseded=$($superseded.Count); StoreMB=$storeMB; Sample=$sample"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
