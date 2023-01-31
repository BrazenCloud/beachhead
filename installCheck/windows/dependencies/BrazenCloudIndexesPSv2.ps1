Function Invoke-BcBulkDataStoreInsertPSv2 {
    param (
        [string]$GroupId,
        [string]$IndexName,
        [string[]]$Entries
    )
    $splat = @{
        Method = 'Post'
        Path   = "/api/v2/datastore/$IndexName/$GroupId"
        Body   = "[`"$($Entries -join '","')`"]"
    }
    Invoke-BcApi @splat
}
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
Function Remove-BcDataStoreEntryPSv2 {
    param (
        [string]$GroupId,
        [string]$IndexName,
        [string]$DeleteQuery
    )
    $splat = @{
        Path   = "/api/v2/datastore/$IndexName/$GroupId/entries"
        Method = 'Delete'
        Body   = "{`"deleteQuery`": `"$DeleteQuery`"}"
    }
    Invoke-BcApi @splat
}