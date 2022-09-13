#region Prep
# load settings.json
$settings = Get-Content .\settings.json | ConvertFrom-Json
$settings

# function to auth as the runner
. .\windows\dependencies\Get-BrazenCloudDaemonToken.ps1

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

#region apply tag
. .\windows\dependencies\Get-InstalledSoftware.ps1

$sw = Get-InstalledSoftware | Where-Object { $_.Name -like $settings.Name }
if ($null -ne $sw) {
    $set = New-BcSet
    Add-BcSetToSet -TargetSetId $set -ObjectIds $settings.prodigal_object_id
    Add-BcTag -SetId $set -Tags $settings.'Tag if installed'
}

#endregion