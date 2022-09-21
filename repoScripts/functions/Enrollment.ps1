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

Function Get-BcAgentDetails {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [string]$UtilityPath,
        [string]$Server = 'staging.brazencloud.com',
        [Parameter(Mandatory)]
        [string]$EnrollmentToken
    )
    $regex = '\> Enrollment: (Using ?)?(?<name>[^ ]+) (?<value>.*)\.'
    #        > Enrollment: UsingDesiredRunnerName default.
    $enrollment = & $UtilityPath -N -S $Server node -t $EnrollmentToken -d 0.00:00:00 --new | Where-Object { $_ -like '> Enrollment:*' }
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
        [string]$Server = 'staging.brazencloud.com'
    )
    $pfiles = $env:ProgramFiles
    if (-not (Test-Path $pfiles\Runway)) {
        New-Item $pfiles\Runway -ItemType Directory | Out-Null
    }

    $fullInstallPath = "$pfiles\Runway\$($EnrollResponse.nodeId)"

    if (-not (Test-Path $fullInstallPath)) {
        New-Item $fullInstallPath -ItemType Directory | Out-Null
    }
    Copy-Item $AgentExecutablePath -Destination $fullInstallPath\runner.exe

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
    if ($out -like '*SUCCESS') {
        Start-Service $serviceName
    } else {
        Throw "Service failed to create: $out"
    }
}