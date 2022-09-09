Function Invoke-BcQueryDatastore2 {
    [cmdletbinding()]
    param (
        [string]$IndexName,
        [hashtable]$Query,
        [string]$GroupId,
        [int]$From = 0,
        [int]$Take = 500
    )
    $splat = @{
        Method  = 'Post'
        Uri     = "https://$($env:BrazenCloudDomain)/api/v2/datastore/$IndexName/query"
        Body    = @{
            searchQuery = $Query
            groupId     = $GroupId
            from        = $From
            take        = $Take
        } | ConvertTo-Json -Depth 10
        Headers = @{
            Accept         = 'application/json'
            'Content-Type' = 'application/json'
            Authorization  = "Session $($env:BrazenCloudSessionToken)"
        }
    }
    (Invoke-RestMethod @splat).result
}