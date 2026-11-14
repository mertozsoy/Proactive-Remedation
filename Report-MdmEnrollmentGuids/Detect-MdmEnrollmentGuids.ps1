<#
.SYNOPSIS
  Detection script for leftover and duplicate MDM enrollment entries on a device.

.DESCRIPTION
  Reads the enrollment GUIDs under HKLM\SOFTWARE\Microsoft\Enrollments and separates
  active enrollments from leftover records. Reports the ConfigMgr client state, the
  co-managed view and recent auto-enrollment failures from the device event log.
  Exits 1 if a leftover record, duplicate active enrollment or a device with keys but
  no active enrollment is found. Report only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$IntuneProviderId     = 'MS DM Server'
$EnrolledStateValue   = 1
$ConfigMgrServiceName = 'CcmExec'
$EventLookbackDays    = 14
$MaxListedGuids       = 6

$EnrollmentsRoot = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
$GuidPattern     = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
$EnrollEventLog  = 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostic-Provider/Admin'

$PackageName = 'MdmEnrollmentGuids'
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
    if (-not (Test-Path -LiteralPath $EnrollmentsRoot)) { Exit-Script 0 'NotApplicable | EnrollmentsKey=Missing' }

    $enrollmentKeys = @(Get-ChildItem -LiteralPath $EnrollmentsRoot -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match $GuidPattern })
    if ($enrollmentKeys.Count -eq 0) { Exit-Script 0 'NotApplicable | Enrollments=0' }

    $activeIntune = 0
    $activeOther  = 0
    $leftover     = 0
    $providers    = New-Object System.Collections.Generic.List[string]
    $leftoverIds  = New-Object System.Collections.Generic.List[string]

    foreach ($enrollmentKey in $enrollmentKeys) {
        $props    = Get-ItemProperty -LiteralPath $enrollmentKey.PSPath -ErrorAction SilentlyContinue
        $provider = [string]$props.ProviderID
        if ([string]::IsNullOrWhiteSpace($provider)) { $provider = 'Unknown' }
        if (-not $providers.Contains($provider)) { $providers.Add($provider) }

        $state = -1
        if ($null -ne $props.EnrollmentState) {
            try { $state = [int]$props.EnrollmentState } catch { $state = -1 }
        }

        if ($state -eq $EnrolledStateValue) {
            if ($provider -eq $IntuneProviderId) { $activeIntune++ } else { $activeOther++ }
        }
        else {
            $leftover++
            $leftoverIds.Add($enrollmentKey.PSChildName)
        }

        Write-IRTLog ('Guid={0} Provider={1} State={2}' -f $enrollmentKey.PSChildName, $provider, $state)
    }

    $configMgr = 'Absent'
    if (Get-Service -Name $ConfigMgrServiceName -ErrorAction SilentlyContinue) { $configMgr = 'Present' }

    $coManaged = 'No'
    if ($configMgr -eq 'Present' -and $activeIntune -gt 0) { $coManaged = 'Yes' }

    $autoEnrollFail = 'Unknown'
    if (Get-WinEvent -ListLog $EnrollEventLog -ErrorAction SilentlyContinue) {
        $since = (Get-Date).AddDays(-1 * $EventLookbackDays)
        $autoEnrollFail = @(Get-WinEvent -FilterHashtable @{
            LogName = $EnrollEventLog; Id = 76; StartTime = $since
        } -ErrorAction SilentlyContinue).Count
    }

    $issues = New-Object System.Collections.Generic.List[string]
    if ($leftover -gt 0) { $issues.Add("Leftover=$leftover") }
    if ($activeIntune -gt 1) { $issues.Add("DuplicateActive=$activeIntune") }
    if ($activeIntune -eq 0 -and $activeOther -eq 0) { $issues.Add('NoActiveEnrollment') }

    $listed = @($leftoverIds | Select-Object -First $MaxListedGuids)
    $more   = [math]::Max(0, $leftoverIds.Count - $MaxListedGuids)
    $guidText = 'None'
    if ($listed.Count -gt 0) {
        $guidText = $listed -join ','
        if ($more -gt 0) { $guidText += ",+$more" }
    }

    $summary = 'Enrollments={0}; IntuneActive={1}; OtherActive={2}; Leftover={3}; Providers={4}; ConfigMgr={5}; CoManaged={6}; AutoEnrollFail{7}={8}; LeftoverGuids={9}' -f `
        $enrollmentKeys.Count, $activeIntune, $activeOther, $leftover, ($providers -join '/'),
        $configMgr, $coManaged, $EventLookbackDays, $autoEnrollFail, $guidText

    if ($issues.Count -gt 0) { Exit-Script 1 ('Attention ({0}) | {1}' -f ($issues -join ','), $summary) }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
