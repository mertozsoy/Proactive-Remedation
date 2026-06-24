$AllowedMembers = @(
    "Administrator",
    "aves",
    "ADMAdmin",
    "patron",
    "Domain Admins"
)

try {

    $Group = [ADSI]"WinNT://./Administrators,group"

    $Members = @($Group.psbase.Invoke("Members"))

    foreach ($Member in $Members) {

        try {

            $Name = $Member.GetType().InvokeMember(
                "Name",
                "GetProperty",
                $null,
                $Member,
                $null
            )

            $AdsPath = $Member.GetType().InvokeMember(
                "ADsPath",
                "GetProperty",
                $null,
                $Member,
                $null
            )

            Write-Output "Found: $Name"

            if ($Name -notin $AllowedMembers) {

                Write-Output "Removing: $Name"

                $Group.Remove($AdsPath)

                Write-Output "Removed: $Name"
            }
        }
        catch {
            Write-Output "Failed Member: $($_.Exception.Message)"
        }
    }

    exit 0
}
catch {
    Write-Output $_.Exception.Message
    exit 1
}
