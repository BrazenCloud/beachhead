#region dependencies
. .\windows\dependencies\subnets.ps1
. .\windows\dependencies\Enrollment.ps1
#. .\windows\dependencies\wmiexec.ps1
. .\windows\dependencies\Get-IpAddressesInRange.ps1
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
. .\windows\dependencies\Parse-Targets.ps1
. .\windows\dependencies\Tee-BcLog.ps1
#endregion

function Get-BeachheadMonitorJob {
    [OutputType([BrazenCloudSdk.PowerShell.Models.IJobQueryView])]
    [cmdletbinding()]
    param (
        [string]$group
    )
    $skip = 0
    $take = 1000
    $query = @{
        includeSubgroups  = $false
        MembershipCheckId = $group
        skip              = $skip
        take              = $take
        sortDirection     = 0
        filter            = @{
            children = @(
                @{
                    Left     = 'Name'
                    Operator = ':'
                    Right    = 'Beachhead Monitor'
                },
                @{
                    Left     = 'Groups'
                    Operator = '='
                    Right    = $group
                }
            )
            operator = 'AND'
        }
    }
    (Invoke-BcQueryJob -Query $query).Items
}
Function Update-FailCounts {
    [cmdletbinding()]
    param (
        [string[]]$Ips,
        [ValidateSet('bcAgentFailCount', 'bcAgentPsRemoteFailCount', 'bcAgentWmiFailCount')]
        [string]$Stage
    )
    # loop if monitor is running
    $repeat = $true
    while ($repeat) {
        $repeat = $false
        if ((Get-BeachheadMonitorJob).TotalEndpointsRunning -gt 0) {
            Write-Host 'Monitor is running.'
            $repeat = $true
            Start-Sleep -Seconds 5
        } else {
            # get existing items
            $coverageSplat = @{
                GroupId     = $group
                QueryString = '{ "query": { "match_all": { } } }'
                IndexName   = 'beachheadcoverage'
            }
            $coverage = Invoke-BcQueryDataStoreHelper @coverageSplat
            $coverageHt = @{}
            foreach ($item in $coverage) {
                $coverageHt[$item.ipAddress] = $item
            }
            # updating data
            foreach ($ip in $Ips) {
                if ($coverageHt.Keys -contains $ip) {
                    $coverageHt[$ip].$Stage = $coverageHt[$ip].$Stage + 1
                }
            }
        }
        if ((Get-BeachheadMonitorJob).TotalEndpointsRunning -gt 0) {
            Write-Host 'Monitor is running.'
            $repeat = $true
            Start-Sleep -Seconds 5
        } else {
            Remove-BcDataStoreEntry -GroupId $group -IndexName 'beachheadcoverage' -DeleteQuery '{"query": {"match_all": {} } }'
            # uploading data
            for ($x = 0; $x -lt $coverageHt.Keys.Count; $x = $x + 100) {
                $hts = @($coverageHt.Keys)[$x..$($x + 100)] | ForEach-Object {
                    $coverageHt[$_]
                }
                $itemSplat = @{
                    GroupId   = $group
                    IndexName = 'beachheadcoverage'
                    Data      = $hts | ForEach-Object { ConvertTo-Json $_ -Compress }
                }
                Invoke-BcBulkDataStoreInsert @itemSplat
            }
        }
    }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    if (-not (Test-Path '..\..\..\pwsh\pwsh.exe')) {
        Throw 'Pwsh missing, rerun assessor'
    }
    Write-Host 'Executing pwsh...'
    ..\..\..\pwsh\pwsh.exe -ExecutionPolicy Bypass -File $($MyInvocation.MyCommand.Definition)
} else {
    $settings = Get-Content .\settings.json | ConvertFrom-Json
    Initialize-BcRunnerAuthentication -Settings $settings -WarningAction SilentlyContinue
    $group = (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]
    $logSplat = @{
        Level   = 'Info'
        Group   = $group
        JobName = 'BrazenAgent Deployer'
    }
    Tee-BcLog @logSplat -Message 'BrazenCloud BrazenAgent Deployer initialized'

    # Get a whole list of targets
    <#
    Returns an object like:
    {
        "Type": "",
        "StartIp": "",
        "EndIp": ""
    }
    #>
    $deployTargets = Parse-Targets -Targets $settings.Targets
    # Build master IP list
    $ips = foreach ($deployTarget in $deployTargets) {
        if ($null -ne $deployTarget['EndIp']) { 
        (Get-IpAddressesInRange -First $deployTarget['StartIp'] -Last $deployTarget['EndIp']).IpAddressToString
        } else {
            $deployTarget['StartIp']
        }
    }

    Tee-BcLog @logSplat -Message "Starting IP count: $($ips.Count)"

    #region STEP 1: try the built in auto deploy
    foreach ($deployTarget in $deployTargets) {
        if ($null -ne $deployTarget['EndIp']) {
            Tee-BcLog @logSplat -Message "Deploying to IP range: $($deployTarget['StartIp'])-$($deployTarget['EndIp'])"
            ..\..\..\runway.exe -N -S $($settings.host) deploy --range "$($deployTarget['StartIp'])-$($deployTarget['EndIp'])" --token $($settings.'Enrollment Token')
        } else {
            Tee-BcLog @logSplat -Message "Deploying to IP: $($deployTarget['StartIp'])"
            ..\..\..\runway.exe -N -S $($settings.host) deploy --range "$($deployTarget['StartIp'])-$($deployTarget['StartIp'])" --token $($settings.'Enrollment Token')
        }
    }
    #endregion

    #region In between

    # Pause long enough for runners to come online
    Tee-BcLog @logSplat -Message 'Pausing for runners to come online.'
    Start-Sleep -Seconds 30

    # Then find all remaining EndpointAssets without Runners that are in the ips array
    $remainingEndpoints = Get-BcEndpointAssetHelper -NoRunner -GroupId $group | Where-Object { $ips -contains $_.LastIPAddress }
    Tee-BcLog @logSplat -Message "Remaining target IP count: $($remainingEndpoints.Count)"
    Tee-BcLog @logSplat -Message "Remaining target IPs: $($remainingEndpoints.LastIPAddress -join ', ')"

    

    if ($remainingEndpoints.Count -eq 0) {
        Tee-BcLog @logSplat -Message 'No remaining endpoints, exiting.'
        Start-BeachheadJob -JobName 'Deployer' -Group $group
        return
    } else {
        Update-FailCounts -Ips $remainingEndpoints.LastIPAddress -Stage bcAgentFailCount
    }

    #endregion

    #region STEP 2: try Remove PowerShell Deployment

    # Download runner.exe
    Get-BcAgentExecutable -Platform Windows64 -OutFile .\runner.exe

    foreach ($ip in $remainingEndpoints.LastIPAddress) {
        Tee-BcLog @logSplat -Message "Attempting PowerShell Remoting deployment on $ip"
        # Lookup the host name
        $dnsName = powershell.exe -OutputFormat XML -NonInteractive -C "& {Resolve-DnsName $ip}"
        $name = $dnsName.NameHost

        if ($null -ne $name) {
            # Create the session
            $session = New-PSSession $name -ErrorAction SilentlyContinue

            if ($null -ne $session) {
                # Copy runner.exe and runway.exe to remote host
                Copy-Item ..\..\..\runner.exe -Destination C:\runner.exe -ToSession $session
                Copy-Item ..\..\..\runway.exe -Destination C:\runway.exe -ToSession $session

                # Execute the script
                $str1 = (Get-Content .\windows\dependencies\Enrollment.ps1 -Raw)
                $sb2 = {
                    $execPath = 'C:\runner.exe'
                    $utilityPath = 'C:\runway.exe'
                    $token = $using:settings.'Enrollment Token'
                    Write-Host "Retrieving agent details..."
                    $agentDetails = Get-BcAgentDetails -UtilityPath $utilityPath
                    Write-Host "Requesting enrollment..."
                    $enrollment = Get-BcAgentEnrollment -EnrollmentToken $token -Parameters $agentDetails
                    Write-Host "Installing agent..."
                    Install-BcAgent -EnrollResponse $enrollment -AgentExecutablePath $execPath -EnrollmentToken $token
                    Write-Host "Cleaning..."
                    if (Test-Path $execPath) {
                        Remove-Item $execPath -Force
                    }
                    if (Test-Path $utilityPath) {
                        Remove-Item $utilityPath -Force
                    }
                    Write-Host "Complete"
                }
                Invoke-Command -Session $session -ScriptBlock ([scriptblock]::Create(($str1 + $sb2.ToString())))

                Remove-PSSession $session
            } else {
                Tee-BcLog @logSplat -Message 'Failed to create session.' -Level Error
            }
        } else {
            Tee-BcLog @logSplat -Message 'Failed to resolve IP to DNS name. Unable to establish remote PowerShell session.' -Level Error
        }
    }
    #endregion

    #region In between

    # Pause long enough for runners to come online
    Tee-BcLog @logSplat -Message 'Pausing for runners to come online.'
    Start-Sleep -Seconds 30

    # Then find all remaining EndpointAssets without Runners that are in the ips array
    $remainingEndpoints = Get-BcEndpointAssetHelper -NoRunner -GroupId $group | Where-Object { $ips -contains $_.LastIPAddress }
    Tee-BcLog @logSplat -Message "Remaining target IP count: $($remainingEndpoints.Count)"
    Tee-BcLog @logSplat -Message "Remaining target IPs: $($remainingEndpoints.LastIPAddress -join ', ')"

    if ($remainingEndpoints.Count -eq 0) {
        Tee-BcLog @logSplat -Message 'No remaining endpoints, exiting.'
        Start-BeachheadJob -JobName 'Deployer' -Group $group
        return
    } else {
        Update-FailCounts -Ips $remainingEndpoints.LastIPAddress -Stage bcAgentPsRemoteFailCount
    }

    #endregion

    #region STEP 3: try WMI deployment
    # requires Windows PS 5.1
    $windowsPsVersion = powershell.exe -c { $PSVersionTable }
    if ($windowsPsVersion.Major -eq 5 -and $windowsPsVersion.Minor -eq 1) {
        foreach ($ip in $remainingEndpoints.LastIPAddress) {
            Tee-BcLog @logSplat -Message "Attempting WMI deployment on $ip"
            $name = (Get-WmiObject -Class Win32_ComputerSystem -ComputerName $ip).Name


            $str1 = (Get-Content .\windows\dependencies\Enrollment.ps1 -Raw)
            $str2 = "`n`$token = '$($settings.'Enrollment Token')'`n"
            $sb3 = {
                $utilityPath = 'C:\runway.exe'
                Get-BcUtilityExecutable -Platform Windows64 -OutFile $utilityPath
                Start-Process $utilityPath -ArgumentList '-N', '-S', 'staging.brazencloud.com', 'install', '-t', $token -Wait
                Write-Output "Cleaning..."
                if (Test-Path $utilityPath) {
                    Remove-Item $utilityPath -Force
                }
                Write-Output "Complete"
            }

            $command = $str1 + $str2 + $sb3.ToString()
            .\windows\dependencies\wmiexec.ps1 -ComputerName $name -Command $command
        }
    } else {
        Tee-BcLog @logSplat -Message "Unable to attempt WMI deployment, Windows PowerShell not at v5.1." -Level Error
    }
    #endregion

    # Then find all remaining EndpointAssets without Runners that are in the ips array
    $remainingEndpoints = Get-BcEndpointAssetHelper -NoRunner -GroupId $group | Where-Object { $ips -contains $_.LastIPAddress }
    Tee-BcLog @logSplat -Message "Remaining target IP count: $($remainingEndpoints.Count)"
    Tee-BcLog @logSplat -Message "Remaining target IPs: $($remainingEndpoints.LastIPAddress -join ', ')"

    if ($remainingEndpoints.Count -gt 0) {
        Update-FailCounts -Ips $remainingEndpoints.LastIPAddress -Stage bcAgentWmiFailCount
    }
    Tee-BcLog @logSplat -Message "BrazenAgent deploy complete."
    Start-BeachheadJob -JobName 'Deployer' -Group $group
}