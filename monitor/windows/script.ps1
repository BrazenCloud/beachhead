#region dependencies
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
. .\windows\dependencies\Tee-BcLog.ps1
#endregion

#region PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if (-not (Test-Path '..\..\..\pwsh\pwsh.exe')) {
        Throw 'Pwsh missing, rerun assessor'
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
    Tee-BcLog @logSplat -Message 'BrazenCloud Coverage Tracker initialized'

    # Clean indexes
    Tee-BcLog @logSplat -Message 'Retrieving existing coverage data...'
    $coverageSplat = @{
        GroupId     = $group
        QueryString = '{ "query": { "match_all": { } } }'
        IndexName   = 'beachheadcoverage'
    }
    $coverage = Invoke-BcQueryDataStoreHelper @coverageSplat
    $coverageHt = @{}
    foreach ($item in $coverage) {
        $coverageHt[$item.ipAddress] = $item
    }

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

    $coverageSummary = @{
        LastUpdate          = $lastUpdate
        BrazenCloudCoverage = $([math]::round((($endpointAssets | Where-Object { $_.HasRunner }).Count / $endpointAssets.Count), 2) * 100)
        counts              = @{
            Runners        = ($endpointAssets | Where-Object { $_.HasRunner }).Count
            EndpointAssets = $endpointAssets.Count
        }
        missing             = @{
            Runners = $endpointAssets | Where-Object { -not $_.HasRunner }
        }
    }

    #foreach agent deploy, calculate coverage
    Tee-BcLog @logSplat -Message 'Calculating agent coverage...'
    $agentInstalls = Invoke-BcQueryDataStoreHelper -GroupId $group -QueryString '{ "query": { "query_string": { "query": "agentInstall", "default_field": "type" } } }' -IndexName beachheadconfig
    foreach ($ai in $agentInstalls) {
        $installCount = ($endpointAssets | Where-Object { $_.Tags -contains $ai.InstalledTag }).Count
        $coverageSummary['counts']["$($ai.Name.Replace(' ',''))Installs"] = $installCount
        $coverageSummary["$($ai.Name.Replace(' ',''))Coverage"] = $([math]::round($($installCount / $endpointAssets.Count), 2) * 100)
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
    Invoke-BcBulkDataStoreInsert -GroupId $group -IndexName 'beachheadcoveragesummary' -Data ($coverageSummary | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 10 })

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
    Remove-BcDataStoreEntry -GroupId $group -IndexName 'beachheadcoverage' -DeleteQuery '{"query": {"match_all": {} } }'
    for ($x = 0; $x -lt $coverageHt.Keys.Count; $x = $x + 100) {
        $hts = @($coverageHt.Keys)[$x..$($x + 100)] | ForEach-Object {
            $coverageHt[$_]
        }
        $itemSplat = @{
            GroupId   = $group
            IndexName = 'beachheadcoverage'
            Data      = $hts | ForEach-Object { ConvertTo-Json $_ -Compress }
        }
        Invoke-BcBulkDataStoreInsert @itemSplat
    }
    $coverageHt | ConvertTo-Json -Depth 10 | Out-File .\results\coverageReport.json

    <# 
            Calculate time since start, if greater than 3 runs (based on run interval), then
        check to make sure a asset discovery job has completed. If both true, then calculate
        Beachheadcompletion conditions.
        Conditions for beachhead being 'complete':
        - Each of the following conditions are true or their failure count is 2 or greater:
            - bcAgent
            - Other agents
    #>
    $monitorJob = Get-BcJob -JobId $settings.job_id
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
                    Left     = 'Tags'
                    Operator = '='
                    Right    = 'beachhead'
                },
                @{
                    Left     = 'Tags'
                    Operator = '='
                    Right    = 'assetDiscovery'
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
    $assetDiscoverJob = (Invoke-BcQueryJob -Query $query).Items[0]
    if ($monitorJob.JobMetrics.Where({ $_.NumRunning -eq 0 }).Count -gt 3 -and $assetDiscoverJob.TotalEndpointsFinished -eq 1) {
        Tee-BcLog @logSplat -Message "Starting completion test..."
        # monitor job (this one) has run at least 3 times
        # asset discover job has finished
        $coverageSplat = @{
            GroupId     = $group
            QueryString = '{ "query": { "match_all": { } } }'
            IndexName   = 'beachheadcoverage'
        }
        $coverage = Invoke-BcQueryDataStoreHelper @coverageSplat
        $complete = $true
        :completecalc foreach ($item in $coverage) {
            if ($item.bcAgent -ne $true) {
                if ($item.bcAgentFailCount -lt 2 -or $item.bcAgentPsRemoteFailCount -lt 2 -or $item.bcAgentWmiFailCount -lt 2) {
                    Tee-BcLog @logSplat -Message "Process is not completed. First endpoint found with missing bcAgent: $($item.name) - $($item.ipAddress)"
                    $complete = $false
                    break completecalc
                }
            }
            foreach ($ai in $agentInstalls) {
                if ($item."$($ai.Name.Replace(' ',''))Installed" -ne $true) {
                    if ($item."$($ai.Name.Replace(' ',''))FailCount" -lt 2) {
                        Tee-BcLog @logSplat -Message "Process is not completed. First endpoint found with missing agent ($($ai.Name)): $($item.name) - $($item.ipAddress)"
                        $complete = $false
                        break completecalc
                    }
                }
            }
        }
        if ($complete) {
            Tee-BcLog @logSplat -Message "Process is complete!"
        }
    }
}