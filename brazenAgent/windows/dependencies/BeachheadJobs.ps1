Function Get-DeployerJob {
    param (
        [ValidateSet('Deployer', 'Monitor', 'AssetDiscovery')]
        [string]$JobName,
        [string]$Group
    )
    switch ($JobName) {
        'Deployer' {
            $searchTag = 'Deployer'
        }
        'Monitor' {
            $searchTag = 'Monitor'
        }
        'AssetDiscovery' {
            $searchTag = 'AssetDiscovery'
        }
    }
    $query = @{
        includeSubgroups  = $true
        MembershipCheckId = $group
        skip              = 0
        take              = 1
        sortDirection     = 0
        filter            = @{
            children = @(
                @{
                    Left     = 'Tags'
                    Operator = '='
                    Right    = 'Beachhead'
                },
                @{
                    Left     = 'Tags'
                    Operator = '='
                    Right    = $searchTag
                },
                @{
                    Left     = 'Groups'
                    Operator = '='
                    Right    = $group
                }
            )
            operator = 'AND'
        }
    }
    (Invoke-BcQueryJob -Query $query).Items[0]
}
Function Start-DeployerJob {
    param (
        [ValidateSet('Deployer', 'Monitor', 'AssetDiscovery')]
        [string]$JobName,
        [string]$Group
    )
    $job = Get-DeployerJob -JobName $JobName -Group $Group
    While ($job.TotalEndpointsRunning -gt 0) {
        Start-Sleep -Seconds 10
        $job = Get-DeployerJob -JobName $JobName -Group $Group
    }
    Remove-BcJobThread -JobId $job.Id
}