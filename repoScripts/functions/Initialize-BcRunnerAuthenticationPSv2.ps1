Function Initialize-BcRunnerAuthentication {
    [cmdletbinding()]
    param (
        [psobject]$Settings
    )
    Function Get-BrazenCloudDaemonToken {
        # outputs the session token
        [OutputType([System.String])]
        [CmdletBinding()]
        param (
            [string]$aToken,
            [string]$Domain
        )

        $resp = Invoke-WebRequestPSv2 -RawResponse -Uri "$Domain/api/v2/auth/ping" -Headers @{
            Authorization = "Daemon $aToken"
        }

        if ($resp.GetResponseHeader('Authorization') -like 'Session *') {
            return (($resp.GetResponseHeader('Authorization') | Select-Object -First 1) -split ' ')[1]
        } else {
            Throw 'Failed auth'
            exit 1
        }
    }

    if ($PSBoundParameters.Keys -notcontains 'Settings') {
        if (Test-Path .\settings.json) {
            $Settings = Get-Content .\settings.json | ConvertFrom-Json
        } else {
            Throw 'Unable to load settings. Missing .\settings.json or the -Settings parameter.'
        }
    }

    $global:settings = $Settings

    # set up sdk auth
    $env:BrazenCloudSessionToken = Get-BrazenCloudDaemonToken -aToken $settings.atoken -Domain $settings.host
    $env:BrazenCloudDomain = $settings.host.split('/')[-1]
}