#region Prep
# load settings.json
$settings = Get-Content .\settings.json | ConvertFrom-Json
$settings

# function to auth as the runner
. .\windows\dependencies\Get-BrazenCloudDaemonToken.ps1

# update nuget, if necessary
$v = (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue).Version
if ($null -eq $v -or $v -lt 2.8.5.201) {
    Write-Host 'Updating NuGet...'
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Confirm:$false -Force -Verbose
}

# set up the BrazenCloud module
if (-not (Get-Module BrazenCloud -ListAvailable)) {
    Install-Module BrazenCloud -MinimumVersion 0.3.2 -Force
}
$wp = $WarningPreference
$WarningPreference = 'SilentlyContinue'
Import-Module BrazenCloud | Out-Null
$WarningPreference = $wp
$env:BrazenCloudSessionToken = Get-BrazenCloudDaemonToken -aToken $settings.atoken -Domain $settings.host
$env:BrazenCloudSessionToken
$env:BrazenCloudDomain = $settings.host.split('/')[-1]

#endregion

$group = (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]
. .\windows\dependencies\Invoke-BcQueryDatastore2.ps1
. .\windows\dependencies\Invoke-BcBulkDatastoreInsert2.ps1
. .\windows\dependencies\Remove-BcDatastoreQuery2

# Clean indexes
Remove-BcDatastoreQuery2 -GroupId $group -IndexName 'beachheadcoverage' -Query @{query = @{match_all = @{} } }
Remove-BcDatastoreQuery2 -GroupId $group -IndexName 'beachheadcoveragesummary' -Query @{query = @{match_all = @{} } }

# Get all Runners
$skip = 0
$take = 1000
$r = Invoke-BcQueryRunner -MembershipCheckId $group -Take $take -Skip $skip -IncludeSubgroups:$false -SortDirection 1
[BrazenCloudSdk.PowerShell.Models.IRunnerQueryView[]]$runners = $r.Items
while ($runners.Count -lt $r.FilteredCount) {
    $skip = $skip + $take
    Write-Host 'query'
    Write-Host "Skip: $skip"
    $r = Invoke-BcQueryRunner -MembershipCheckId $group -Take $take -Skip $skip -IncludeSubgroups:$false -SortDirection 1
    [BrazenCloudSdk.PowerShell.Models.IRunnerQueryView[]]$runners += $r.Items
}

#calculate runner coverage
$skip = 0
$take = 1000
$query = @{
    includeSubgroups = $true
    skip             = $skip
    take             = $take
    sortDirection    = 0
    filter           = @{
        Left     = 'OSName'
        Operator = '^:'
        Right    = 'Microsoft Windows'
    }
}
$ea = Invoke-BcQueryEndpointAsset -Query $query
[BrazenCloudSdk.PowerShell.Models.IEndpointAssetQueryView[]]$endpointAssets = $ea.Items
while ($endpointAssets.Count -lt $ea.FilteredCount) {
    $query.skip = $query.skip + $take
    $ea = Invoke-BcQueryEndpointAsset -Query $query
    [BrazenCloudSdk.PowerShell.Models.IEndpointAssetQueryView[]]$endpointAssets += $ea.Items
}

$lastUpdate = (Get-Date).ToString()

$coverageSummary = @{
    LastUpdate          = $lastUpdate
    BrazenCloudCoverage = $([math]::round($($runners.Count / $endpointAssets.Count), 2) * 100)
    counts              = @{
        Runners        = $runners.Count
        EndpointAssets = $endpointAssets.Count
    }
    missing             = @{
        Runners = $endpointAssets | Where-Object { -not $_.HasRunner }
    }
}

#foreach agent deploy, calculate coverage
$agentInstalls = Invoke-BcQueryDatastore2 -GroupId $group -Query @{query_string = @{query = 'agentInstall'; default_field = 'type' } } -IndexName beachheadconfig
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

Invoke-BcBulkDatastoreInsert2 -GroupId $group -IndexName 'beachheadcoveragesummary' -Data $coverageSummary

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
Invoke-BcBulkDatastoreInsert2 -GroupId $group -IndexName 'beachheadcoverage' -Data $coverageReport
$coverageReport | ConvertTo-Json -Depth 10 | Out-File .\results\coverageReport.json