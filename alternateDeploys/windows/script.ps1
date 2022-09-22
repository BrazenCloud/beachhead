#region Prep
# load settings.json
$settings = Get-Content .\settings.json | ConvertFrom-Json
$settings

# function to auth as the runner
. .\windows\dependencies\Get-BrazenCloudDaemonToken.ps1

# set up the BrazenCloud module
if (-not (Get-Module BrazenCloud -ListAvailable)) {
    Install-Module BrazenCloud -MinimumVersion 0.3.2 -Force
}
$wp = $WarningPreference
$WarningPreference = 'SilentlyContinue'
Import-Module BrazenCloud | Out-Null
$WarningPreference = $wp
$env:BrazenCloudSessionToken = Get-BrazenCloudDaemonToken -aToken $settings.atoken -Domain $settings.host
$env:BrazenCloudSessionToken
$env:BrazenCloudDomain = $settings.host.split('/')[-1]

#endregion

. .\windows\dependencies\Enrollment.ps1
. .\windows\dependencies\Get-IpAddressesInRange.ps1

if ($settings.'IP Range' -notmatch '(\d{1,3}\.){3}\d{1,3}\-(\d{1,3}\.){3}\d{1,3}') {
    Throw 'Invalid IP range. Expecting something like: 192.168.0.1-192.168.10.1'
}

$ips = Get-IpAddressesInRange -First $settings.'IP Range'.Split('-')[0] -Last $settings.'IP Range'.Split('-')[1]

# Download runner.exe
Get-BcAgentExecutable -Platform Windows64 -OutFile .\runner.exe

foreach ($ip in $ips) {
    if ($settings.'PowerShell Remoting'.ToString() -eq 'true') {
        Write-Host "Attempting PowerShell Remoting deployment on $($ip.ToString())"
        #region RemotePowerShell
        # get the host name
        $name = (Resolve-DnsName $ip.ToString()).NameHost

        # create the session
        $session = New-PSSession $name

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

        #endregion
    } elseif ($settings.WMI.ToString() -eq 'true') {
        #region WMI
        Write-Host "Attempting WMI deployment on $($ip.ToString())"
        $name = (Get-WmiObject -Class Win32_ComputerSystem -ComputerName $ip.ToString()).Name
        

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
        #endregion
    }
}