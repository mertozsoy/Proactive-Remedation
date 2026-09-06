<#
.SYNOPSIS
    Intune Proactive Remediation - Remediation: TightVNC guncelleme

.DESCRIPTION
    Guncelleme detection fazinda yapildigi icin bu script durumu loglar ve basarili doner.
    Log: C:\Temp\IntunePR-TightVNC-Remediation.log
#>

$LogPath = "C:\Temp\IntunePR-TightVNC-Remediation.log"

function Write-Log {
    param([string]$Message)
    $line = $Message
    Write-Output $line
    try {
        $dir = Split-Path $LogPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    }
    catch {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] LOG HATASI (dosyaya yazilamadi): $($_.Exception.Message)"
    }
}

Write-Log "Remediation stub calisti. Guncelleme detection fazinda yapildigi icin islem yok."
exit 0