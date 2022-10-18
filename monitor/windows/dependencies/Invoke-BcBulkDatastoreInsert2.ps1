Function Invoke-BcBulkDatastoreInsert2 {
    [cmdletbinding()]
    param (
        [string]$GroupId = (Get-BcAuthenticationCurrentUser).HomeContainerId,
        [Parameter(Mandatory)]
        $Data,
        [Parameter(Mandatory)]
        [string]$IndexName
    )
    $json = $Data | ConvertTo-Json -Depth 10 -Compress
    if ($Data.GetType().Name -notlike '*`[`]') {
        $json = "[$json]"
    }
    $splat = @{
        Method  = 'Post'
        Uri     = "https://$($env:BrazenCloudDomain)/api/v2/datastore/$IndexName/$GroupId/bulk"
        Body    = $json
        Headers = @{
            Accept         = 'application/json'
            'Content-Type' = 'application/json'
            Authorization  = "Session $($env:BrazenCloudSessionToken)"
        }
    }
    Invoke-RestMethod @splat
}