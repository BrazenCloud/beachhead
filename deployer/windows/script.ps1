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

# Get agents to deploy
$agentInstalls = Invoke-BcQueryDataStore2 -GroupId $group -Query @{query_string = @{query = 'agentInstall'; default_field = 'type' } } -IndexName beachheadconfig

# Get all runners in current group
$skip = 0
$take = 1
$r = Invoke-BcQueryRunner -MembershipCheckId $group -Take $take -Skip $skip -IncludeSubgroups:$false -SortDirection 1
[BrazenCloudSdk.PowerShell.Models.IRunnerQueryView[]]$runners = $r.Items
while ($runners.Count -lt $r.FilteredCount) {
    $skip = $skip + $take
    Write-Host 'query'
    Write-Host "Skip: $skip"
    $r = Invoke-BcQueryRunner -MembershipCheckId $group -Take $take -Skip $skip -IncludeSubgroups:$false -SortDirection 1
    [BrazenCloudSdk.PowerShell.Models.IRunnerQueryView[]]$runners += $r.Items
}

# foreach agentInstall, get runners lacking the tag and assign the job
foreach ($ai in $agentInstalls) {
    $set = New-BcSet
    foreach ($runner in $runners | Where-Object { $_.Tags -notcontains $ai.InstalledTag }) {
        Add-BcSetToSet -TargetSetId $set -ObjectIds $runner.Id
    }
    $jobSplat = @{
        Name          = "Beachhead Deploy $($ai.Name)"
        GroupId       = $group
        EndpointSetId = $set
        IsEnabled     = $true
        IsHidden      = $false
        Actions       = foreach ($action in $ai.actions) {
            @(
                @{
                    RepositoryActionId = (Get-BcRepository -Name $action.action).Id
                    Settings           = $actions.settings
                }
            )
        }
        Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow'
    }
    New-BcJob @jobSplat
}