<#
.SYNOPSIS
  Detection script for Edge and Chrome extensions that are not on the approved list.

.DESCRIPTION
  Reads the extension IDs installed in every Edge and Chrome profile of every local user profile and compares them with the approved list. Exits 1 if an unapproved extension is found. With an empty list it only reports the inventory and exits 0. Report only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedExtensionIds = @()
$Browsers = [ordered]@{
    'Edge'   = 'AppData\Local\Microsoft\Edge\User Data'
    'Chrome' = 'AppData\Local\Google\Chrome\User Data'
}
$MaxListedIds = 40

$PackageName = 'BrowserExtensions'
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

try {
    $approved = @($ApprovedExtensionIds | ForEach-Object { "$_".Trim().ToLowerInvariant() } | Where-Object { $_ })
    $found    = @{}
    $profileCount = 0

    $userProfiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter 'Special=False' -ErrorAction Stop | Where-Object { $_.LocalPath })
    foreach ($userProfile in $userProfiles) {
        foreach ($browser in $Browsers.Keys) {
            $userData = Join-Path $userProfile.LocalPath $Browsers[$browser]
            if (-not (Test-Path -LiteralPath $userData)) { continue }
            $browserProfiles = @(Get-ChildItem -LiteralPath $userData -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
            foreach ($browserProfile in $browserProfiles) {
                $extensionRoot = Join-Path $browserProfile.FullName 'Extensions'
                if (-not (Test-Path -LiteralPath $extensionRoot)) { continue }
                $profileCount++
                $ids = @(Get-ChildItem -LiteralPath $extensionRoot -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[a-p]{32}$' })
                foreach ($id in $ids) {
                    $key = '{0}:{1}' -f $browser, $id.Name
                    if ($found.ContainsKey($key)) { $found[$key]++ } else { $found[$key] = 1 }
                }
            }
        }
    }

    if ($profileCount -eq 0) { Exit-Script 0 'NotApplicable | BrowserProfiles=0' }

    $unapproved = @($found.Keys | Where-Object { $approved -notcontains ($_ -split ':')[1] } | Sort-Object)
    foreach ($key in ($found.Keys | Sort-Object)) { Write-IRTLog ('{0} Profiles={1} Approved={2}' -f $key, $found[$key], ($unapproved -notcontains $key)) }

    $listSource = if ($approved.Count -eq 0) { @($found.Keys | Sort-Object) } else { $unapproved }
    $listed     = @($listSource | Select-Object -First $MaxListedIds | ForEach-Object { '{0}({1})' -f $_, $found[$_] })
    $more       = [math]::Max(0, @($listSource).Count - $MaxListedIds)
    $idText     = if ($listed.Count -gt 0) { $listed -join ',' } else { 'None' }
    if ($more -gt 0) { $idText += ",+$more" }

    $summary = 'Profiles={0}; Installed={1}; Approved={2}; Ids={3}' -f $profileCount, $found.Count, $approved.Count, $idText
    if ($approved.Count -eq 0)    { Exit-Script 0 "Inventory | $summary" }
    if ($unapproved.Count -gt 0)  { Exit-Script 1 "Unapproved ($($unapproved.Count)) | $summary" }
    Exit-Script 0 "Compliant | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
