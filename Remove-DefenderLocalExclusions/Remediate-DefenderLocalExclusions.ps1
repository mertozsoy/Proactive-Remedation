<#
.SYNOPSIS
  Remediation script that removes local Microsoft Defender Antivirus exclusions that are not set by policy.

.DESCRIPTION
  Compares the effective Defender exclusion list with the exclusions that come from policy, backs up the exclusion registry key and removes the local entries with Remove-MpPreference. Policy exclusions are never touched. Exits 0 when no local exclusion is left, 1 when the cleanup fails.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $false
$IgnorePaths       = @()
$MaxItemsInOutput  = 6

$PackageName = 'DefenderLocalExclusions'
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

$ExclusionTypes = @{
    Paths      = 'ExclusionPath'
    Extensions = 'ExclusionExtension'
    Processes  = 'ExclusionProcess'
}
$TypeOrder      = @('Paths', 'Extensions', 'Processes')
$ExclusionRoot  = 'HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions'
$PolicyRoot     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions'
$PolicyMdmKey   = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Defender'
$PolicyMdmNames = @{ Paths = 'ExcludedPaths'; Extensions = 'ExcludedExtensions'; Processes = 'ExcludedProcesses' }
$BackupRoot     = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

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

function Get-TamperState {
    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        return [string]$status.IsTamperProtected
    } catch { return 'Unknown' }
}

function Save-ExclusionBackup {
    $null = New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop
    $file = Join-Path $BackupRoot ('DefenderExclusions-{0}.reg' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $output = & reg.exe export $ExclusionRoot $file /y 2>&1
    if ($LASTEXITCODE -ne 0) { throw "reg export failed with exit code $LASTEXITCODE ($($output -join ' '))" }
    return $file
}

function Remove-ExclusionValue { param([string]$Type, [string]$Value)
    $parameterName = $ExclusionTypes[$Type]
    $parameters = @{ $parameterName = @($Value); ErrorAction = 'Stop' }
    Remove-MpPreference @parameters
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

    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | Local=$localCount; Items=$shown; Toggle=EnableRemediation"
    }

    $backupFile = Save-ExclusionBackup
    Write-IRTLog "Backup written to $backupFile"

    $removed = @{ Paths = 0; Extensions = 0; Processes = 0 }
    $failed = 0
    foreach ($type in $TypeOrder) {
        foreach ($value in $local[$type]) {
            try {
                Remove-ExclusionValue -Type $type -Value $value
                $removed[$type]++
                Write-IRTLog "Local exclusion removed: $type $value"
            } catch {
                $failed++
                Write-IRTLog "Removal failed for $type $value : $($_.Exception.Message)" 'WARN'
            }
        }
    }

    $check = Get-EffectiveExclusion
    if ($null -eq $check) { Exit-Script 1 "Failed | Backup=$backupFile; Preference=unreadable" }

    $policyAfter = Get-PolicyExclusion
    $remaining = Get-LocalExclusion -Effective $check -Policy $policyAfter -Ignore $IgnorePaths
    $left = Get-ExclusionCount -Set $remaining
    $total = $removed.Paths + $removed.Extensions + $removed.Processes
    $afterCount = Get-ExclusionCount -Set $check

    if ($left -eq 0) {
        Exit-Script 0 "Fixed | Removed=$total; Paths=$($removed.Paths); Extensions=$($removed.Extensions); Processes=$($removed.Processes); Effective=$afterCount; Backup=$backupFile"
    }
    Exit-Script 1 "Failed | Removed=$total; Remaining=$left; Failed=$failed; TamperProtected=$(Get-TamperState); Backup=$backupFile"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
