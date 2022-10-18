#region dependencies
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
. .\windows\dependencies\Get-BcEndpointAssetHelper.ps1
. .\windows\dependencies\Invoke-BcQueryDatastore2.ps1
#endregion

Initialize-BcRunnerAuthentication -Settings (Get-Content .\settings.json | ConvertFrom-Json)

$group = (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]

#region Deploy BC Agent
$ea = Get-BcEndpointAssetHelper -NoRunner -GroupId $group

if ($ea.Count -gt 0) {
    $set = New-BcSet
    # add runners to set
    Add-BcSetToSet -TargetSetId $set -ObjectIds $settings.prodigal_object_id | Out-Null
    $jobSplat = @{
        Name          = "Beachhead BrazenAgent Deploy"
        GroupId       = $group
        EndpointSetId = $set
        IsEnabled     = $true
        IsHidden      = $false
        Actions       = @(
            @{
                RepositoryActionId = (Get-BcRepository -Name 'beachhead:bcDeployer').Id
                Settings           = @{
                    'Enrollment Token' = (New-BcEnrollmentSession -Type 'EnrollPersistentRunner' -Expiration (Get-Date).AddDays(1) -GroupId $group -IsOneTime:$false).Token
                    IPs                = ($ea.LastIPAddress -join ',')
                }
            }
        )
        Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes 0
    }
    $job = New-BcJob @jobSplat
    $set = New-BcSet
    Add-BcSetToSet -TargetSetId $set -ObjectIds $job.JobId
    Add-BcTag -SetId $set -Tags 'Beachhead', 'BrazenAgentInstall'
}

#endregion

#region Deploy other required agents
# Get agents to deploy
$installCheck = (Get-BcRepository -Name 'beachhead:installCheck').Id
$agentInstalls = Invoke-BcQueryDatastore2 -GroupId $group -Query @{query_string = @{query = 'agentInstall'; default_field = 'type' } } -IndexName beachheadconfig

# Get all endpointassets w/runner in current group
$endpointAssets = Get-BcEndpointAssetHelper -HasRunner -GroupId $group

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
                    RepositoryActionId = (Get-BcRepository -Name $action.name).Id
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
            Name          = "Beachhead Deploy: $($atd.Name)"
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
#endregion