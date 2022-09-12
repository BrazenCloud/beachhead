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

#region Initiate asset discovery
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $settings.runner_identity | Out-Null
$action = Get-BcRepository -Name 'map:discover'
$jobSplat = @{
    Name          = 'Beachhead Asset Discovery'
    GroupId       = $group
    EndpointSetId = $set
    IsEnabled     = $true
    IsHidden      = $false
    Actions       = @(
        @{
            RepositoryActionId = $action.Id
            Settings           = @{
                "Update Assets" = $false
            }
        }
    )
    Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes 0
}
$job = New-BcJob @jobSplat

Write-Host "Created Asset discovery job with ID: $($job.JobId)"
#endregion

#region Initiate autodeploy
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $settings.runner_identity | Out-Null
$action = Get-BcRepository -Name 'runway:deploy'
$jobSplat = @{
    Name          = 'Beachhead Autodeploy'
    GroupId       = $group
    EndpointSetId = $set
    IsEnabled     = $true
    IsHidden      = $false
    Actions       = @(
        @{
            RepositoryActionId = $action.Id
            Settings           = @{
                "Enrollment Token" = (New-BcEnrollmentSession -Type 'EnrollPersistentRunner' -Expiration (Get-Date).AddDays(30) -GroupId $group -IsOneTime $false).Token
            }
        }
    )
    Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes 20
}
$job = New-BcJob @jobSplat

Write-Host "Created autodeploy job with ID: $($job.JobId)"
#endregion

#region Initiate periodic jobs

#region Initiate deployer
$agentsToDeploy = Invoke-BcQueryDatastore2 -IndexName 'beachheadconfig' -Query @{query_string = @{query = 'agentInstall'; default_field = 'type' } } -GroupId $group
$installCheck = (Get-BcRepository -Name 'beachhead:installCheck').Id
$allRunners = (Get-BcRunner).Items

$deployActions = foreach ($atd in $agentsToDeploy) {
    foreach ($action in $atd.actions) {
        @{
            RepositoryActionId = (Get-BcRepository -Name $action.action).Id
            Settings           = $action.settings
        }
    }
    @{
        RepositoryActionId = $installCheck
        Settings           = @{
            Name               = $atd.InstalledName
            'Tag if installed' = $atd.installedTag
        }
    }
    $set = New-BcSet
    # add runners to set
    Add-BcSetToSet -TargetSetId $set -ObjectIds ($allRunners | Where-Object { $_.Tags -notcontains $atd.installedTag }).Id
    $jobSplat = @{
        Name          = 'Beachhead Deploy Agents'
        GroupId       = $group
        EndpointSetId = $set
        IsEnabled     = $true
        IsHidden      = $false
        Actions       = $deployActions
        Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes 0
    }
    $job = New-BcJob @jobSplat
}


#endregion

#region Initiate alternate deploy

#endregion

#region Initiate monitor

#endregion


#endregion