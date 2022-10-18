#region dependencies
. .\windows\dependencies\Get-IpAddressesInRange.ps1
. .\windows\dependencies\wmiexec.ps1
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
. .\windows\dependencies\Get-BcEndpointAssetHelper.ps1
. .\windows\dependencies\Enrollment.ps1
. .\windows\dependencies\Invoke-BcQueryDatastore2.ps1
#endregion

Initialize-BcRunnerAuthentication -Settings (Get-Content .\settings.json | ConvertFrom-Json)

$group = (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]

if ($settings.'IP Range'.Length -gt 0 -and $settings.'IP Range' -notmatch '(\d{1,3}\.){3}\d{1,3}\-(\d{1,3}\.){3}\d{1,3}') {
    Throw 'Invalid IP range. Expecting something like: 192.168.0.1-192.168.10.1'
}

## Build IP Address Array
$ips = & {
    if ($settings.'IP Range' -match '(\d{1,3}\.){3}\d{1,3}\-(\d{1,3}\.){3}\d{1,3}') {
        Get-IpAddressesInRange -First $settings.'IP Range'.Split('-')[0] -Last $settings.'IP Range'.Split('-')[1]
    }
    if ($settings.IPs.Length -gt 0) {
        $settings.IPs -split ',' | ForEach-Object { $_.Trim() }
    }
}

[System.IO.File]::WriteAllLines('.\IPs.txt', ($ips -join ','), [System.Text.UTF8Encoding]::UTF8)

#region First, try the built in auto doploy
$ipRange = $ips | ForEach-Object { [ipaddress]$_ } | Sort-Object Address
..\..\..\runway.exe --loglevel debug -N -S $($settings.host) deploy --range "$($ipRange[0].IPAddressToString)-$($ipRange[-1].IPAddressToString)" --token $($settings.'Enrollment Token')
#endregion

# Then find all remaining EndpointAssets without Runners that are in the ips array
$remainingEndpoints = Get-BcEndpointAssetHelper -NoRunner -GroupId $group | Where-Object { $ips -contains $_.LastIPAddress }
Write-Host "Remaining target IPs: $($remainingEndpoints.LastIPAddress -join ', ')"

#region Now try Remove PowerShell Deployment

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

#region Now try WMI deployment
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