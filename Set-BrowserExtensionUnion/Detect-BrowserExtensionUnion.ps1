<#
.SYNOPSIS
  Detection script for merged Edge and Chrome force-install lists.

.DESCRIPTION
  Unions administrator-selected group lists and checks machine policy entries.
  Exits 1 for missing entries, conflicting sources or invalid configuration.
  Exits 0 when all required entries exist or no entries are configured.
  Group membership is supplied by deployment targeting, not discovered locally.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExtensionGroups = @(
    @{ Browser = 'Edge'; Entries = @() }
    @{ Browser = 'Chrome'; Entries = @() }
)
$PolicyOwnershipConfirmed = $false

$PackageName = 'BrowserExtensionUnion'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try {
        $directory = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null }
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function ConvertTo-ExtensionEntry { param([string]$Text, [string]$Browser)
    $parts = $Text.Trim().Split(';')
    if ($parts.Count -gt 2 -or $parts[0] -cnotmatch '^[a-p]{32}$') { throw 'InvalidExtensionEntry' }
    $url = if ($Browser -eq 'Edge') { 'https://edge.microsoft.com/extensionwebstorebase/v1/crx' } else { 'https://clients2.google.com/service/update2/crx' }
    if ($parts.Count -eq 2) { $url = $parts[1] }
    $uri = $null
    if (-not [uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri)) { throw 'InvalidUpdateUrl' }
    if ($uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Fragment -or $url -match '\s') { throw 'HttpsUpdateUrlRequired' }
    [pscustomobject]@{ Id = $parts[0]; Url = $url; Entry = ($parts[0] + ';' + $url) }
}

function Get-ExpectedExtension {
    $unique = @{}
    foreach ($group in $ExtensionGroups) {
        if ($group.Browser -cnotin @('Edge', 'Chrome')) { throw 'InvalidBrowser' }
        foreach ($text in $group.Entries) {
            if ($text -isnot [string]) { throw 'InvalidExtensionEntry' }
            $entry = ConvertTo-ExtensionEntry -Text $text -Browser $group.Browser
            $key = $group.Browser + '/' + $entry.Id
            if ($unique.ContainsKey($key) -and $unique[$key].Entry -cne $entry.Entry) { throw 'GroupUpdateUrlConflict' }
            $unique[$key] = [pscustomobject]@{ Browser = $group.Browser; Id = $entry.Id; Entry = $entry.Entry }
        }
    }
    $unique.Values | Sort-Object Browser, Id
}

function Get-ExtensionPlan { param([object[]]$Expected)
    foreach ($browser in @('Edge', 'Chrome')) {
        $required = @($Expected | Where-Object { $_.Browser -eq $browser })
        if ($required.Count -eq 0) { continue }
        $parentPath = if ($browser -eq 'Edge') { 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' } else { 'HKLM:\SOFTWARE\Policies\Google\Chrome' }
        if (Test-Path -LiteralPath $parentPath -ErrorAction Stop) {
            $parent = Get-Item -LiteralPath $parentPath -ErrorAction Stop
            try {
                if ($parent.GetValueNames() -contains 'ExtensionSettings') { throw 'ExtensionSettingsRequiresReview' }
            } finally { $parent.Close() }
        }
        $path = $parentPath + '\ExtensionInstallForcelist'
        $existing = @{}
        $names = @()
        if (Test-Path -LiteralPath $path -ErrorAction Stop) {
            $item = Get-Item -LiteralPath $path -ErrorAction Stop
            try {
                $names = @($item.GetValueNames())
                foreach ($name in $names) {
                    if ($name -eq '') { continue }
                    if ($name -notmatch '^[1-9][0-9]*$') { throw 'UnexpectedValueName' }
                    if ($item.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::String) { throw 'UnexpectedValueType' }
                    $entry = ConvertTo-ExtensionEntry -Text ([string]$item.GetValue($name)) -Browser $browser
                    if ($existing.ContainsKey($entry.Id) -and $existing[$entry.Id] -cne $entry.Entry) { throw 'ExistingUpdateUrlConflict' }
                    $existing[$entry.Id] = $entry.Entry
                }
            } finally { $item.Close() }
        }
        foreach ($entry in $required) {
            if ($existing.ContainsKey($entry.Id) -and $existing[$entry.Id] -cne $entry.Entry) { throw 'RequiredUpdateUrlConflict' }
        }
        $missing = @($required | Where-Object { -not $existing.ContainsKey($_.Id) })
        [pscustomobject]@{ Browser = $browser; Path = $path; Names = $names; Missing = $missing }
    }
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $expected = @(Get-ExpectedExtension)
    if ($expected.Count -eq 0) { Exit-Script 0 'NotApplicable | ConfiguredEntries=0' }
    $plan = @(Get-ExtensionPlan -Expected $expected)
    $missingCount = @($plan | ForEach-Object { $_.Missing }).Count
    if ($missingCount -gt 0) { Exit-Script 1 "Drift | Required=$($expected.Count); Missing=$missingCount; OwnershipConfirmed=$PolicyOwnershipConfirmed" }
    Exit-Script 0 "Healthy | Required=$($expected.Count); Missing=0; Scope=MachinePolicy"
} catch {
    $reason = $_.Exception.Message
    if ($reason -notmatch '^[A-Za-z]+$') { $reason = $_.Exception.GetType().Name }
    Exit-Script 1 "Error: Failed | Reason=$reason"
}
