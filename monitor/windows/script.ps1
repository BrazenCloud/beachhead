#region dependencies
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
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

    # Clean indexes
    Remove-BcDataStoreEntry -GroupId $group -IndexName 'beachheadcoverage' -DeleteQuery '{"query": {"match_all": {} } }'
    #Remove-BcDataStoreEntry -GroupId $group -IndexName 'beachheadcoveragesummary' -DeleteQuery '{"query": {"match_all": {} } }'

    #calculate runner coverage
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

    Invoke-BcBulkDataStoreInsert -GroupId $group -IndexName 'beachheadcoveragesummary' -Data ($coverageSummary | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 10 })

    $coverageReport = foreach ($ea in $endpointAssets) {
        $ht = @{
            name            = $ea.Name
            operatingSystem = $ea.OSName
            bcAgent         = $ea.HasRunner
        }
        foreach ($ai in $agentInstalls) {
            $ht["$($ai.Name.Replace(' ',''))Installed"] = $ea.Tags -contains ($ai.InstalledTag)
        }
        $ht
    }
    Invoke-BcBulkDataStoreInsert -GroupId $group -IndexName 'beachheadcoverage' -Data ($coverageReport | ForEach-Object { $_ | ConvertTo-Json -Compress })
    $coverageReport | ConvertTo-Json -Depth 10 | Out-File .\results\coverageReport.json
}