Function Get-JsonValuePSv2 {
    param (
        [string[]]$Json,
        [string]$Property
    )
    # this isn't super reliable, but it works on a non-nested json object
    if (($Json | Where-Object { $_ -like "*$Property*" }).Trim().Trim(',') -match '"(?<prop>[^"]+)"}?$') {
        $Matches.prop
    }
}