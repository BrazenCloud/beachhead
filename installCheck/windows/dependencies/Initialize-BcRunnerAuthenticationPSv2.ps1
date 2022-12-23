Function Initialize-BcRunnerAuthenticationPSv2 {
    [cmdletbinding()]
    param (
        [string]$aToken,
        [string]$Domain
    )
    Function Get-BrazenCloudDaemonToken {
        # outputs the session token
        [OutputType([System.String])]
        [CmdletBinding()]
        param (
            [string]$aToken,
            [string]$Domain
        )

        $resp = Invoke-WebRequestPSv2 -RawResponse -Uri "https://$Domain/api/v2/auth/ping" -Headers @{
            Authorization = "Daemon $aToken"
        }

        if ($resp.GetResponseHeader('Authorization') -like 'Session *') {
            return (($resp.GetResponseHeader('Authorization') | Select-Object -First 1) -split ' ')[1]
        } else {
            Throw 'Failed auth'
            exit 1
        }
    }

    # set up sdk auth
    $env:BrazenCloudSessionToken = Get-BrazenCloudDaemonToken -aToken $aToken -Domain $Domain
    $env:BrazenCloudDomain = $Domain
}