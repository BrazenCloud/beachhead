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
. .\windews\dependencies\subnets.ps1

#region Initiate asset discovery
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $settings.prodigal_object_id | Out-Null
$assetdiscoverSplat = @{
    Name          = 'Beachhead Asset Discovery'
    GroupId       = $group
    EndpointSetId = $set
    IsEnabled     = $true
    IsHidden      = $false
    Actions       = @(
        @{
            RepositoryActionId = (Get-BcRepository -Name 'map:discover').Id
            Settings           = @{
                "Update Assets" = 'true'
            }
        }
    )
    Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes 0
}
$job = New-BcJob @assetdiscoverSplat
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $job.JobId
Add-BcTag -SetId $set -Tags 'Beachhead', 'AssetDiscovery'


Write-Host "Created Asset discovery job with ID: $($job.JobId)"
#endregion

#region Initiate autodeploy
# https://docs.microsoft.com/en-us/powershell/module/nettcpip/get-netroute?view=windowsserver2022-ps#example-5-get-ip-routes-to-non-local-destinations
$internetRoute = Get-NetRoute | Where-Object -FilterScript { $_.NextHop -Ne "::" } | Where-Object -FilterScript { $_.NextHop -Ne "0.0.0.0" } | Where-Object -FilterScript { ($_.NextHop.SubString(0, 6) -Ne "fe80::") } | Sort-Object InterfaceMetric | Select-Object -First 1
$ipconfig = Get-NetIPConfiguration -InterfaceIndex $internetRoute.InterfaceIndex
$subnet = Get-IPv4Subnet -IPAddress $ipconfig.IPv4Address.IPAddress -PrefixLength $ipconfig.IPv4Address.PrefixLength

$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $settings.prodigal_object_id | Out-Null
$autodeploySplat = @{
    Name          = 'Beachhead Autodeploy'
    GroupId       = $group
    EndpointSetId = $set
    IsEnabled     = $true
    IsHidden      = $false
    Actions       = @(
        @{
            RepositoryActionId = (Get-BcRepository -Name 'deploy:runway').Id
            Settings           = @{
                "Enrollment Token" = (New-BcEnrollmentSession -Type 'EnrollPersistentRunner' -Expiration (Get-Date).AddDays(30) -GroupId $group -IsOneTime:$false).Token
                "IP Range"         = "$($subnet.FirstHostIP)-$($subnet.LastHostIP)"
            }
        }
    )
    Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes 20
}
$job = New-BcJob @autodeploySplat
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $job.JobId
Add-BcTag -SetId $set -Tags 'Beachhead', 'AutoDeploy'

Write-Host "Created autodeploy job with ID: $($job.JobId)"
#endregion

#region Initiate periodic jobs

#region Initiate deployer
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $settings.prodigal_object_id | Out-Null
$deployerSplat = @{
    Name          = "Beachhead Deployer"
    GroupId       = $group
    EndpointSetId = $set
    IsEnabled     = $true
    IsHidden      = $false
    Actions       = @(
        @{
            RepositoryActionId = (Get-BcRepository -Name 'beachhead:deployer').Id
        }
    )
    Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes 20
}
$job = New-BcJob @deployerSplat
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $job.JobId
Add-BcTag -SetId $set -Tags 'Beachhead', 'Deployer'

Write-Host "Created job: Beachhead Deployer"

#endregion

#region Initiate alternate deploy

#endregion

#region Initiate monitor
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $settings.prodigal_object_id | Out-Null
$monitorSplat = @{
    Name          = "Beachhead Monitor"
    GroupId       = $group
    EndpointSetId = $set
    IsEnabled     = $true
    IsHidden      = $false
    Actions       = @(
        @{
            RepositoryActionId = (Get-BcRepository -Name 'beachhead:monitor').Id
        }
    )
    Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes 20
}
$job = New-BcJob @monitorSplat
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $job.JobId
Add-BcTag -SetId $set -Tags 'Beachhead', 'Monitor'

Write-Host "Created job: Beachhead Monitor"
#endregion


#endregion