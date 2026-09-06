[Console]::OutputEncoding = [Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

$RunValueName = "OneDrive"
$RunValueData = '"C:\Program Files\Microsoft OneDrive\OneDrive.exe" /background'
$OneDrivePath = "C:\Program Files\Microsoft OneDrive\OneDrive.exe"
$LogFile = "C:\Temp\Detect_OneDrive_Startup.log"

function Write-Log {
    param([string]$Message)
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$TimeStamp - $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Host $Message
}

if (-not (Test-Path -LiteralPath $OneDrivePath)) {
    Write-Log "Uyumsuz: OneDrive.exe dosyasi bulunamadi - $OneDrivePath"
    exit 1
} else {
    Write-Log "OneDrive.exe dosyasi mevcut - $OneDrivePath"
}

$IsSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem

if ($IsSystem) {
    $UserSID = (Get-CimInstance Win32_UserProfile | Where-Object { $_.Loaded -eq $true }).SID
    if (-not $UserSID) {
        Write-Log "Uyumsuz: Su anda yuklu bir kullanici profili bulunamadi"
        exit 1
    }
    $RunKeyPath = "Registry::HKEY_USERS\$UserSID\Software\Microsoft\Windows\CurrentVersion\Run"
} else {
    $RunKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
}

try {
    $Existing = Get-ItemProperty -Path $RunKeyPath -Name $RunValueName -ErrorAction Stop
    if ($Existing.$RunValueName -eq $RunValueData) {
        Write-Log "Uyumlu: OneDrive baslangic kaydi dogru degerle mevcut"
        exit 0
    } else {
        Write-Log "Uyumsuz: OneDrive baslangic kaydi mevcut ancak deger hatali"
        Write-Log "Beklenen: $RunValueData"
        Write-Log "Mevcut:   $($Existing.$RunValueName)"
        exit 1
    }
} catch {
    Write-Log "Uyumsuz: OneDrive baslangic kaydi bulunamadi - $RunKeyPath"
    exit 1
}
