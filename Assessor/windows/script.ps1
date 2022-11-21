#region dependencies
. .\windows\dependencies\subnets.ps1
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
#endregion

Initialize-BcRunnerAuthentication -Settings (Get-Content .\settings.json | ConvertFrom-Json)

$group = (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]

# apply job tags
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $settings.job_id
Add-BcTag -SetId $set -Tags 'Beachhead', 'Assessor'

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
            RepositoryActionId = (Get-BcRepository -Name 'beachhead:assetDiscover').Id
            Settings           = @{
                "Group ID" = $group
                "Subnet"   = if ($settings.'Subnet to Scan'.Length -gt 0) {
                    $settings.'Subnet To Scan'
                } else {
                    $null
                }
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

<#region Initiate autodeploy
# https://docs.microsoft.com/en-us/powershell/module/nettcpip/get-netroute?view=windowsserver2022-ps#example-5-get-ip-routes-to-non-local-destinations
<#
$internetRoute = Get-NetRoute | Where-Object -FilterScript { $_.NextHop -Ne "::" } | Where-Object -FilterScript { $_.NextHop -Ne "0.0.0.0" } | Where-Object -FilterScript { ($_.NextHop.SubString(0, 6) -Ne "fe80::") } | Sort-Object InterfaceMetric | Select-Object -First 1
$ipconfig = Get-NetIPConfiguration -InterfaceIndex $internetRoute.InterfaceIndex
$subnet = Get-IPv4Subnet -IPAddress $ipconfig.IPv4Address.IPAddress -PrefixLength $ipconfig.IPv4Address.PrefixLength
#

# hard coding /24 for demos.
$internetRoute = Get-NetRoute | Where-Object -FilterScript { $_.NextHop -Ne "::" } | Where-Object -FilterScript { $_.NextHop -Ne "0.0.0.0" } | Where-Object -FilterScript { ($_.NextHop.SubString(0, 6) -Ne "fe80::") } | Sort-Object InterfaceMetric | Select-Object -First 1
$ipconfig = Get-NetIPConfiguration -InterfaceIndex $internetRoute.InterfaceIndex
$subnet = Get-IPv4Subnet -IPAddress $ipconfig.IPv4Address.IPAddress -PrefixLength 24

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
    Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes $settings.'Autodeploy Interval'
}
$job = New-BcJob @autodeploySplat
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $job.JobId
Add-BcTag -SetId $set -Tags 'Beachhead', 'AutoDeploy'

Write-Host "Created autodeploy job with ID: $($job.JobId)"
#endregion#>

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
    Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes $settings.'Deployer Interval'
}
$job = New-BcJob @deployerSplat
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $job.JobId
Add-BcTag -SetId $set -Tags 'Beachhead', 'Deployer'

Write-Host "Created job: Beachhead Deployer"

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
    Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes $settings.'Monitor Interval'
}
$job = New-BcJob @monitorSplat
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $job.JobId
Add-BcTag -SetId $set -Tags 'Beachhead', 'Monitor'

Write-Host "Created job: Beachhead Monitor"
#endregion


#endregion