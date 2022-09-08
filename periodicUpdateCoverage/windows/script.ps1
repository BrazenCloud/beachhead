#region Prep
# load settings.json
$settings = Get-Content .\settings.json | ConvertFrom-Json
$settings

# function to auth as the runner
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