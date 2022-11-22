#region dependencies
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
#endregion

Initialize-BcRunnerAuthentication -Settings (Get-Content .\settings.json | ConvertFrom-Json) -WarningAction SilentlyContinue

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
$agentInstalls = Invoke-BcQueryDataStoreHelper -GroupId $group -QueryString '{"query_string" : {"query" : "agentInstall", "default_field" : "type" } }' -IndexName beachheadconfig

# Get all endpointassets w/runner in current group
$endpointAssets = Get-BcEndpointAssetHelper -HasRunner -GroupId $group

# foreach agentInstall, get runners lacking the tag and assign the job
foreach ($atd in $agentInstalls) {
    Write-Host "Checking for '$($atd.Name)' deploys..."
    $agentJobName = "Beachhead Deploy: $($atd.Name)"

    # Get runners to deploy to
    $toAssign = ($endpointAssets | Where-Object { $_.Tags -notcontains $atd.installedTag }).Id
    Write-Host "Total assets missing tag: $($toAssign.Count)"

    # Check for existing jobs
    $runningAssets = foreach ($agentJob in (Get-BcJobByName -JobName $agentJobName -GroupId $group | Where-Object { $_.TotalEndpointsRunning -gt 0 })) {
        Get-BcJobThread -JobId $agentJob.Id | Where-Object { $_.ThreadState -eq 'Running' } | Select-Object -ExpandProperty ProdigalObjectId
    }
    $runningAssets = $runningAssets | Select-Object -Unique
    Write-Host "Total assets already running: $($runningAssets.Count)"

    # filter out already running assets
    $toAssign = $toAssign | Where-Object { $runningAssets -notcontains $_ }
    Write-Host "Total assets to assign: $($toAssign.Count)"

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
        Add-BcSetToSet -TargetSetId $set -ObjectIds $toAssign
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