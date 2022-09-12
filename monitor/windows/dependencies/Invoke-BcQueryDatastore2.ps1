Function Invoke-BcQueryDatastore2 {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [string]$IndexName,
        #example: @{query_string=@{query='agentInstall';default_field='type'}}
        [hashtable]$Query,
        [string]$GroupId = (Get-BcAuthenticationCurrentUser).HomeContainerId,
        [int]$From = 0,
        [int]$Take = 500
    )
    if ($PSBoundParameters.Keys -notcontains 'Query') {
        $Query = @{match_all = @{} }
    }
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