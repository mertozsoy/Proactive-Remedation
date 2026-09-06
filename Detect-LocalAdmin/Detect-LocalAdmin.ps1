$AllowedAdmins = @(
    "demo.admin",
    "demo.user1",
    "demo.user2"
)

try {
    $AdminGroup = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop

    $UnauthorizedAdmins = @()

    foreach ($Member in $AdminGroup) {

        $AccountName = $Member.Name.Split("\")[-1]

        if ($Member.ObjectClass -eq "User") {
            if ($AccountName -notin $AllowedAdmins) {
                $UnauthorizedAdmins += $Member.Name
            }
        }
    }

    if ($UnauthorizedAdmins.Count -gt 0) {

        Write-Output "NON-COMPLIANT"
        Write-Output "Unauthorized Local Admin Accounts:"

        foreach ($user in $UnauthorizedAdmins) {
            Write-Output $user
        }

        exit 1
    }

    Write-Output "COMPLIANT - No unauthorized local admin accounts"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
