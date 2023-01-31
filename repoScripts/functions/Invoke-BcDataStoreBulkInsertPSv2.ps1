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