<#
.SYNOPSIS
  Detection script for Microsoft Defender Antivirus exclusions that were added locally.

.DESCRIPTION
  Compares the effective Defender exclusion list with the exclusions that come from policy and reports the ones that are left. Exits 1 if a local exclusion is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$IgnorePaths      = @()
$MaxItemsInOutput = 6

$PackageName = 'DefenderLocalExclusions'
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

$ExclusionTypes = @{
    Paths      = 'ExclusionPath'
    Extensions = 'ExclusionExtension'
    Processes  = 'ExclusionProcess'
}
$TypeOrder      = @('Paths', 'Extensions', 'Processes')
$PolicyRoot     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions'
$PolicyMdmKey   = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Defender'
$PolicyMdmNames = @{ Paths = 'ExcludedPaths'; Extensions = 'ExcludedExtensions'; Processes = 'ExcludedProcesses' }

function ConvertTo-NormalValue { param([string]$Value)
    if (-not $Value) { return '' }
    return $Value.Trim().TrimEnd('\').ToLowerInvariant()
}

function Add-KeySetValue { param([hashtable]$Set, [string]$Value)
    if (-not $Value) { return }
    $key = ConvertTo-NormalValue $Value
    if ($key) { $Set[$key] = $true }
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($Value)
        $key = ConvertTo-NormalValue $expanded
        if ($key) { $Set[$key] = $true }
    } catch { }
}

function New-KeySet { param([string[]]$Values)
    $set = @{}
    foreach ($value in $Values) { Add-KeySetValue -Set $set -Value $value }
    $set
}

function Get-EffectiveExclusion {
    $result = @{ Paths = @(); Extensions = @(); Processes = @() }
    $preference = $null
    try { $preference = Get-MpPreference -ErrorAction Stop }
    catch {
        try { $preference = Get-CimInstance -Namespace 'root/Microsoft/Windows/Defender' -ClassName MSFT_MpPreference -ErrorAction Stop }
        catch { $preference = $null }
    }
    if ($null -eq $preference) { return $null }
    foreach ($type in $TypeOrder) {
        $name = $ExclusionTypes[$type]
        $result[$type] = @((@($preference.$name)) | Where-Object { $_ })
    }
    $result
}

function Get-PolicyExclusion {
    $result = @{ Paths = @(); Extensions = @(); Processes = @() }
    foreach ($type in $TypeOrder) {
        $values = @()
        $subKey = Join-Path $PolicyRoot $type
        if (Test-Path -LiteralPath $subKey) {
            $properties = Get-ItemProperty -LiteralPath $subKey -ErrorAction SilentlyContinue
            if ($properties) {
                foreach ($property in $properties.PSObject.Properties) {
                    if ($property.Name -like 'PS*') { continue }
                    if ($property.Value -is [array]) { $values += @($property.Value); continue }
                    if ($property.Name -like 'Exclusions_*') {
                        if ($property.Value -is [string] -and $property.Value) { $values += @($property.Value -split '\|') }
                        continue
                    }
                    $values += [string]$property.Name
                }
            }
        }
        if (Test-Path -LiteralPath $PolicyMdmKey) {
            $mdmName = $PolicyMdmNames[$type]
            $mdm = Get-ItemProperty -LiteralPath $PolicyMdmKey -Name $mdmName -ErrorAction SilentlyContinue
            if ($mdm) {
                $mdmValue = $mdm.$mdmName
                if ($mdmValue) { $values += @((@($mdmValue) -join '|') -split '\|') }
            }
        }
        $result[$type] = @($values | Where-Object { $_ })
    }
    $result
}

function Get-LocalExclusion { param($Effective, $Policy, [string[]]$Ignore)
    $local = @{ Paths = @(); Extensions = @(); Processes = @() }
    $ignoreSet = New-KeySet -Values $Ignore
    foreach ($type in $TypeOrder) {
        $policySet = New-KeySet -Values $Policy[$type]
        foreach ($value in $Effective[$type]) {
            $key = ConvertTo-NormalValue $value
            $expandedKey = ConvertTo-NormalValue ([Environment]::ExpandEnvironmentVariables($value))
            if ($policySet.ContainsKey($key) -or $policySet.ContainsKey($expandedKey)) { continue }
            if ($ignoreSet.ContainsKey($key) -or $ignoreSet.ContainsKey($expandedKey)) { continue }
            $local[$type] += $value
        }
    }
    $local
}

function Get-ExclusionCount { param($Set)
    return ($Set.Paths.Count + $Set.Extensions.Count + $Set.Processes.Count)
}

try {
    $effective = Get-EffectiveExclusion
    if ($null -eq $effective) { Exit-Script 0 'NotApplicable | Defender preference not available' }

    $policy = Get-PolicyExclusion
    $local = Get-LocalExclusion -Effective $effective -Policy $policy -Ignore $IgnorePaths

    $effectiveCount = Get-ExclusionCount -Set $effective
    $localCount = Get-ExclusionCount -Set $local
    if ($localCount -eq 0) { Exit-Script 0 "Healthy | Local=0; Effective=$effectiveCount" }

    $items = @()
    foreach ($type in $TypeOrder) {
        foreach ($value in $local[$type]) { $items += ('{0}:{1}' -f $type.Substring(0, 1), $value) }
    }
    $shown = ($items | Select-Object -First $MaxItemsInOutput) -join ', '
    $more = ''
    if ($items.Count -gt $MaxItemsInOutput) { $more = '; More=' + ($items.Count - $MaxItemsInOutput) }

    Exit-Script 1 "Drift | Paths=$($local.Paths.Count); Extensions=$($local.Extensions.Count); Processes=$($local.Processes.Count); Items=$shown$more"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
