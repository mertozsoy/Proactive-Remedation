$ErrorActionPreference = 'Stop'

function Get-LoggedOnUserSid {
    $explorer = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'explorer.exe'" |
        Select-Object -First 1

    if (-not $explorer) {
        return $null
    }

    $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner
    if (-not $owner.User -or -not $owner.Domain) {
        return $null
    }

    $account = New-Object System.Security.Principal.NTAccount($owner.Domain, $owner.User)
    return $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
}

function Convert-ProgIdToBrowserName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProgId
    )

    switch -Regex ($ProgId) {
        '^MSEdgeHTM' { return 'Microsoft Edge' }
        '^ChromeHTML' { return 'Google Chrome' }
        '^FirefoxURL' { return 'Mozilla Firefox' }
        '^FirefoxHTML' { return 'Mozilla Firefox' }
        '^IE\.' { return 'Internet Explorer' }
        '^Opera' { return 'Opera' }
        '^BraveHTML' { return 'Brave' }
        '^VivaldiHTM' { return 'Vivaldi' }
        default { return $ProgId }
    }
}

try {
    $sid = Get-LoggedOnUserSid
    if (-not $sid) {
        Write-Output 'No logged-on user'
        exit 0
    }

    $userChoicePath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice"
    $userChoice = Get-ItemProperty -Path $userChoicePath -ErrorAction Stop

    if (-not $userChoice.ProgId) {
        Write-Output 'Default browser not found'
        exit 0
    }

    Write-Output (Convert-ProgIdToBrowserName -ProgId $userChoice.ProgId)
    exit 0
}
catch {
    Write-Output 'Default browser not found'
    exit 0
}
