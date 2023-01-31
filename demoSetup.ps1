<#
    This script is designed to guide a user through setting up their tenant for a beachhead demo.
    - Download and install the BrazenCloud module
    - Authenticate with the module
    - Create a group
    - Upload the sample config
    - Provide next steps
#>

$sampleConfigJson = @'
[
    {
        "type": "agentInstall",
        "Name": "FireFox",
        "InstalledName": "Mozilla Firefox*",
        "actions": [
            {
                "name": "deploy:msi",
                "settings": {
                    "MSI URL": "https://brazenclouddlsstaging.z20.web.core.windows.net/Firefox%20Setup%20104.0.1.msi"
                }
            }
        ],
        "installedTag": "firefox:true"
    },
    {
        "type": "agentInstall",
        "Name": "Edge",
        "InstalledName": "Microsoft Edge",
        "actions": [
            {
                "name": "deploy:msi",
                "settings": {
                    "MSI URL": "https://brazenclouddlsstaging.z20.web.core.windows.net/MicrosoftEdgeEnterpriseX64.msi"
                }
            }
        ],
        "installedTag": "edge:true"
    }
]
'@

Write-Host "`n"
Write-Host "This script is designed to deploy a DEMO configuration for BrazenCloud Beachhead. While it can be"
Write-Host "modified to deploy a custom configuration, please do so with care and/or direction from BrazenCloud."
Read-Host "`nBy continuing, you understand that this deploys a DEMO configuration (press any key to continue)"

# this bc module version correlates to current prod API (as of 11/30/2022)
# as soon as staging is deployed, this will be bumped to v0.3.3
$bcModuleVersion = '0.3.3'
$bcPrerelease = 'beta2'

Write-Host 'Configuring prerequisites for the BrazenCloud module...'

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

# Install basic prerequisites for module installation
$v = (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue).Version
if ($null -eq $v -or $v -lt 2.8.5.201) {
    Write-Host '- Updating NuGet...'
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Confirm:$false -Force -Verbose
} else {
    Write-Host '- Nuget already up to date.'
}
if (-not (Test-ModulePresent -Name PowerShellGet -Version 2.2.5)) {
    Write-Host '- Updating PowerShellGet...'
    Install-Module PowerShellGet -RequiredVersion 2.2.5 -Force
    Import-Module PowerShellGet -Version 2.2.5
} else {
    Write-Host '- PowerShellGet already up to date.'
}

# Install necessary BrazenCloud module version
if (-not (Test-ModulePresent -Name BrazenCloud -Version $bcModuleVersion -Prerelease $bcPrerelease)) {
    Write-Host '- Updating BrazenCloud module...'
    $reqVersion = if ($bcPrerelease.Length -gt 0) {
        "$bcModuleVersion-$bcPrerelease"
    } else {
        $ModuleVersion.ToString()
    }
    $splat = @{
        Name            = 'BrazenCloud'
        RequiredVersion = $reqVersion
        AllowPrerelease = ($bcPrerelease.Length -gt 0)
        Force           = $true
    }
    Install-Module @splat
} else {
    Write-Host '- BrazenCloud module already at the correct version.'
}
Import-Module BrazenCloud -Version $bcModuleVersion -WarningAction SilentlyContinue

# Authenticate to BrazenCloud
Write-Host 'Authenticating to BrazenCloud...'
$needsAuth = $true
While ($needsAuth) {
    $email = Read-Host '- Enter your BrazenCloud email '
    $password = Read-Host '- Enter your BrazenCloud password ' -AsSecureString
    
    try {
        Connect-BrazenCloud -Email $email -Password $password -Domain 'portal.brazencloud.com' -TTL 60
        $needsAuth = $false
    } catch {
        Write-Host 'Authentication failed, try again.'
    }
}

# Create group, if necessary
Write-Host 'Creating group...'
$groupName = Read-Host "Enter a group name, if left blank, 'Beachhead Demo' will be used "
if ($groupName.Length -eq 0) {
    $groupName = 'Beachhead Demo'
}

$groups = (Get-BcGroup).Items
$group = $groups | Where-Object { $_.Name -eq $groupName }
if ($null -eq $group) {
    # no group found, create one
    $splat = @{
        LicenseAllocatedRunners     = 0
        Name                        = $groupName
        ParentGroupId               = (Get-BcAuthenticationCurrentUser).HomeContainerId
        LicenseCanAssignSubLicenses = $false
        LicenseSkip                 = $false
    }
    Write-Host "Creating a group with name: '$groupName'"
    $splat
    $bcGroup = New-BcGroup @splat
} elseIf ($group.Count -gt 1) {
    # multiple groups found
    Throw "Unexpected group count. There are already $($group.Count) groups with the given name."
} else {
    # group already exists
    $bcGroup = $group
}

# Upload beachhead config
Write-Host 'Uploading demo config...'
$sampleConfig = $sampleConfigJson | ConvertFrom-Json
try {
    Remove-BcDataStoreQuery2 -GroupId $bcGroup.Id -Query @{query = @{match_all = @{} } } -IndexName 'deployerconfig' | Out-Null
} catch {}
Invoke-BcBulkDatastoreInsert2 -GroupId $bcGroup.Id -Data $sampleConfig -IndexName 'deployerconfig' | Out-Null

# Generate an enrollment token, download runway.exe
Write-Host 'Downloading runway.exe...'
if (-not (Test-Path .\runway.exe)) {
    Invoke-WebRequest -Uri 'https://brazenclouddlsproduction.z13.web.core.windows.net/windows/x64/runway.exe' -OutFile .\runway.exe
}
Write-Host 'Generating enrollment token...'
$et = New-BcEnrollmentSession -GroupId $bcGroup.Id -Expiration (Get-Date).AddDays(30) -Type 4 -IsOneTime:$false

# Output
Write-Host "`n"
Write-Host "### NEXT STEPS ###" -ForegroundColor Cyan
Write-Host "Enrollment token:" -NoNewline
Write-Host " $($et.Token)" -ForegroundColor Green
Write-Host 'Runway.exe:' -NoNewline
Write-Host "'$((Get-Item .\runway.exe).FullName)'" -ForegroundColor Green
Write-Host "`n"
Write-Host "Using runway.exe and the generated token, you can install your first runner with the following command:"
Write-Host "runway.exe -N -S portal.brazencloud.com install -t $($et.Token)" -ForegroundColor Green
Write-Host "`n"
Write-Host "Once you have your first runner deployed, initiate a job using the " -NoNewline
Write-Host "beachhead:assessor" -ForegroundColor Green -NoNewline
Write-Host " action."
Write-Host "`n"
Write-Host "### IMPORTANT ###" -ForegroundColor Cyan
Write-Host "Beachhead has been configured with a default, DEMO configuration. This will deploy Microsoft Edge and Mozilla Firefox."
Write-Host "To support your agents of choice, you will need to write, or request us to write, actions to deploy them."
Write-Host "Action development is not difficult, for a basic overview, please review our docs via the link in the navigation bar."
Write-Host "`n"