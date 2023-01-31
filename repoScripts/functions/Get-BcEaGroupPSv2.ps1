Function Get-BcEaGroupPSv2 {
    param (
        [string]$EndpointAssetId
    )
    $str = Invoke-BcApi -Method 'Get' -Path "/api/v2/endpoints/$EndpointAssetId"
    if ($str -match '\"groups\"\:\[\"(?<group>[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') {
        $Matches.group
    } else {
        Throw 'Unable to retrieve group info'
    }
}