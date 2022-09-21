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

# Download runner.exe
Get-BcAgentExecutable -Platform Windows64 -OutFile .\runner.exe

if ($settings.'PowerShell Remoting'.ToString() -eq 'true') {
    #region RemotePowerShell
    # get the host name
    $name = (Resolve-DnsName 192.168.77.6).NameHost

    # create the session
    $session = New-PSSession $name

    # Copy runner.exe and runway.exe to remote host
    Copy-Item .\runner.exe -Destination C:\temp\runner.exe -ToSession $session
    Copy-Item ..\..\runway.exe -Destination C:\temp\runway.exe -ToSession $session

    # Execute the script
    $str1 = (Get-Content .\repoScripts\functions\Enrollment.ps1 -Raw)
    $sb2 = {
        $execPath = 'C:\temp\runner.exe'
        $utilityPath = 'C:\temp\runway.exe'
        $token = $using:settings.'Enrollment Token'
        $agentDetails = Get-BcAgentDetails -UtilityPath $utilityPath -EnrollmentToken $token
        $enrollment = Get-BcAgentEnrollment -EnrollmentToken $token -Parameters $agentDetails
        Install-BcAgent -EnrollResponse $enrollment -AgentExecutablePath $execPath -EnrollmentToken $token
    }
    Invoke-Command -Session $session -ScriptBlock [scriptblock]::Create(($str1 + $sb2.ToString()))

    #endregion
}

if ($settings.WMI.ToString() -eq 'true') {
    #region WMI
    $name = (Get-WmiObject -Class Win32_ComputerSystem -ComputerName 192.168.77.6).Name

    $sb = {
        $execPath = 'C:\runner.exe'
        $utilityPath = 'C:\runway.exe'
        $token = 'ac582afae5b64228a1a628480b775dd8'
        Get-BcAgentExecutable -Platform Windows64 -OutFile C:\runner.exe
        $agentDetails = Get-BcAgentDetails -UtilityPath $utilityPath -EnrollmentToken $token
        $enrollment = Get-BcAgentEnrollment -EnrollmentToken $token -Parameters $agentDetails
        Install-BcAgent -EnrollResponse $enrollment -AgentExecutablePath $execPath -EnrollmentToken $token
    }
    #endregion
}