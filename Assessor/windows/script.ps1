#region dependencies
. .\windows\dependencies\subnets.ps1
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
#endregion

$settings = Get-Content .\settings.json | ConvertFrom-Json

#region PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if ($settings.'Use PowerShell 7'.ToString() -eq 'true') {
        pwsh.exe -ExecutionPolicy Bypass -File $($MyInvocation.MyCommand.Definition)
    }
}
#endregion

Write-Host 'Initializing authentication...'
Initialize-BcRunnerAuthentication -Settings $settings -WarningAction SilentlyContinue

$group = (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]

# Clean indexes
$existingIndexes = Get-BcDataStoreIndex -GroupId $group
if ($existingIndexes -contains 'beachheadcoverage') {
    Remove-BcDataStoreIndex -GroupId $group -IndexName 'beachheadcoverage'
}
if ($existingIndexes -contains 'beachheadcoveragesummary') {
    Remove-BcDataStoreIndex -GroupId $group -IndexName 'beachheadcoveragesummary'
}

# apply job tags
Write-Host 'Applying job tags...'
$set = New-BcSet
Add-BcSetToSet -TargetSetId $set -ObjectIds $settings.job_id | Out-Null
Add-BcTag -SetId $set -Tags 'Beachhead', 'Assessor' | Out-Null

#region Initiate asset discovery
Write-Host 'Initiating asset discovery job...'
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
                "Group ID"         = $group
                "Targets"          = if ($settings.'Targets'.Length -gt 0) {
                    $settings.'Targets'
                } else {
                    $null
                }
                "Use PowerShell 7" = ($settings.'Use PowerShell 7'.ToString() -eq 'true')
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

#region Initiate periodic jobs

#region Initiate deployer
Write-Host 'Initiating deploy job...'
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
            Settings           = @{
                "Use PowerShell 7" = ($settings.'Use PowerShell 7'.ToString() -eq 'true')
                Targets            = $settings.Targets
            }
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
Write-Host 'Initiating monitor job...'
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
            Settings           = @{
                "Use PowerShell 7" = ($settings.'Use PowerShell 7'.ToString() -eq 'true')
            }
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