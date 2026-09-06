<#
.SYNOPSIS
    Intune Proactive Remediation - Remediation: Classic Teams uninstall registry key silme

.DESCRIPTION
    Tum kullanicilarin HKEY_USERS\<sid>\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Teams
    kaydini siler. Kalan varsa exit 1, temizse exit 0.
    Log: C:\Temp\IntunePR-Teams-UninstallKey-Remediation.log
#>

$LogPath = "C:\Temp\IntunePR-Teams-UninstallKey-Remediation.log"

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

$ErrorActionPreference = 'Continue'
$regKeyRel = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Teams'
$removed = $false

try {
    $profiles = Get-CimInstance Win32_UserProfile |
        Where-Object { $_.Special -eq $false }

    Write-Log "Remediation baslatildi. Taranan profil sayisi: $($profiles.Count)"

    foreach ($profile in $profiles) {
        $userName = Split-Path $profile.LocalPath -Leaf
        $hiveName = "TEMP_RemediateTeams_$($profile.SID)"
        $hiveLoaded = $false
        $fullKeyPath = "Registry::HKEY_USERS\$($profile.SID)\$regKeyRel"

        try {
            if (Test-Path $fullKeyPath) {
                Remove-Item $fullKeyPath -Recurse -Force
                Write-Log "KEY-REMOVED | Kullanici: $userName | SID: $($profile.SID) | Konum: yuklu profil | Yol: $fullKeyPath"
                $removed = $true
            }
            else {
                $ntUserDat = Join-Path $profile.LocalPath 'NTUSER.DAT'
                if (Test-Path $ntUserDat) {
                    $null = reg.exe load "HKU\$hiveName" "$ntUserDat" 2>&1
                    $hiveLoaded = $true
                    $tempKeyPath = "Registry::HKEY_USERS\$hiveName\$regKeyRel"
                    if (Test-Path $tempKeyPath) {
                        Remove-Item $tempKeyPath -Recurse -Force
                        Write-Log "KEY-REMOVED | Kullanici: $userName | SID: $($profile.SID) | Konum: offline profil | Yol: $tempKeyPath"
                        $removed = $true
                    }
                }
            }
        }
        catch {
            Write-Log "KEY-REMOVE-ERROR | Kullanici: $userName | SID: $($profile.SID) | Hata: $($_.Exception.Message)"
        }
        finally {
            if ($hiveLoaded) {
                $null = reg.exe unload "HKU\$hiveName" 2>&1
            }
        }
        Write-Log "Profil islendi: $userName"
    }

    # Dogrulama
    $stillPresent = $false
    foreach ($profile in $profiles) {
        $userName = Split-Path $profile.LocalPath -Leaf
        if (Test-Path "Registry::HKEY_USERS\$($profile.SID)\$regKeyRel") { $stillPresent = $true }
        else {
            $hiveName = "TEMP_VerifyTeams_$($profile.SID)"
            $ntUserDat = Join-Path $profile.LocalPath 'NTUSER.DAT'
            if (Test-Path $ntUserDat) {
                $null = reg.exe load "HKU\$hiveName" "$ntUserDat" 2>&1
                if (Test-Path "Registry::HKEY_USERS\$hiveName\$regKeyRel") { $stillPresent = $true }
                $null = reg.exe unload "HKU\$hiveName" 2>&1
            }
        }
        if (-not $stillPresent) {
            Write-Log "KEY-VERIFIED | Kullanici: $userName | SID: $($profile.SID) | Sonuc: temiz"
        }
    }

    Write-Log "Remediation tamamlandi. Silinen anahtar: $removed | Kalan anahtar: $stillPresent"

    if ($removed) {
        Write-Log "Remediation completed."
    } else {
        Write-Log "Key not present in any profile - nothing to remediate."
    }
}
catch {
    Write-Log "HATA: $($_.Exception.Message)"
    exit 1
}

if ($stillPresent) { exit 1 } else { exit 0 }