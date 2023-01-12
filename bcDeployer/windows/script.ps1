#region dependencies
. .\windows\dependencies\Get-BcEndpointAssetHelper.ps1
. .\windows\dependencies\Enrollment.ps1
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
#. .\windows\dependencies\wmiexec.ps1
. .\windows\dependencies\Get-IpAddressesInRange.ps1
. .\windows\dependencies\subnets.ps1
#endregion

$settings = Get-Content .\settings.json | ConvertFrom-Json

#region PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if ($settings.'Use PowerShell 7'.ToString() -eq 'true') {
        pwsh.exe -ExecutionPolicy Bypass -File $($MyInvocation.MyCommand.Definition)
    }
}
#endregion

Initialize-BcRunnerAuthentication -Settings $settings -WarningAction SilentlyContinue

$group = (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]

# get a whole list of targets
<#
    Returns an object like:
{
    "Type": "",
    "StartIp": "",
    "EndIp": ""
}
#>
$deployTargets = Parse-Targets -Targets $settings.Targets

$ips = foreach ($deployTarget in $deployTargets) {
    if ($null -ne $deployTarget['EndIp']) { 
        (Get-IpAddressesInRange -First $deployTarget['StartIp'] -Last $deployTarget['EndIp']).IpAddressToString
    } else {
        $deployTarget['StartIp']
    }
}

# STEP 1: try the built in auto deploy
foreach ($deployTarget in $deployTargets) {
    if ($null -ne $deployTarget['EndIp']) {
        Write-Host "Deploying to IP range: $($deployTarget['StartIp'])-$($deployTarget['EndIp'])"
        ..\..\..\runway.exe --loglevel debug -N -S $($settings.host) deploy --range "$($deployTarget['StartIp'])-$($deployTarget['EndIp'])" --token $($settings.'Enrollment Token')
    } else {
        Write-Host "Deploying to IP: $($deployTarget['StartIp'])"
        ..\..\..\runway.exe --loglevel debug -N -S $($settings.host) deploy --range "$($deployTarget['StartIp'])-$($deployTarget['StartIp'])" --token $($settings.'Enrollment Token')
    }
}
#endregion

# Then find all remaining EndpointAssets without Runners that are in the ips array
$remainingEndpoints = Get-BcEndpointAssetHelper -NoRunner -GroupId $group | Where-Object { $ips -contains $_.LastIPAddress }
Write-Host "Remaining target IPs: $($remainingEndpoints.LastIPAddress -join ', ')"

#region STEP 2: try Remove PowerShell Deployment

# Download runner.exe
Get-BcAgentExecutable -Platform Windows64 -OutFile .\runner.exe

foreach ($ip in $remainingEndpoints.LastIPAddress) {
    Write-Host "Attempting PowerShell Remoting deployment on $ip"
    #region RemotePowerShell
    # get the host name
    $name = (Resolve-DnsName $ip).NameHost

    # create the session
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
        Write-Host 'Failed to create session.'
    }

    #endregion
}
#endregion

# Then find all remaining EndpointAssets without Runners that are in the ips array
$remainingEndpoints = Get-BcEndpointAssetHelper -NoRunner -GroupId $group | Where-Object { $ips -contains $_.LastIPAddress }
Write-Host "Remaining target IPs: $($remainingEndpoints.LastIPAddress -join ', ')"

#region STEP 3: try WMI deployment
foreach ($ip in $remainingEndpoints.LastIPAddress) {
    Write-Host "Attempting WMI deployment on $ip"
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
#endregion