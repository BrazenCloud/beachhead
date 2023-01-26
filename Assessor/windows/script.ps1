#region dependencies
. .\windows\dependencies\subnets.ps1
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
. .\windows\dependencies\Tee-BcLog.ps1
#endregion

Write-Host '### Beachhead Start ###'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host 'PowerShell version is not PowerShell 7, evaluating...'

    $os = Get-WmiObject -Class Win32_OperatingSystem
    [version]$osVersion = $os.Version
    # If OS is earlier than Win10, apply KB3118401
    # This is required for PowerShell 7
    if ($osVersion.Major -lt 10) {
        $is64bit = $os.OSArchitecture = '64-bit'
        $osVersionString = "$($osVersion.Major).$($osVersion.Minor)"
        Write-Host "Detected OS version: $osVersionString"
        Write-Host "Version is less than 10, a Universal C Runtime is required and will be installed..."
        switch ($osVersionString) {
            #6.0 - Vista/2008
            '6.0' {
                if ($is64bit) {
                    $uri = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2016/02/windows6.0-kb3118401-x64_abbfdb3452bded83cde9fc280f314a3f0f0f3146.msu'
                } else {
                    $uri = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2016/02/windows6.0-kb3118401-x86_8a1d950f6e32e086f580ce2812c2156edeaf8faa.msu'
                }
            }
            #6.1 - 7/2008r2
            '6.1' {
                if ($is64bit) {
                    $uri = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2016/02/windows6.1-kb3118401-x64_99153d75ee4d103a429464cdd9c63ef4e4957140.msu'
                } else {
                    $uri = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/updt/2016/02/windows6.1-kb3118401-x86_db0267a39805ae9e98f037a5f6ada5b34fa7bdb2.msu'
                }
            }
            #6.2 - 8/2012
            '6.2' {
                if ($is64bit) {
                    $uri = 'https://download.microsoft.com/download/8/E/3/8E3AED94-65F6-43A4-A502-1DE3881EA4DA/Windows8-RT-KB3118401-x64.msu'
                } else {
                    Throw 'Unsupported OS'
                }
            }
            #6.3 - 8.1/2012r2
            '6.3' {
                if ($is64bit) {
                    $uri = 'https://download.microsoft.com/download/F/E/7/FE776F83-5C58-47F2-A8CF-9065FE6E2775/Windows8.1-KB3118401-x64.msu'
                } else {
                    $uri = 'https://download.microsoft.com/download/5/E/8/5E888014-D156-44C8-A25B-CA30F0CCDA9F/Windows8.1-KB3118401-x86.msu'
                }
            }
        }
        Write-Host 'Validating update...'
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest $uri -OutFile .\update.msu
        & wusa.exe "$((Get-Item .\update.msu).FullName)" /quiet /norestart
        Write-Host "sleeping after update..."
        Start-Sleep -Seconds 5
    }

    Write-Host "Extracting PowerShell..."
    .\windows\7z\7za.exe x .\windows\pwsh.7z
    if (Test-Path ..\..\..\pwsh) {
        Remove-Item ..\..\..\pwsh -Force -Recurse -Confirm:$false
    }
    Move-Item .\pwsh -Destination..\..\..\ -Force -Confirm:$false
    Write-Host 'Executing pwsh...'
    ..\..\..\pwsh\pwsh.exe -ExecutionPolicy Bypass -File $($MyInvocation.MyCommand.Definition)
} else {

    $settings = Get-Content .\settings.json | ConvertFrom-Json

    Write-Host 'Initializing authentication...'
    Initialize-BcRunnerAuthentication -Settings $settings -WarningAction SilentlyContinue
    $group = (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]
    $PSDefaultParameterValues = @{
        'Tee-BcLog:Level' = 'Info';
        'Too-BcLog:Group' = $group
    }

    Tee-BcLog -Message 'BrazenCloud Deployer initialized'

    # Clean indexes
    Write-Host 'Cleaning coverage indexes...'
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
                    "Group ID" = $group
                    "Targets"  = if ($settings.'Targets'.Length -gt 0) {
                        $settings.'Targets'
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
                    Targets = $settings.Targets
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
                Settings           = @{}
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

    Write-Host 'Beachhead initialized.'
    #endregion
}