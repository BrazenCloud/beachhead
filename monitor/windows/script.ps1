#region Prep
# load settings.json
$settings = Get-Content .\settings.json | ConvertFrom-Json
$settings

# function to auth as the runner
. .\windows\dependencies\Get-BrazenCloudDaemonToken.ps1

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

$group = (Get-BcAuthenticationCurrentUser).HomeContainerId
. .\windows\dependencies\Invoke-BcQueryDatastore2.ps1

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
$take = 1
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
$endpointAssets = Invoke-BcQueryEndpointAsset -Query $query
[BrazenCloudSdk.PowerShell.Models.IEndpointAssetQueryView[]]$endpointAssets = $ea.Items
while ($endpointAssets.Count -lt $ea.FilteredCount) {
    $query.skip = $skip + $take
    $ea = Invoke-BcQueryEndpointAsset -Query $query
    [BrazenCloudSdk.PowerShell.Models.IEndpointAssetQueryView[]]$endpointAssets += $ea.Items
}

$out = @{
    Runners        = $runners.Count
    EndpointAssets = $endpointAssets.Count
}

#foreach agent deploy, calculate coverage
$agentInstalls = Invoke-BcQueryDataStore2 -GroupId $group -Query @{query_string = @{query = 'agentInstall'; default_field = 'type' } } -IndexName beachheadconfig

foreach ($ai in $agentInstalls) {
    $out["$($ai.Name.Replace(' ',''))Installs"] = ($runners | Where-Object { $_.Tags -contains $ai.InstalledTag }).Count
}
$out | ConvertTo-Json
$out | ConvertTo-Json | Out-File .\results\coverage.json