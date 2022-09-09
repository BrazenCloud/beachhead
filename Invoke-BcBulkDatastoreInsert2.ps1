Function Invoke-BcBulkDatastoreInsert2 {
    [cmdletbinding()]
    param (
        [string]$GroupId,
        [psobject[]]$Data,
        [string]$IndexName
    )
    $splat = @{
        Method  = 'Post'
        Uri     = "https://$($env:BrazenCloudDomain)/api/v2/datastore/$IndexName/bulk"
        Body    = @{
            groupId = $GroupId
            data    = $Data
        } | ConvertTo-Json -Depth 10 -Compress
        Headers = @{
            Accept         = 'application/json'
            'Content-Type' = 'application/json'
            Authorization  = "Session $($env:BrazenCloudSessionToken)"
        }
    }
    Invoke-RestMethod @splat
}