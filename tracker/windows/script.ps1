#region dependencies
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
. .\windows\dependencies\Tee-BcLog.ps1
. .\windows\dependencies\DeployerJobs.ps1
#endregion

#region PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if (-not (Test-Path '..\..\..\pwsh\pwsh.exe')) {
        Throw 'Pwsh missing, rerun deployer:start'
    }
    Write-Host 'Executing pwsh...'
    ..\..\..\pwsh\pwsh.exe -ExecutionPolicy Bypass -File $($MyInvocation.MyCommand.Definition)
} else {
    #endregion
    $settings = Get-Content .\settings.json | ConvertFrom-Json
    Initialize-BcRunnerAuthentication -Settings $settings -WarningAction SilentlyContinue
    $group = (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]
    $logSplat = @{
        Level   = 'Info'
        Group   = $group
        JobName = 'Coverage Tracker'
    }
    Tee-BcLog @logSplat -Message 'Deployer Tracker initialized'

    # Clean indexes
    Tee-BcLog @logSplat -Message 'Retrieving existing coverage data...'
    $coverageSplat = @{
        GroupId     = $group
        QueryString = '{ "query": { "match_all": { } } }'
        IndexName   = 'deployercoverage'
    }

    # load indexes
    $coverage = Invoke-BcQueryDataStoreHelper @coverageSplat
    $coverageHt = @{}
    foreach ($item in $coverage) {
        $coverageHt[$item.ipAddress] = $item
    }
    $agentInstalls = Invoke-BcQueryDataStoreHelper -GroupId $group -QueryString '{ "query": { "query_string": { "query": "agentInstall", "default_field": "type" } } }' -IndexName deployerconfig

    #calculate runner coverage
    Tee-BcLog @logSplat -Message 'Calculating BrazenAgent coverage...'
    $skip = 0
    $take = 1000
    $query = @{
        includeSubgroups  = $true
        MembershipCheckId = $group
        skip              = $skip
        take              = $take
        sortDirection     = 0
        filter            = @{
            children = @(
                @{
                    Left     = 'OSName'
                    Operator = '^:'
                    Right    = 'Microsoft Windows'
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
    $ea = Invoke-BcQueryEndpointAsset -Query $query
    [BrazenCloudSdk.PowerShell.Models.IEndpointAssetQueryView[]]$endpointAssets = $ea.Items
    while ($endpointAssets.Count -lt $ea.FilteredCount) {
        $query.skip = $query.skip + $take
        $ea = Invoke-BcQueryEndpointAsset -Query $query
        [BrazenCloudSdk.PowerShell.Models.IEndpointAssetQueryView[]]$endpointAssets += $ea.Items
    }

    $lastUpdate = Get-Date -Format "o"

    #region coverage
    foreach ($ea in $endpointAssets) {
        if ($coverageHt.Keys -contains $ea.LastIPAddress) {
            $coverageHt[$ea.LastIPAddress].name = $ea.Name
            $coverageHt[$ea.LastIPAddress].operatingSystem = $ea.OSName
            $coverageHt[$ea.LastIPAddress].bcAgent = $ea.HasRunner
            foreach ($ai in $agentInstalls) {
                $coverageHt[$ea.LastIPAddress]."$($ai.Name.Replace(' ',''))Installed" = $ea.Tags -contains ($ai.InstalledTag)
            }
        } else {
            Tee-BcLog @logSplat -Message "EndpointAsset with IP: '$($ea.LastIPAddress)' does not exist in targets list. Adding."
            $ht = @{
                name                     = $ea.Name
                operatingSystem          = $ea.OSName
                ipAddress                = $ea.LastIPAddress
                bcAgent                  = $ea.HasRunner
                bcAgentFailCount         = 0
                bcAgentPsRemoteFailCount = 0
                bcAgentWmiFailCount      = 0
            }
            foreach ($ai in $agentInstalls) {
                $ht["$($ai.Name.Replace(' ',''))Installed"] = $ea.Tags -contains ($ai.InstalledTag)
                $ht["$($ai.Name.Replace(' ',''))FailCount"] = 0
            }
            $coverageHt[$ea.LastIPAddress] = $ht
        }
    }
    Tee-BcLog @logSplat -Message 'Uploading coverage data...'
    Remove-BcDataStoreEntry -GroupId $group -IndexName 'deployercoverage' -DeleteQuery '{"query": {"match_all": {} } }'
    for ($x = 0; $x -lt $coverageHt.Keys.Count; $x = $x + 100) {
        $hts = @($coverageHt.Keys)[$x..$($x + 100)] | ForEach-Object {
            $coverageHt[$_]
        }
        $itemSplat = @{
            GroupId   = $group
            IndexName = 'deployercoverage'
            Data      = $hts | ForEach-Object { ConvertTo-Json $_ -Compress }
        }
        Invoke-BcBulkDataStoreInsert @itemSplat
    }
    $coverageHt | ConvertTo-Json -Depth 10 | Out-File .\results\coverageReport.json
    #endregion

    #region Coverage Summary
    $allNonFailedEndpoints = $coverage | Where-Object { $_.name.Length -gt 0 -and ($_.bcAgent -eq $true -or $_.bcAgentFailCount -lt [int]$settings.'Failure Threshold') }
    $allEndpointsWithBcAgent = $coverage | Where-Object { $_.name.Length -gt 0 -and $_.bcAgent -eq $true }
    $coverageSummary = @{
        LastUpdate          = $lastUpdate
        BrazenCloudCoverage = $([math]::round(($allEndpointsWithBcAgent.Count / $allNonFailedEndpoints.Count), 2) * 100)
        counts              = @{
            Runners        = ($endpointAssets | Where-Object { $_.HasRunner }).Count
            EndpointAssets = $endpointAssets.Count
        }
        missing             = @{
            Runners = @($endpointAssets | Select-Object -ExcludeProperty Adapters | Where-Object { -not $_.HasRunner })
        }
    }

    #foreach agent deploy, calculate coverage
    Tee-BcLog @logSplat -Message 'Calculating agent coverage...'
    foreach ($ai in $agentInstalls) {
        $allNonFailedAgentEndpoints = $coverage | Where-Object { $_.name.Length -gt 0 -and ($_."$($ai.Name.Replace(' ',''))Installed" -eq $true -or $_."$($ai.Name.Replace(' ',''))FailCount" -lt [int]$settings.'Failure Threshold') }
        $installCount = ($endpointAssets | Where-Object { $_.Tags -contains $ai.InstalledTag }).Count
        $coverageSummary['counts']["$($ai.Name.Replace(' ',''))Installs"] = $installCount
        $coverageSummary["$($ai.Name.Replace(' ',''))Coverage"] = $([math]::round($($installCount / $allNonFailedAgentEndpoints.Count), 2) * 100)
        $coverageSummary['missing']["$($ai.Name.Replace(' ',''))Installs"] = @($endpointAssets | Where-Object { $_.Tags -notcontains $ai.InstalledTag } | ForEach-Object {
                @{
                    Name       = $_.Name
                    IPAddress  = $_.LastIPAddress
                    MacAddress = $_.PreferredMacAddress
                    LastUpdate = $lastUpdate
                }
            })
    
        Select-Object Name, LastIPAddress, PreferredMacAddress
    }
    $coverageSummary | ConvertTo-Json -Depth 10 -Compress

    $coverageSummary | ConvertTo-Json -Depth 10 | Out-File .\results\coverageReportSummary.json

    Tee-BcLog @logSplat -Message "Uploading coverage summary..."
    Invoke-BcBulkDataStoreInsert -GroupId $group -IndexName 'deployercoveragesummary' -Data ($coverageSummary | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 10 })
    #endregion

    <# 
            Calculate time since start, if greater than 3 runs (based on run interval), then
        check to make sure a asset discovery job has completed. If both true, then calculate
        Deployer completion conditions.
        Conditions for Deployer being 'complete':
        - Each of the following conditions are true or their failure count is 2 or greater:
            - bcAgent
            - Other agents
    #>
    $trackerJob = Get-BcJob -JobId $settings.job_id
    $assetDiscoverJob = Get-DeployerJob -JobName AssetDiscovery -Group $group
    if ($trackerJob.JobMetrics.Where({ $_.NumRunning -eq 0 }).Count -gt 3 -and $assetDiscoverJob.TotalEndpointsFinished -eq 1) {
        Tee-BcLog @logSplat -Message "Starting completion test..."
        # tracker job (this one) has run at least 3 times
        # asset discover job has finished
        $coverageSplat = @{
            GroupId     = $group
            QueryString = '{ "query": { "match_all": { } } }'
            IndexName   = 'deployercoverage'
        }
        $coverage = Invoke-BcQueryDataStoreHelper @coverageSplat
        $complete = $true
        :completecalc foreach ($item in $coverage.Where({ $_.name.Length -gt 0 })) {
            if ($item.bcAgent -ne $true) {
                if ($item.bcAgentFailCount -lt [int]$settings.'Failure Threshold' -or $item.bcAgentPsRemoteFailCount -lt [int]$settings.'Failure Threshold' -or $item.bcAgentWmiFailCount -lt [int]$settings.'Failure Threshold') {
                    Tee-BcLog @logSplat -Message "Process is not completed. Found endpoint with missing bcAgent: $($item.name) - $($item.ipAddress)"
                    $complete = $false
                    #break completecalc
                } else {
                    # no point in testing agent installs if no bcAgent exists
                    continue completecalc
                }
            }
            foreach ($ai in $agentInstalls) {
                if ($item."$($ai.Name.Replace(' ',''))Installed" -ne $true) {
                    if ($item."$($ai.Name.Replace(' ',''))FailCount" -lt [int]$settings.'Failure Threshold') {
                        Tee-BcLog @logSplat -Message "Process is not completed. Found endpoint with missing agent ($($ai.Name)): $($item.name) - $($item.ipAddress)"
                        $complete = $false
                        #break completecalc
                    }
                }
            }
        }
        if ($complete) {
            Tee-BcLog @logSplat -Message "Process is complete!"
            # disable tracker and deployer jobs
            Tee-BcLog @logSplat -Message "Disabling recurring jobs..."
            Enable-BcJob -JobId $settings.job_id -Value:$false
            $deployJob = Get-DeployerJob -JobName Orchestrator -Group $group
            Enable-BcJob -JobId $deployJob.Id -Value:$false
            Tee-BcLog @logSplat -Message "Sending completion message." -Complete
        }
    }
}