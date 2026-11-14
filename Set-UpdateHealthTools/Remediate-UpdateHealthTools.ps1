<#
.SYNOPSIS
  Remediation script that removes the Microsoft Update Health Tools on 24H2 and later and installs them on older builds.

.DESCRIPTION
  Uninstalls the Update Health Tools MSI when the device runs Windows 11 24H2 or later and the tools are still present. On earlier builds it installs the MSI from $HealthToolsMsiPath when the tools are missing. Checks the service state afterwards. Exits 0 when the device is in the expected state, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$HealthToolsMsiPath = ''
$EnableRemediation  = $true
$Build24H2          = 26100
$ServiceName        = 'uhssvc'
$ProductNamePattern = 'Microsoft Update Health Tools*'
$InstallFolder      = Join-Path $env:ProgramFiles 'Microsoft Update Health Tools'

$PackageName = 'UpdateHealthTools'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

$VersionKey    = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$ProductKey    = 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions'
$UninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
$GuidPattern   = '[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}'
$SuccessCodes  = @(0, 3010, 1605, 1641)

function Get-HealthToolsEntry {
    $entries = @()
    foreach ($root in $UninstallKeys) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            $name = [string]$props.DisplayName
            if ($name -notlike $ProductNamePattern) { continue }
            $entries += [pscustomobject]@{
                KeyName         = $key.PSChildName
                Name            = $name
                UninstallString = [string]$props.UninstallString
            }
        }
    }
    @($entries)
}

function Get-HealthToolsState {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    $entries = @(Get-HealthToolsEntry)
    [pscustomobject]@{
        Service   = [bool]$service
        Uninstall = ($entries.Count -gt 0)
        Folder    = (Test-Path -LiteralPath $InstallFolder)
        Entries   = $entries
    }
}

function Get-OSBuild {
    $raw   = [string](Get-ItemProperty -LiteralPath $VersionKey -Name 'CurrentBuildNumber' -ErrorAction SilentlyContinue).CurrentBuildNumber
    $build = [int]$raw
    if ($build -lt 10240) { throw "OS build number not readable: $raw" }
    $build
}

function Get-ProductCode {
    param($Entry)
    if ($Entry.KeyName -match "^\{$GuidPattern\}$") { return $Entry.KeyName }
    if ($Entry.UninstallString -match "\{$GuidPattern\}") { return $Matches[0] }
    ''
}

function Invoke-MsiExec {
    param([string]$Arguments)
    $file    = Join-Path $env:SystemRoot 'System32\msiexec.exe'
    $process = Start-Process -FilePath $file -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    [int]$process.ExitCode
}

try {
    $productType = [string](Get-ItemProperty -LiteralPath $ProductKey -Name 'ProductType' -ErrorAction SilentlyContinue).ProductType
    if ($productType -and $productType -ne 'WinNT') { Exit-Script 0 "NotApplicable | ProductType=$productType" }

    $build = Get-OSBuild
    $state = Get-HealthToolsState
    $present = $false
    if ($state.Service -or $state.Uninstall -or $state.Folder) { $present = $true }
    $stateText = 'Absent'
    if ($present) { $stateText = 'Present' }

    $needsUninstall = ($build -ge $Build24H2 -and $present)
    $needsInstall   = ($build -lt $Build24H2 -and -not $present)
    if (-not $needsUninstall -and -not $needsInstall) { Exit-Script 0 "Healthy | Build=$build; HealthTools=$stateText" }
    if (-not $EnableRemediation) { Exit-Script 0 "ReportOnly | Build=$build; HealthTools=$stateText; Toggle=EnableRemediation" }

    if ($needsUninstall) {
        $removed  = 0
        $lastCode = 0
        foreach ($entry in $state.Entries) {
            $code = Get-ProductCode -Entry $entry
            if (-not $code) {
                Write-IRTLog "No MSI product code for $($entry.Name)"
                continue
            }
            $lastCode = Invoke-MsiExec -Arguments ('/x {0} /qn /norestart' -f $code)
            Write-IRTLog "msiexec /x $code returned $lastCode"
            if ($SuccessCodes -contains $lastCode) { $removed++ }
        }

        if ($state.Entries.Count -eq 0) { Exit-Script 1 "Manual | Build=$build; HealthTools=Present; Reason=Uninstall entry not found" }
        if ($removed -eq 0) { Exit-Script 1 "Failed | Action=Uninstall; Build=$build; ExitCode=$lastCode; HealthTools=Present" }

        $after = Get-HealthToolsState
        if ($after.Service -or $after.Uninstall) {
            Exit-Script 1 "Partial | Action=Uninstall; Build=$build; ExitCode=$lastCode; Service=$($after.Service); UninstallEntry=$($after.Uninstall)"
        }
        Exit-Script 0 "Fixed | Action=Uninstall; Build=$build; ExitCode=$lastCode; Service=Absent; Folder=$($after.Folder)"
    }

    if (-not $HealthToolsMsiPath) {
        Exit-Script 0 "Manual | Build=$build; HealthTools=Absent; Action=Set HealthToolsMsiPath to a local KB4023057 MSI"
    }
    if (-not (Test-Path -LiteralPath $HealthToolsMsiPath -PathType Leaf)) {
        Exit-Script 1 "WrongPath | Build=$build; HealthToolsMsiPath=$HealthToolsMsiPath"
    }

    $lastCode = Invoke-MsiExec -Arguments ('/i "{0}" /qn /norestart' -f $HealthToolsMsiPath)
    Write-IRTLog "msiexec /i returned $lastCode"

    $after = Get-HealthToolsState
    if (-not ($after.Service -or $after.Uninstall -or $after.Folder)) {
        Exit-Script 1 "Failed | Action=Install; Build=$build; ExitCode=$lastCode; HealthTools=Absent"
    }
    Exit-Script 0 "Fixed | Action=Install; Build=$build; ExitCode=$lastCode; Service=$($after.Service); UninstallEntry=$($after.Uninstall)"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
