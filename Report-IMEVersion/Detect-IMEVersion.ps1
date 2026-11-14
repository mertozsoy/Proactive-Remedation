<#
.SYNOPSIS
  Detection script for an Intune Management Extension version below the supported minimum.

.DESCRIPTION
  Reads the installed Intune Management Extension version from the agent executable
  and from the uninstall registry entries. Compares the highest version found with
  the minimum supported version. Exits 1 when the version is old or unreadable,
  0 when it is current or the extension is not installed. Report only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumVersion = '1.58.103.0'
$AgentFolderName = 'Microsoft Intune Management Extension'
$AgentFileName = 'Microsoft.Management.Services.IntuneWindowsAgent.exe'
$UninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

$PackageName = 'IMEVersion'
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

function ConvertTo-FourPartVersion { param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, '\d+(\.\d+){1,3}')
    if (-not $match.Success) { return $null }
    $parts = @($match.Value.Split('.') | ForEach-Object { [int]$_ })
    while ($parts.Count -lt 4) { $parts += 0 }
    try { return [version]($parts -join '.') } catch { return $null }
}

function Get-AgentPath {
    $root = ${env:ProgramFiles(x86)}
    if (-not $root) { $root = $env:ProgramFiles }
    Join-Path (Join-Path $root $AgentFolderName) $AgentFileName
}

function Get-RegistryVersions {
    $versions = @()
    foreach ($root in $UninstallRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            if ([string]$props.DisplayName -notlike '*Intune Management Extension*') { continue }
            $parsed = ConvertTo-FourPartVersion ([string]$props.DisplayVersion)
            if (-not $parsed) { continue }
            $versions += $parsed
        }
    }
    return $versions
}

try {
    $ErrorActionPreference = 'Stop'
    $minimum = ConvertTo-FourPartVersion $MinimumVersion
    if (-not $minimum) { throw 'InvalidMinimumVersion' }

    $agentPath = Get-AgentPath
    $agentPresent = Test-Path -LiteralPath $agentPath
    $fileVersion = $null
    if ($agentPresent) {
        try {
            $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($agentPath)
            $fileVersion = ConvertTo-FourPartVersion $info.FileVersion
            if (-not $fileVersion) { $fileVersion = ConvertTo-FourPartVersion $info.ProductVersion }
        }
        catch { $fileVersion = $null }
        Write-IRTLog ('Agent={0} FileVersion={1}' -f $agentPath, $fileVersion)
    }

    $registryVersions = @(Get-RegistryVersions)
    foreach ($registryVersion in $registryVersions) { Write-IRTLog "RegistryVersion=$registryVersion" }

    $agentState = 'Present'
    if (-not $agentPresent) { $agentState = 'Missing' }

    if (-not $agentPresent -and $registryVersions.Count -eq 0) {
        Exit-Script 0 ('NotApplicable | Agent={0}; RegistryEntries=0' -f $agentState)
    }

    $candidates = @()
    if ($fileVersion) { $candidates += $fileVersion }
    $candidates += $registryVersions

    if ($candidates.Count -eq 0) {
        Exit-Script 1 ('Unknown | Agent={0}; RegistryEntries={1}; Minimum={2}' -f $agentState, $registryVersions.Count, $minimum)
    }

    $installed = @($candidates | Sort-Object -Descending)[0]
    $source = 'Registry'
    if ($fileVersion -and $fileVersion.Equals($installed)) { $source = 'File' }

    $summary = 'Version={0}; Minimum={1}; Source={2}; Agent={3}; RegistryEntries={4}' -f $installed, $minimum, $source, $agentState, $registryVersions.Count
    if ($installed -ge $minimum) { Exit-Script 0 "Current | $summary" }
    Exit-Script 1 "Old | $summary"
}
catch { Exit-Script 1 ('Error | Reason=DetectionFailed; Type={0}' -f $_.Exception.GetType().Name) }
