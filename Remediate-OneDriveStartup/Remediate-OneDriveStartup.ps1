[Console]::OutputEncoding = [Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

$RunValueName = "OneDrive"
$RunValueData = '"C:\Program Files\Microsoft OneDrive\OneDrive.exe" /background'
$OneDrivePath = "C:\Program Files\Microsoft OneDrive\OneDrive.exe"
$LogFile = "C:\Temp\Remediate_OneDrive_Startup.log"

function Write-Log {
    param([string]$Message)
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$TimeStamp - $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Host $Message
}

if (-not (Test-Path -LiteralPath $OneDrivePath)) {
    Write-Log "Uyari: OneDrive.exe dosyasi bulunamadi - $OneDrivePath"
}

$IsSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem

if ($IsSystem) {
    $UserSID = (Get-CimInstance Win32_UserProfile | Where-Object { $_.Loaded -eq $true }).SID
    if (-not $UserSID) {
        Write-Log "Hata: Su anda yuklu bir kullanici profili bulunamadi"
        exit 1
    }
    $RunKeyPath = "Registry::HKEY_USERS\$UserSID\Software\Microsoft\Windows\CurrentVersion\Run"
} else {
    $RunKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
}

try {
    $Existing = Get-ItemProperty -Path $RunKeyPath -Name $RunValueName -ErrorAction Stop
    if ($Existing.$RunValueName -eq $RunValueData) {
        Write-Log "Uyumlu: OneDrive baslangic kaydi zaten dogru degerle mevcut. Islem yapilmadi."
        exit 0
    } else {
        Write-Log "OneDrive baslangic kaydi guncelleniyor..."
        Set-ItemProperty -Path $RunKeyPath -Name $RunValueName -Value $RunValueData
        Write-Log "Duzeltildi: OneDrive baslangic kaydi basariyla guncellendi."
        exit 0
    }
} catch {
    Write-Log "OneDrive baslangic kaydi olusturuluyor..."
    New-ItemProperty -Path $RunKeyPath -Name $RunValueName -Value $RunValueData -PropertyType String -Force
    Write-Log "Duzeltildi: OneDrive baslangic kaydi basariyla olusturuldu."
    exit 0
}
