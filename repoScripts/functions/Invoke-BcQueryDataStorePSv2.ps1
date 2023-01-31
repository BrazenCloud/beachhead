Function Invoke-BcQueryDataStorePSv2 {
    param (
        [string]$Query,
        [string]$IndexName,
        [string]$GroupId
    )
    $splat = @{
        Method = 'Post'
        Path   = "/api/v2/datastore/$IndexName/$GroupId/entries"
        Body   = "{`"searchQuery`": `"$Query`",`"from`":0,`"take`":1}"
    }
    Invoke-BcApi @splat
}