[System.Text.StringBuilder]$global:Report = [System.Text.StringBuilder]::new()
$OutputEncoding = [System.Text.Encoding]::UTF8
$LogFolder = "C:\Temp"
$LogFile = Join-Path $LogFolder "OneDriveHealthRemediation.log"

if (!(Test-Path $LogFolder)) { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }
if (Test-Path $LogFile) { Remove-Item $LogFile -Force }

function Write-Log {
    param([string]$Message,[string]$Level="INFO")
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Time] [$Level] $Message"
    [void]$global:Report.AppendLine($Line)
    Add-Content -Path $LogFile -Value $Line -ErrorAction SilentlyContinue
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
    if ([string]::IsNullOrWhiteSpace($Output)) { $Output = "OneDriveHealthRemediation calisti" }
    $Output | Write-Output
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Starter {
    [DllImport("wtsapi32.dll")] static extern bool WTSQueryUserToken(int ses, out IntPtr t);
    [DllImport("advapi32.dll")] static extern bool DuplicateTokenEx(IntPtr t, uint a, IntPtr p, int l, int ty, out IntPtr n);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode)] static extern bool CreateProcessAsUser(IntPtr t, string a, string c, IntPtr pa, IntPtr ta, bool i, uint f, IntPtr e, string d, ref SI s, out PI p);
    [DllImport("userenv.dll", CharSet=CharSet.Unicode)] static extern bool CreateEnvironmentBlock(out IntPtr env, IntPtr token, bool inherit);
    [DllImport("userenv.dll")] static extern bool DestroyEnvironmentBlock(IntPtr env);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern uint GetLastError();

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct SI {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public uint dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars;
        public uint dwFillAttribute;
        public uint dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput, hStdOutput, hStdError;
    }
    struct PI { public IntPtr hProcess,hThread; public int dwProcessId; public int dwThreadId; }

    public static int Start(string cmd, int ses, string workDir, out string err) {
        err = null; IntPtr t, n;
        if (!WTSQueryUserToken(ses, out t)) { err = "WTSQueryUserToken failed: " + GetLastError(); return 0; }
        if (!DuplicateTokenEx(t, 0x000F01FF, IntPtr.Zero, 2, 1, out n)) { err = "DuplicateTokenEx failed: " + GetLastError(); CloseHandle(t); return 0; }
        CloseHandle(t);
        IntPtr env = IntPtr.Zero;
        CreateEnvironmentBlock(out env, n, false);
        SI s = new SI();
        s.cb = Marshal.SizeOf(typeof(SI)); s.lpDesktop = "winsta0\\default"; s.dwFlags = 1; s.wShowWindow = 0;
        PI p;
        if (!CreateProcessAsUser(n, null, cmd, IntPtr.Zero, IntPtr.Zero, false, 0x00000410, env, workDir, ref s, out p)) {
            err = "CreateProcessAsUser failed: " + GetLastError();
            if (env != IntPtr.Zero) DestroyEnvironmentBlock(env); CloseHandle(n); return 0;
        }
        if (env != IntPtr.Zero) DestroyEnvironmentBlock(env);
        CloseHandle(n); CloseHandle(p.hProcess); CloseHandle(p.hThread);
        return p.dwProcessId;
    }
}
"@

function Start-OneDriveProcess {
    param([string]$ExePath, [string]$UserProfile, [string]$Arguments="/background")
    $IsSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
    if ($IsSystem) {
        $ExplorerSession = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Select-Object -First 1
        if (-not $ExplorerSession) { throw "Aktif session bulunamadi." }
        $SessionId = $ExplorerSession.SessionId
        Write-Log "SYSTEM context, Session ID: $SessionId"
        $CmdLine = "`"$ExePath`" $Arguments"
        $ErrMsg = $null
        $NewPID = [Starter]::Start($CmdLine, $SessionId, $UserProfile, [ref]$ErrMsg)
        if ($NewPID -le 0) { throw $ErrMsg }
        Write-Log "OneDrive baslatildi (PID: $NewPID, Session: $SessionId)."
        return $NewPID
    } else {
        $proc = Start-Process -FilePath $ExePath -ArgumentList $Arguments -WindowStyle Hidden -PassThru
        Write-Log "OneDrive baslatildi (PID: $($proc.Id), User context)."
        return $proc.Id
    }
}

Write-Log "##############"
Write-Log "ONEDRIVE HEALTH REMEDIATION"
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
    Write-Log "Profil: $UserProfile"

    $HKU_AccountsRoot = "Registry::HKEY_USERS\$UserSID\Software\Microsoft\OneDrive\Accounts"

    $BusinessAccounts = Get-ChildItem $HKU_AccountsRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "Business*" }
    $UserEmail = $null
    $UserFolder = $null
    if ($BusinessAccounts) {
        $Account = $BusinessAccounts | Select-Object -First 1
        $UserEmail = $Account.GetValue("UserEmail")
        $UserFolder = $Account.GetValue("UserFolder")
        $DisplayName = $Account.GetValue("DisplayName")
    }

    $OneDrivePaths = @(
        "$UserProfile\AppData\Local\Microsoft\OneDrive\OneDrive.exe"
        "C:\Program Files\Microsoft OneDrive\OneDrive.exe"
        "${env:ProgramFiles}\Microsoft OneDrive\OneDrive.exe"
        "C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe"
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
    )
    $OneDriveExe = $OneDrivePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $OneDriveExe) { throw "OneDrive.exe bulunamadi." }
    Write-Log "OneDrive.exe: $OneDriveExe"

} catch {
    Write-Log "[ERROR] $($_.Exception.Message)" "ERROR"
    Write-Report; Exit 1
}

# ========== REMEDIATION 1: Baslangicta calisma kaydi ==========
$IsSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
$RunKeyPath = if ($IsSystem) {
    "Registry::HKEY_USERS\$UserSID\Software\Microsoft\Windows\CurrentVersion\Run"
} else {
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
}
$RunValueName = "OneDrive"
$RunValueData = '"C:\Program Files\Microsoft OneDrive\OneDrive.exe" /background'

try {
    $Existing = Get-ItemProperty -Path $RunKeyPath -Name $RunValueName -ErrorAction Stop
    Write-Log "[OK] Baslangicta calisma zaten aktif."
} catch {
    Write-Log "[ACTION] Baslangicta calisma kaydi olusturuluyor..."
    try {
        New-ItemProperty -Path $RunKeyPath -Name $RunValueName -Value $RunValueData -PropertyType String -Force | Out-Null
        Write-Log "[OK] Baslangicta calisma kaydi olusturuldu."
    } catch {
        Write-Log "[WARNING] Baslangicta calisma kaydi olusturulamadi: $($_.Exception.Message)" "WARNING"
    }
}

# ========== REMEDIATION 2: OneDrive process baslat ==========
$ExistingProcess = Get-Process OneDrive -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -ne 0 } | Select-Object -First 1

if (-not $ExistingProcess) {
    Write-Log "[ACTION] OneDrive calismiyor. Baslatiliyor..."
    try {
        Start-OneDriveProcess -ExePath $OneDriveExe -UserProfile $UserProfile
        Start-Sleep -Seconds 15
        $AfterStart = Get-Process OneDrive -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -ne 0 } | Select-Object -First 1
        if ($AfterStart) {
            Write-Log "[OK] OneDrive baslatildi (PID: $($AfterStart.Id))."
        } else {
            Write-Log "[WARNING] OneDrive baslatilamadi." "WARNING"
        }
    } catch {
        Write-Log "[WARNING] Baslatma hatasi: $($_.Exception.Message)" "WARNING"
    }
} else {
    Write-Log "[OK] OneDrive zaten calisiyor (PID: $($ExistingProcess.Id))."
}

# ========== REMEDIATION 3: Silent Account Config (hesap yoksa) ==========
if (-not $UserEmail) {
    Write-Log "[ACTION] Hesap bulunamadi. Silent Account Configuration kontrol ediliyor..."
    $PolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
    $SilentConfig = $null
    try { $SilentConfig = (Get-ItemProperty -Path $PolicyPath -Name "SilentAccountConfig" -ErrorAction Stop).SilentAccountConfig } catch {}
    if ($SilentConfig -eq 1) {
        Write-Log "[ACTION] Silent Account Configuration policy AKTIF."
        $IsSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
        $ODBaseKey = if ($IsSystem) { "Registry::HKEY_USERS\$UserSID\Software\Microsoft\OneDrive" } else { "HKCU:\Software\Microsoft\OneDrive" }

        try {
            if (Test-Path "$ODBaseKey\Accounts") { Remove-Item "$ODBaseKey\Accounts" -Recurse -Force -ErrorAction SilentlyContinue; Write-Log "[CLEAN] Accounts registry temizlendi." }
            $SettingsDir = "$UserProfile\AppData\Local\Microsoft\OneDrive\settings"
            if (Test-Path $SettingsDir) { Remove-Item "$SettingsDir\Business*" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item "$SettingsDir\Personal*" -Recurse -Force -ErrorAction SilentlyContinue; Write-Log "[CLEAN] Settings klasoru temizlendi." }
            $LogsCache = "$UserProfile\AppData\Local\Microsoft\OneDrive\logs"
            if (Test-Path $LogsCache) { Remove-Item "$LogsCache\Business*" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item "$LogsCache\Personal*" -Recurse -Force -ErrorAction SilentlyContinue; Write-Log "[CLEAN] Logs cache temizlendi." }
        } catch { Write-Log "[WARNING] Temizlik hatasi: $($_.Exception.Message)" "WARNING" }

        $StaleKeys = @('SilentBusinessConfigCompleted','ClientEverSignedIn','PersonalUnlinkedTimeStamp','OneAuthUnrecoverableTimestamp')
        foreach ($key in $StaleKeys) {
            try { Remove-ItemProperty -Path $ODBaseKey -Name $key -Force -ErrorAction SilentlyContinue; Write-Log "[CLEAN] $key temizlendi." } catch {}
        }

        Write-Log "[ACTION] OneDrive yeniden baslatiliyor (sign-in mod)..."
        $OldProcesses = Get-Process OneDrive -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -ne 0 }
        foreach ($p in $OldProcesses) { try { $p.Kill(); Write-Log "Durduruldu: PID $($p.Id)" } catch {} }
        Start-Sleep -Seconds 5

        try {
            $SACProcId = Start-OneDriveProcess -ExePath $OneDriveExe -UserProfile $UserProfile -Arguments ""
            Write-Log "[OK] OneDrive baslatildi (PID: $SACProcId). Silent sign-in bekleniyor (45sn)..."
            Start-Sleep -Seconds 45
        } catch {
            Write-Log "[WARNING] Silent sign-in sirasinda hata: $($_.Exception.Message)" "WARNING"
        }
    } else {
        Write-Log "[WARNING] Silent Account Configuration policy bulunamadi veya devre disi." "WARNING"
    }
}

# ========== REMEDIATION 4: Sync fix (process restart + db cleanup) ==========
Write-Log "[ACTION] OneDrive process restart ve db cleanup uygulaniyor..."

$OldProcesses = Get-Process OneDrive -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -ne 0 }
foreach ($p in $OldProcesses) {
    Write-Log "Durduruluyor: PID $($p.Id)..."
    $p.Kill()
}
Start-Sleep -Seconds 5

$SettingsDir = "$UserProfile\AppData\Local\Microsoft\OneDrive\settings\Business1"
if (Test-Path $SettingsDir) {
    $removedWal = $false
    Get-ChildItem -Path $SettingsDir -Filter "*.db-wal" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Log "Temizlendi: $($_.Name)"
        $removedWal = $true
    }
    Get-ChildItem -Path $SettingsDir -Filter "*.db-shm" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Log "Temizlendi: $($_.Name)"
    }
    if ($removedWal) { Write-Log "[OK] Pause state database dosyalari temizlendi." }
}

try {
    Start-OneDriveProcess -ExePath $OneDriveExe -UserProfile $UserProfile
    Start-Sleep -Seconds 15
    $AfterRestart = Get-Process OneDrive -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -ne 0 } | Select-Object -First 1
    if ($AfterRestart) {
        Write-Log "[OK] OneDrive yeniden baslatildi (PID: $($AfterRestart.Id))."
    } else {
        Write-Log "[WARNING] OneDrive yeniden baslatilamadi." "WARNING"
    }
} catch {
    Write-Log "[WARNING] Yeniden baslatma hatasi: $($_.Exception.Message)" "WARNING"
}

Write-Log "##############"
Write-Log "REMEDIATION TAMAMLANDI"
Write-Log "##############"
Write-Report; Exit 0
