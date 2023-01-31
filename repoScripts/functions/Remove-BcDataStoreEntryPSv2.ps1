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