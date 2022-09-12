Function Get-BrazenCloudDaemonToken {
    # outputs the session token
    [OutputType([System.String])]
    [CmdletBinding()]
    param (
        [string]$aToken,
        [string]$Domain
    )
    $authResponse = Invoke-WebRequest -UseBasicParsing -Uri "$Domain/api/v2/auth/ping" -Headers @{
        Authorization = "Daemon $aToken"
    }
    
    if ($authResponse.Headers.Authorization -like 'Session *') {
        return (($authResponse.Headers.Authorization | Select-Object -First 1) -split ' ')[1]
    } else {
        Throw 'Failed auth'
        exit 1
    }
}