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
    Schedule      = New-RwJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes 0
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
    Schedule      = New-RwJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes 20
}
$job = New-BcJob @jobSplat

Write-Host "Created autodeploy job with ID: $($job.JobId)"
#endregion

#region Initiate periodic jobs

#region Initiate periodic agent query and deploy job

#endregion

#region Initiate alternate deploy

#endregion

#region Initiate coverage update

#endregion


#endregion