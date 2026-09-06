<#
.SYNOPSIS
    Intune Proactive Remediation - Detection: Classic Teams uninstall registry key denetimi

.DESCRIPTION
    Tum kullanicilarin HKEY_USERS\<sid>\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Teams
    kaydini kontrol eder. Kayit varsa exit 1 (remediation tetiklenir), yoksa exit 0 (saglikli).
    Log: C:\Temp\IntunePR-Teams-UninstallKey-Detection.log
#>

$LogPath = "C:\Temp\IntunePR-Teams-UninstallKey-Detection.log"

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

$ErrorActionPreference = 'SilentlyContinue'
$regKeyRel = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Teams'
$teamsKeyFound = $false

try {
    $profiles = Get-CimInstance Win32_UserProfile |
        Where-Object { $_.Special -eq $false }

    Write-Log "Detection baslatildi. Taranan profil sayisi: $($profiles.Count)"

    foreach ($profile in $profiles) {
        $userName = Split-Path $profile.LocalPath -Leaf
        $hiveName = "TEMP_DetectTeams_$($profile.SID)"
        $hiveLoaded = $false

        if (Test-Path "Registry::HKEY_USERS\$($profile.SID)\$regKeyRel") {
            $teamsKeyFound = $true
            Write-Log "TEAMS-KEY-FOUND | Kullanici: $userName | SID: $($profile.SID) | Konum: yuklu profil"
        }
        else {
            $ntUserDat = Join-Path $profile.LocalPath 'NTUSER.DAT'
            if (Test-Path $ntUserDat) {
                $null = reg.exe load "HKU\$hiveName" "$ntUserDat" 2>&1
                if (Test-Path "Registry::HKEY_USERS\$hiveName\$regKeyRel") {
                    $teamsKeyFound = $true
                    Write-Log "TEAMS-KEY-FOUND | Kullanici: $userName | SID: $($profile.SID) | Konum: offline profil"
                }
                $null = reg.exe unload "HKU\$hiveName" 2>&1
            }
        }
        Write-Log "Profil kontrol edildi: $userName"
    }

    Write-Log "Detection tamamlandi. Sonuc: $teamsKeyFound"
}
catch {
    Write-Log "HATA: $($_.Exception.Message)"
    exit 1
}

if ($teamsKeyFound) { exit 1 } else { exit 0 }