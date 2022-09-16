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
. .\windows\dependencies\Get-BcEndpointAssetwRunner.ps1

# Get agents to deploy
$installCheck = (Get-BcRepository -Name 'beachhead:installCheck').Id
$agentInstalls = Invoke-BcQueryDataStore2 -GroupId $group -Query @{query_string = @{query = 'agentInstall'; default_field = 'type' } } -IndexName beachheadconfig

# Get all endpointassets w/runner in current group
$endpointAssets = Get-BcEndpointAssetwRunner

# foreach agentInstall, get runners lacking the tag and assign the job
foreach ($atd in $agentInstalls) {
    $toAssign = ($endpointAssets | Where-Object { $_.Tags -notcontains $atd.installedTag }).Id
    if ($toAssign.Count -gt 0) {
        $deployActions = & {
            foreach ($action in $atd.actions) {
                $settingsHt = @{}
                foreach ($prop in $action.settings.psobject.Properties.Name) {
                    $settingsHt[$prop] = $action.Settings.$prop
                }
                @{
                    RepositoryActionId = (Get-BcRepository -Name $action.action).Id
                    Settings           = $settingsHt
                }
            }
            @{
                RepositoryActionId = $installCheck
                Settings           = @{
                    Name               = $atd.InstalledName
                    'Tag if installed' = $atd.installedTag
                }
            }
        }
        $set = New-BcSet
        # add runners to set
        Add-BcSetToSet -TargetSetId $set -ObjectIds ($endpointAssets | Where-Object { $_.Tags -notcontains $atd.installedTag }).Id
        $jobSplat = @{
            Name          = "Beachhead Deploy test: $($atd.Name)"
            GroupId       = $group
            EndpointSetId = $set
            IsEnabled     = $true
            IsHidden      = $false
            Actions       = $deployActions
            Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes 0
        }
        $job = New-BcJob @jobSplat
        $set = New-BcSet
        Add-BcSetToSet -TargetSetId $set -ObjectIds $job.JobId
        Add-BcTag -SetId $set -Tags 'Beachhead', 'AgentInstall'

        Write-Host "Created job: Beachead Deploy: $($atd.Name)"
    } else {
        Write-Host "No agents need $($atd.Name)"
    }
}
