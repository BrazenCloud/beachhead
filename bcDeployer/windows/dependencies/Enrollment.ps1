Function Get-BcAgentExecutable {
    [cmdletbinding()]
    param (
        [ValidateSet('Windows64', 'Windows32')]
        [string]$Platform = 'Windows64',
        [string]$Server = 'staging.brazencloud.com',
        [Parameter(Mandatory)]
        [string]$OutFile
    )
    Invoke-WebRequest -Method Get -Uri "https://$Server/api/v2/content/public?key=runner&platform=$Platform" -OutFile $OutFile
}

Function Get-BcUtilityExecutable {
    [cmdletbinding()]
    param (
        [ValidateSet('Windows64', 'Windows32')]
        [string]$Platform = 'Windows64',
        [string]$Server = 'staging.brazencloud.com',
        [Parameter(Mandatory)]
        [string]$OutFile
    )
    Invoke-WebRequest -Method Get -Uri "https://$Server/api/v2/content/public?key=runway&platform=$Platform" -OutFile $OutFile
}

Function Get-BcAgentDetails {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [string]$UtilityPath,
        [string]$Server = 'staging.brazencloud.com'
    )
    $regex = '\> Enrollment: (Using ?)?(?<name>[^ ]+) (?<value>.*)\.'
    #        > Enrollment: UsingDesiredRunnerName default.
    $enrollment = & $UtilityPath -N -S $Server node -t 'blah' -d 0.00:00:00 --new | Where-Object { $_ -like '> Enrollment:*' }
    $ht = @{}
    foreach ($line in $enrollment) {
        if ($line -match $regex) {
            $ht[$Matches.name] = $Matches.value.Trim()
        }
    }
    $ht
}

Function Get-BcAgentEnrollment {
    [cmdletbinding()]
    param (
        [string]$Server = 'staging.brazencloud.com',
        [Parameter(Mandatory)]
        [string]$EnrollmentToken,
        [Parameter(Mandatory)]
        [hashtable]$Parameters,
        [hashtable]$Interfaces
    )
    $body = @{
        enrollmentToken = $EnrollmentToken
        parameters      = $Parameters
    }
    if ($PSBoundParameters.Keys -contains 'Interfaces') {
        $body['interfaces'] = $Interfaces
    }
    Invoke-RestMethod -Method Post -Uri "https://$Server/api/v2/auth/enroll" -Body ($body | ConvertTo-Json) -Headers @{
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }
}

Function Set-BcAgentPermissions {
    [cmdletbinding()]
    param (
        [string]$AgentExecutablePath
    )
    # Allow full access to administrators
    # deny access to guests
    # deny access to ANONYMOUS LOGON
    # Owner = comp\administrators
    # Nothing else
    if (-not (Test-Path $AgentExecutablePath -PathType Leaf)) {
        throw "'$AgentExecutablePath' is not a valid path."
    }
    $acl = [System.Security.AccessControl.FileSecurity]::new()
    #$acl = Get-Acl $AgentExecutablePath
    # clear acl
    #foreach ($ace in $acl.Access) {
    #    $acl.RemoveAccessRuleAll($ace)
    #}
    # full control to admins
    $adminAce = [System.Security.AccessControl.FileSystemAccessRule]::new(
        [System.Security.Principal.NTAccount]'Builtin\Administrators',
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.InheritanceFlags]::None,
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    # deny guests
    $guestAce = [System.Security.AccessControl.FileSystemAccessRule]::new(
        [System.Security.Principal.NTAccount]'Builtin\Guests',
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.InheritanceFlags]::None,
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Deny
    )
    # deny anonymous logon
    $alAce = [System.Security.AccessControl.FileSystemAccessRule]::new(
        [System.Security.Principal.NTAccount]'ANONYMOUS LOGON',
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.InheritanceFlags]::None,
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Deny
    )
    $acl.AddAccessRule($adminAce)
    $acl.AddAccessRule($guestAce)
    $acl.AddAccessRule($alAce)
    $acl.SetOwner([System.Security.Principal.NTAccount]'Builtin\Administrators')
    $acl.SetAccessRuleProtection($true, $true)
    foreach ($item in (Get-ChildItem (Get-Item $AgentExecutablePath).Directory.FullName -File)) {
        Write-Host "Applying ACL to $($item.Name)"
        Set-Acl $item.FullName -AclObject $acl
    }
}

Function Install-BcAgent {
    [cmdletbinding()]
    param (
        <#
        {
            "nodeId": "string",
            "nodeSecretKey": "string",
            "parameters": {
                "property1": "string",
                "property2": "string"
            }
        }
        #>
        [Parameter(Mandatory)]
        [object]$EnrollResponse,
        [Parameter(Mandatory)]
        [string]$AgentExecutablePath,
        [Parameter(Mandatory)]
        [string]$EnrollmentToken,
        [string]$Server = 'staging.brazencloud.com',
        [switch]$MoveAgentExecutable
    )
    $pfiles = $env:ProgramFiles
    if (-not (Test-Path $pfiles\Runway)) {
        New-Item $pfiles\Runway -ItemType Directory | Out-Null
    }

    $fullInstallPath = "$pfiles\Runway\$($EnrollResponse.nodeId)"

    if (-not (Test-Path $fullInstallPath)) {
        New-Item $fullInstallPath -ItemType Directory | Out-Null
    }
    if ($MoveAgentExecutable.IsPresent) {
        Move-Item $AgentExecutablePath -Destination $fullInstallPath\runner.exe
    } else {
        Copy-Item $AgentExecutablePath -Destination $fullInstallPath\runner.exe
    }

    $x = 0
    $serviceName = "RunwayRunnerService"
    $displayName = "Runway Runner Service"
    while ((Get-Service $serviceName -ErrorAction SilentlyContinue)) {
        $x++
        $serviceName = "RunwayRunnerService$x"
        $displayName = "Runway Runner Service $x"
    }
    $serviceName

    $ht = @{
        atoken      = $EnrollResponse.nodeSecretKey
        etoken      = $EnrollmentToken
        host        = "https://$Server"
        identity    = $EnrollResponse.nodeId
        servicename = $serviceName
    }
    $json = $ht | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllLines("$fullInstallPath\runner_settings.json", $json, [System.Text.UTF8Encoding]::new($false))

    $out = & sc.exe create $serviceName type=own start=auto error=normal binPath="\`"$fullInstallPath\runner.exe\`" service" displayname=$displayName
    Set-BcAgentPermissions -AgentExecutablePath $fullInstallPath\runner.exe
    if ($out -like '*SUCCESS') {
        Start-Service $serviceName
    } else {
        Throw "Service failed to create: $out"
    }
}
<#
$execPath = 'C:\runner.exe'
$utilityPath = 'C:\runway.exe'
$token = 'ac582afae5b64228a1a628480b775dd8'
Get-BcAgentExecutable -Platform Windows64 -OutFile C:\runner.exe
$agentDetails = Get-BcAgentDetails -UtilityPath $utilityPath -EnrollmentToken $token
$enrollment = Get-BcAgentEnrollment -EnrollmentToken $token -Parameters $agentDetails
Install-BcAgent -EnrollResponse $enrollment -AgentExecutablePath $execPath -EnrollmentToken $token
#>