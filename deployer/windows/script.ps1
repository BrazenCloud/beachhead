#region dependencies
. .\windows\dependencies\Get-BcJobHelper.ps1
. .\windows\dependencies\Get-BcEndpointAssetHelper.ps1
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
. .\windows\dependencies\Invoke-BcQueryDatastore2.ps1
#endregion

Initialize-BcRunnerAuthentication -Settings (Get-Content .\settings.json | ConvertFrom-Json)

$group = (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]

#region Deploy BC Agent
$bcDeployerJobName = "Beachhead BrazenAgent Deploy"
$ea = Get-BcEndpointAssetHelper -NoRunner -GroupId $group

# check for currently running job
$deployerJobs = Get-BcJobByName -JobName $bcDeployerJobName | Where-Object { $_.TotalEndpointsRunning -gt 0 }

# only run if there are endpoint assets and no deployer jobs already running
if ($ea.Count -gt 0 -and $deployerJobs.Count -lt 1) {
    $set = New-BcSet
    # add runners to set
    Add-BcSetToSet -TargetSetId $set -ObjectIds $settings.prodigal_object_id | Out-Null
    $jobSplat = @{
        Name          = $bcDeployerJobName = "Beachhead BrazenAgent Deploy"
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
    $agentJobName = "Beachhead Deploy: $($atd.Name)"

    # Get runners to deploy to
    $toAssign = ($endpointAssets | Where-Object { $_.Tags -notcontains $atd.installedTag }).Id

    # Check for existing jobs
    $runningAssets = foreach ($agentJob in (Get-BcJobHelper -JobName $agentJobName -GroupId $group | Where-Object { $_.TotalEndpointsRunning -gt 0 })) {
        Get-BcJobThread -JobId $agentJob.Id | Where-Object { $_.ThreadState -eq 'Running' } | Select-Object -ExpandProperty ProdigalObjectId
    }
    $runningAssets = $runningAssets | Select-Object -Unique

    # filter out already running assets
    $toAssign = $toAssign | Where-Object { $runningAssets -notcontains $_ }

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
            Name          = $agentJobName
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