Function Remove-BcDatastoreQuery2 {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [string]$IndexName,
        [string]$GroupId = (Get-BcAuthenticationCurrentUser).HomeContainerId,
        #example:  @{query=@{match=@{type='agentInstall'}}}
        [Parameter(Mandatory)]
        [hashtable]$Query
    )
    $splat = @{
        Method  = 'Delete'
        Uri     = "https://$($env:BrazenCloudDomain)/api/v2/datastore/$IndexName/delete"
        Body    = @{
            deleteQuery = $Query
            groupId     = $GroupId
        } | ConvertTo-Json -Depth 10
        Headers = @{
            Accept         = 'application/json'
            'Content-Type' = 'application/json'
            Authorization  = "Session $($env:BrazenCloudSessionToken)"
        }
    }
    Invoke-RestMethod @splat
}