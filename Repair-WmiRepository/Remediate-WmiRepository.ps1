<#
.SYNOPSIS
  Remediation script for an inconsistent WMI repository.

.DESCRIPTION
  Rechecks consistency and invokes winmgmt salvage only for the repository corruption code.
  Verifies again after salvage. Never resets or deletes the repository or restarts services.
  Exits 0 when consistent and 1 when repair is disabled, blocked or unsuccessful.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $true
$CommandTimeoutSeconds = 180

$PackageName = 'WmiRepository'
$Phase = 'Remediate'
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
function Invoke-RepositoryCommand { param([string]$Executable, [string]$Argument)
    $process = New-Object System.Diagnostics.Process
    try {
        $process.StartInfo.FileName = $Executable
        $process.StartInfo.Arguments = $Argument
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($CommandTimeoutSeconds * 1000)) {
            throw 'CommandTimeout; ProcessNotTerminated'
        }
        [void]$stdout.GetAwaiter().GetResult()
        [void]$stderr.GetAwaiter().GetResult()
        $code = $process.ExitCode
        Write-IRTLog "Command=$Argument; ExitCode=$code"
        return $code
    }
    finally { $process.Dispose() }
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $executable = Join-Path $env:windir 'System32\wbem\winmgmt.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        Exit-Script 0 'NotApplicable | Reason=WinmgmtMissing'
    }
    $verification = Invoke-RepositoryCommand -Executable $executable -Argument '/verifyrepository'
    if ($verification -eq 0) { Exit-Script 0 'Healthy | Repository=Consistent; VerifyCode=0' }
    if ($verification -notin @(1358, -2147023538)) {
        Exit-Script 1 "Failed | Reason=VerificationError; VerifyCode=$verification; Repair=Blocked"
    }
    if (-not $EnableRemediation) {
        Exit-Script 1 "Drift | Repository=Inconsistent; VerifyCode=$verification; Repair=Disabled"
    }
    $salvage = Invoke-RepositoryCommand -Executable $executable -Argument '/salvagerepository'
    $after = Invoke-RepositoryCommand -Executable $executable -Argument '/verifyrepository'
    if ($salvage -eq 0 -and $after -eq 0) {
        Exit-Script 0 'Fixed | Repository=Consistent; SalvageCode=0; VerifyCode=0'
    }
    Exit-Script 1 "Failed | Reason=SalvageOrVerificationFailed; SalvageCode=$salvage; VerifyCode=$after"
}
catch {
    Write-IRTLog "ErrorType=$($_.Exception.GetType().Name); HResult=$($_.Exception.HResult)" 'ERROR'
    Exit-Script 1 "Error: RepositoryRepairFailed | HResult=$($_.Exception.HResult)"
}
