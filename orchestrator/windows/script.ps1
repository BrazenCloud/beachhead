#region dependencies
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
. .\windows\dependencies\Tee-BcLog.ps1
#endregion

#region PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if (-not (Test-Path '..\..\..\pwsh\pwsh.exe')) {
        Throw 'Pwsh missing, rerun deployer:start'
    }
    Write-Host 'Executing pwsh...'
    ..\..\..\pwsh\pwsh.exe -ExecutionPolicy Bypass -File $($MyInvocation.MyCommand.Definition)
} else {
    #endregion
    $settings = Get-Content .\settings.json | ConvertFrom-Json
    Initialize-BcRunnerAuthentication -Settings $settings -WarningAction SilentlyContinue
    $group = (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]
    $logSplat = @{
        Level   = 'Info'
        Group   = $group
        JobName = 'Orchestrator'
    }
    Tee-BcLog @logSplat -Message 'BrazenCloud Deployer Orchestrator initialized'

    # load coverage index
    $coverageSplat = @{
        GroupId     = $group
        QueryString = '{ "query": { "match_all": { } } }'
        IndexName   = 'deployercoverage'
    }
    $coverage = Invoke-BcQueryDataStoreHelper @coverageSplat
    $coverageHt = @{}
    foreach ($item in $coverage) {
        $coverageHt[$item.ipAddress] = $item
    }

    #region Deploy BC Agent
    $endpointAssets = Get-BcEndpointAssetHelper -NoRunner -GroupId $group

    # get endpoints needing bc agent within failure threshold
    $eaNeedBcAgent = foreach ($ea in $endpointAssets) {
        if ($coverageHt.Keys -contains $ea.LastIPAddress) {
            if ($coverageHt[$ea.LastIPAddress].bcAgentFailCount -lt [int]$settings.'Failure Threshold') {
                $ea
            }
        }
    }

    # check for currently running brazenAgent jobs
    $bcAgentDeployJobs = Get-DeployerJob -Group $group -JobName BrazenAgent -Take 10 | Where-Object { $_.TotalEndpointsRunning -gt 0 }
    $runningBcAgentDeployJobs = $bcAgentDeployJobs | Where-Object { $_.TotalEndpointsRunning -gt 0 }

    # only run if there are endpoint assets and no deployer jobs already running
    if ($eaNeedBcAgent.Count -gt 0 -and $runningBcAgentDeployJobs.Count -lt 1) {
        $set = New-BcSet
        # add runners to set
        Add-BcSetToSet -TargetSetId $set -ObjectIds $settings.prodigal_object_id | Out-Null
        $jobSplat = @{
            Name          = "Deployer BrazenAgent Deploy"
            GroupId       = $group
            EndpointSetId = $set
            IsEnabled     = $true
            IsHidden      = $false
            Actions       = @(
                @{
                    RepositoryActionId = (Get-BcRepository -Name 'deployer:brazenAgent').Id
                    Settings           = @{
                        'Enrollment Token' = (New-BcEnrollmentSession -Type 'EnrollPersistentRunner' -Expiration (Get-Date).AddDays(1) -GroupId $group -IsOneTime:$false).Token
                        Targets            = ($bcAgentDeployJobs).Count -eq 0 ? $settings.Targets : $eaNeedBcAgent.LastIPAddress -join ','
                    }
                }
            )
            Schedule      = New-BcJobScheduleObject -ScheduleType 'RunNow' -RepeatMinutes 0
        }
        $job = New-BcJob @jobSplat
        $set = New-BcSet
        Add-BcSetToSet -TargetSetId $set -ObjectIds $job.JobId
        Add-BcTag -SetId $set -Tags 'Deployer', 'BrazenAgent'
    }

    #endregion

    #region Deploy other required agents
    # Get agents to deploy
    $installCheck = (Get-BcRepository -Name 'deployer:installCheck').Id
    $agentInstalls = Invoke-BcQueryDataStoreHelper -GroupId $group -QueryString '{ "query": {"query_string" : {"query" : "agentInstall", "default_field" : "type" } } }' -IndexName deployerconfig

    # Get all endpointassets w/runner in current group
    $endpointAssets = Get-BcEndpointAssetHelper -HasRunner -GroupId $group

    # foreach agentInstall, get runners lacking the tag and assign the job
    :atd foreach ($atd in $agentInstalls) {
        Tee-BcLog @logSplat -Message "Checking for endpoints needing '$($atd.Name)'..."
        $agentJobName = "Deployer Deploy Agent: $($atd.Name)"

        # Get runners to deploy to
        $toAssign = ($endpointAssets | Where-Object { $_.Tags -notcontains $atd.installedTag }).Id
        Write-Host "Total endpoints missing tag: $($toAssign.Count)"

        # Check for existing jobs
        $runningAssets = foreach ($agentJob in (Get-BcJobByName -JobName $agentJobName -GroupId $group | Where-Object { $_.TotalEndpointsFinished -lt $_.TotalEndpointsRunning })) {
            $threads = Get-BcJobThread -JobId $agentJob.Id | Where-Object { $_.ThreadState -eq 'Running' } | Select-Object -ExpandProperty ProdigalObjectId
            if ($null -eq $threads -and $agentJob.TotalEndpointsFinished -eq 0 -and $agentJob.TotalEndpointsRunning -eq 0 -and $toAssign.Count -eq $agentJob.TotalEndpointsAssigned) {
                # might be an invalid job
                Tee-BcLog @logSplat -Message 'Possible invalid job detected.' -Level Error
                continue atd
            } else {
                $threads
            }
        }
        $runningAssets = $runningAssets | Select-Object -Unique
        Write-Host "Total assets already running: $($runningAssets.Count)"

        # filter out already running assets
        $toAssign = $toAssign | Where-Object { $runningAssets -notcontains $_ }
        Tee-BcLog @logSplat -Message "Total assets to assign: $($toAssign.Count)"

        if ($toAssign.Count -gt 0) {
            $deployActions = & {
                foreach ($action in $atd.actions) {
                    [hashtable]$settingsHt = $action.settings
                    @{
                        RepositoryActionId = (Get-BcRepository -Name $action.name).Id
                        Settings           = $settingsHt
                    }
                }
                @{
                    RepositoryActionId = $installCheck
                    Settings           = @{
                        'Agent Name'       = $atd.name
                        'Search Name'      = $atd.InstalledName
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
            Add-BcTag -SetId $set -Tags 'Deployer', 'AgentInstall'

            Tee-BcLog @logSplat -Message "Created job: Deployer Deploy Agent: $($atd.Name) with ID: '$($job.JobId)'"
        } else {
            Tee-BcLog @logSplat -Message "No agents need $($atd.Name)"
        }
    }
    #endregion
}