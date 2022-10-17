Function Get-BcEndpointAssetwRunner {
    [cmdletbinding()]
    param (
        [string]$GroupId
    )
    $query = @{
        includeSubgroups = $true
        rootContainerId  = $GroupId
        skip             = 0
        take             = 1
        sortDirection    = 0
        filter           = @{
            Left     = 'HasRunner'
            Operator = '='
            Right    = 'True'
        }
    }
    $ea = Invoke-BcQueryEndpointAsset -Query $query
    $count = $ea.Items.Count
    $ea.Items
    while ($count -lt $ea.FilteredCount) {
        $query.skip = $query.skip + $query.take
        $ea = Invoke-BcQueryEndpointAsset -Query $query
        $count += $ea.Items.Count
        $ea.Items
    }
}