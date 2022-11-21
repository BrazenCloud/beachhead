Function Initialize-BcRunnerAuthentication {
    [cmdletbinding()]
    param (
        [psobject]$Settings,
        [version]$ModuleVersion = '0.3.3',
        [string]$Prerelease = 'beta3'
    )
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

    Function Test-ModulePresent {
        [CmdletBinding()]
        param (
            [string]$Name,
            [version]$Version,
            [string]$Prerelease
        )
        $modules = Get-Module $Name -ListAvailable
        $found = $false
        foreach ($module in $modules) {
            if ($module.Version -eq $ModuleVersion) {
                if ($PSBoundParameters.Keys -contains 'Prerelease') {
                    if ($module.PrivateData.PSData.Prerelease -eq $Prerelease) {
                        $found = $true
                    }
                } else {
                    $found = $true
                }
            }
        }
        return $found
    }

    if ($PSBoundParameters.Keys -notcontains 'Settings') {
        if (Test-Path .\settings.json) {
            $Settings = Get-Content .\settings.json | ConvertFrom-Json
        } else {
            Throw 'Unable to load settings. Missing .\settings.json or the -Settings parameter.'
        }
    }

    $global:settings = $Settings

    # update nuget, if necessary
    $v = (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue).Version
    if ($null -eq $v -or $v -lt 2.8.5.201) {
        Write-Host 'Updating NuGet...'
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Confirm:$false -Force -Verbose
    }

    if (-not (Test-ModulePresent -Name PowerShellGet -Version 2.2.5)) {
        Install-Module PowerShellGet -RequiredVersion 2.2.5 -Force
        Import-Module PowerShellGet -Version 2.2.5
    }

    # set up the BrazenCloud module
    if (-not (Test-ModulePresent -Name BrazenCloud -Version 0.3.3 -Prerelease beta3)) {
        $reqVersion = if ($PSBoundParameters.Keys -contains 'Prerelease') {
            "$ModuleVersion-$Prerelease"
        } else {
            $ModuleVersion
        }
        $splat = @{
            Name            = 'BrazenCloud'
            RequiredVersion = $reqVersion
            AllowPrerelease = ($PSBoundParameters.Keys -contains 'Prerelease')
            Force           = $true
        }
        Install-Module @splat
    }

    # set up sdk auth
    $wp = $WarningPreference
    $WarningPreference = 'SilentlyContinue'
    Import-Module BrazenCloud | Out-Null
    $WarningPreference = $wp
    $env:BrazenCloudSessionToken = Get-BrazenCloudDaemonToken -aToken $settings.atoken -Domain $settings.host
    $env:BrazenCloudSessionToken
    $env:BrazenCloudDomain = $settings.host.split('/')[-1]
}