[System.Text.StringBuilder]$global:Report = [System.Text.StringBuilder]::new()
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Log {
    param([string]$Message,[string]$Level="INFO")
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    [void]$global:Report.AppendLine("[$Time] [$Level] $Message")
}

function Write-Report {
    $Raw = $global:Report.ToString()
    $Cleaned = $Raw -split [Environment]::NewLine |
        Where-Object { $_.Trim() } |
        ForEach-Object {
            $_ -replace '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[\w+\] ', '' |
            ForEach-Object { $_ -replace 's', 's' -replace 'S', 'S' -replace 'i', 'i' -replace 'I', 'I' `
                                 -replace 'g', 'g' -replace 'G', 'G' -replace 'u', 'u' -replace 'U', 'U' `
                                 -replace 'o', 'o' -replace 'O', 'O' -replace 'c', 'c' -replace 'C', 'C' }
        }
    $Output = $Cleaned -join ' ___ '
    if ([string]::IsNullOrWhiteSpace($Output)) { $Output = "OneDrive saglikli" }
    $Output | Write-Output
}

Write-Log "##############"
Write-Log "ONEDRIVE HEALTH DETECTION"
Write-Log "##############"
Write-Log "Bilgisayar: $env:COMPUTERNAME"

try {
    $LoggedOnUser = (Get-CimInstance Win32_ComputerSystem).UserName
    if ([string]::IsNullOrWhiteSpace($LoggedOnUser)) { throw "Oturum acmis kullanici yok." }
    Write-Log "Kullanici: $LoggedOnUser"

    $UserSID = (New-Object System.Security.Principal.NTAccount($LoggedOnUser)).Translate(
        [System.Security.Principal.SecurityIdentifier]).Value
    $UserProfile = (Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $UserSID }).LocalPath
    if ([string]::IsNullOrWhiteSpace($UserProfile)) { throw "Profil klasoru bulunamadi." }

    $HKU_AccountsRoot = "Registry::HKEY_USERS\$UserSID\Software\Microsoft\OneDrive\Accounts"
    $OneDriveLogRoot = "$UserProfile\AppData\Local\Microsoft\OneDrive\logs"

    $BusinessAccounts = Get-ChildItem $HKU_AccountsRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "Business*" }
    $UserEmail = $null
    if ($BusinessAccounts) {
        $Account = $BusinessAccounts | Select-Object -First 1
        $UserEmail = $Account.GetValue("UserEmail")
        $UserFolder = $Account.GetValue("UserFolder")
        $AccountConfigured = $UserEmail -and $UserFolder -and (Test-Path $UserFolder -ErrorAction SilentlyContinue)
    } else {
        $AccountConfigured = $false
    }

    if (-not $AccountConfigured) {
        Write-Log "[DETECT] Hesap yapilandirilmamis." "ERROR"
        Write-Report
        Exit 1
    }
    Write-Log "Hesap: $UserEmail"

    $OneDriveProcess = Get-Process OneDrive -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -ne 0 } | Select-Object -First 1
    if (-not $OneDriveProcess) {
        Write-Log "[DETECT] OneDrive calismiyor." "ERROR"
        Write-Report
        Exit 1
    }
    Write-Log "[OK] OneDrive calisiyor (PID: $($OneDriveProcess.Id))."

    $LogFiles = Get-ChildItem -Path $OneDriveLogRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "Business*" } |
        ForEach-Object { Get-ChildItem -Path $_.FullName -Filter "SyncDiagnostics.log" -ErrorAction SilentlyContinue }
    if (-not $LogFiles) {
        Write-Log "[DETECT] SyncDiagnostics.log bulunamadi." "ERROR"
        Write-Report
        Exit 1
    }

    $LatestLog = $LogFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $LogContent = Get-Content $LatestLog.FullName -ErrorAction SilentlyContinue
    $StatusCode = $null
    foreach ($Line in $LogContent) {
        if ($Line -match '(?i)SyncProgressState\s*[:=]\s*(\d+)') { $StatusCode = [int]$Matches[1] }
    }

    if ($null -eq $StatusCode) {
        Write-Log "[DETECT] SyncProgressState okunamadi." "ERROR"
        Write-Report
        Exit 1
    }

    Write-Log "SyncProgressState: $StatusCode"

    $ErrorCodes = @(65536, 8194, 1854, 1580)
    if ($StatusCode -in $ErrorCodes) {
        Write-Log "[DETECT] Hata kodu tespit edildi: $StatusCode" "ERROR"
        Write-Report
        Exit 1
    }

    Write-Log "Durum: SAGLIKLI"
    Write-Report
    Exit 0

} catch {
    Write-Log "[DETECT] $($_.Exception.Message)" "ERROR"
    Write-Report
    Exit 1
}
