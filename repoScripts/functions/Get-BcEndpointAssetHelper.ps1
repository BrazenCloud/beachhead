Function Get-BcEndpointAssetHelper {
    [cmdletbinding(
        DefaultParameterSetName = 'all'
    )]
    param (
        [Parameter(Mandatory)]
        [string]$GroupId,
        [Parameter(
            ParameterSetName = 'noRunner'
        )]
        [switch]$NoRunner,
        [Parameter(
            ParameterSetName = 'hasRunner'
        )]
        [switch]$HasRunner,
        [Parameter(
            ParameterSetName = 'all'
        )]
        [switch]$All
    )
    $query = @{
        includeSubgroups = $true
        rootContainerId  = $GroupId
        skip             = 0
        take             = 1000
        sortDirection    = 0
    }
    $query['filter'] = switch ($PSCmdlet.ParameterSetName) {
        'all' {
            $null
        }
        'noRunner' {
            @{
                Left     = 'HasRunner'
                Operator = '='
                Right    = 'False'
            }
        }
        'hasRunner' {
            @{
                Left     = 'HasRunner'
                Operator = '='
                Right    = 'True'
            }
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