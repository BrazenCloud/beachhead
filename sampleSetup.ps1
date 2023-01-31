<#
    This script is provided as a sample to prepare your environment to run BrazenCloud Deployer.

    If you already have v0.3.3+ of the BrazenCloud module installed, you can skip the module installation.

    Please refer to the README.md for a full description.
#>

# Install the required version of the BrazenCloud module
# When v0.3.3 is released, that will have full support without the cmdlet names ending in 2
# This should install v0.3.3-beta1
Install-Module BrazenCloud -AllowPrerelease
Import-Module BrazenCloud -RequiredVersion 0.3.3

# Authenticate
Connect-BrazenCloud

# Create a new group
$splat = @{
    LicenseAllocatedRunners     = 0 # number of licenses to assign
    Name                        = 'Deployer Demo'
    ParentGroupId               = (Get-BcAuthenticationCurrentUser).HomeContainerId # this example uses the user's root group ID
    LicenseCanAssignSubLicenses = $false
    LicenseSkip                 = $false # if true, licenses will not be managed at this tenant, if it is a tenant
}
$group = New-BcGroup @splat

# Upload the sample config
$sampleConfig = Get-Content $PSScriptRoot\sampleConfig.json | ConvertFrom-Json
Invoke-BcBulkDatastoreInsert2 -GroupId $group -Data $sampleConfig -IndexName 'deployerconfig'