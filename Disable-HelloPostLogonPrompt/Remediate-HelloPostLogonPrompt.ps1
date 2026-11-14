<#
.SYNOPSIS
  Remediation script that turns off the Windows Hello for Business setup prompt after sign-in.

.DESCRIPTION
  Sets DisablePostLogonProvisioning so Windows Hello for Business stays available but is not forced after sign-in. Does not change devices managed by an MDM policy. Exits 0 if the value is set, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SkipDomainJoinedWithoutPolicy = $true

$PackageName = 'HelloPostLogonPrompt'
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

$GpoKey  = 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'
$MdmRoot = 'HKLM:\SOFTWARE\Microsoft\Policies\PassportForWork'

function Get-MdmHelloPolicy {
    foreach ($tenant in Get-ChildItem -LiteralPath $MdmRoot -ErrorAction SilentlyContinue) {
        $policy = Get-ItemProperty -LiteralPath (Join-Path $tenant.PSPath 'Device\Policies') -ErrorAction SilentlyContinue
        if ($null -ne $policy.UsePassportForWork -or $null -ne $policy.DisablePostLogonProvisioning) {
            return [pscustomobject]@{ UsePassportForWork = $policy.UsePassportForWork; DisablePostLogonProvisioning = $policy.DisablePostLogonProvisioning }
        }
    }
    return $null
}

function Get-GpoHelloPolicy {
    $policy = Get-ItemProperty -LiteralPath $GpoKey -ErrorAction SilentlyContinue
    [pscustomobject]@{ Enabled = $policy.Enabled; DisablePostLogonProvisioning = $policy.DisablePostLogonProvisioning }
}

function Format-Value { param($Value) if ($null -eq $Value) { 'NotSet' } else { "$Value" } }

try {
    $mdm = Get-MdmHelloPolicy
    if ($mdm) { Exit-Script 0 'ManagedByMDM | No change made' }

    if (-not (Test-Path -LiteralPath $GpoKey)) { New-Item -Path $GpoKey -Force -ErrorAction Stop | Out-Null }

    $before = Get-GpoHelloPolicy
    if ($null -eq $before.Enabled) {
        New-ItemProperty -LiteralPath $GpoKey -Name Enabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
        Write-IRTLog 'Enabled was not set, written as 1'
    }
    New-ItemProperty -LiteralPath $GpoKey -Name DisablePostLogonProvisioning -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null

    $after   = Get-GpoHelloPolicy
    $summary = "Enabled=$(Format-Value $after.Enabled); DisablePostLogonProvisioning=$(Format-Value $after.DisablePostLogonProvisioning)"
    if ($after.DisablePostLogonProvisioning -eq 1) { Exit-Script 0 "Applied | $summary" }
    Exit-Script 1 "Failed | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
