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
        foreach ($module in $modules) {
            if ($module.Version -eq $Version) {
                if ($PSBoundParameters.Keys -contains 'Prerelease') {
                    if ($module.PrivateData.PSData.Prerelease -eq $Prerelease) {
                        return $true
                    }
                } else {
                    return $true
                }
            }
        }
        return $false
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
        Write-Host 'Updating PowerShellGet...'
        Install-Module PowerShellGet -RequiredVersion 2.2.5 -Force
        Import-Module PowerShellGet -Version 2.2.5
    }

    # set up the BrazenCloud module
    if (-not (Test-ModulePresent -Name BrazenCloud -Version $ModuleVersion -Prerelease $Prerelease)) {
        $reqVersion = if ($Prerelease.Length -gt 0) {
            "$ModuleVersion-$Prerelease"
        } else {
            $ModuleVersion.ToString()
        }
        $splat = @{
            Name            = 'BrazenCloud'
            RequiredVersion = $reqVersion
            AllowPrerelease = ($Prerelease.Length -gt 0)
            Force           = $true
        }
        $splat | ConvertTo-Json
        Install-Module @splat
    }

    # set up sdk auth
    Import-Module BrazenCloud -Version $ModuleVersion -DisableNameChecking -WarningAction SilentlyContinue | Out-Null
    Get-Module BrazenCloud
    $env:BrazenCloudSessionToken = Get-BrazenCloudDaemonToken -aToken $settings.atoken -Domain $settings.host
    $env:BrazenCloudSessionToken
    $env:BrazenCloudDomain = $settings.host.split('/')[-1]
}