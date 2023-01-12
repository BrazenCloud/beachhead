#region dependencies
. .\windows\dependencies\TaggingPSv2.ps1
. .\windows\dependencies\Initialize-BcRunnerAuthenticationPSv2.ps1
. .\windows\dependencies\Invoke-WebRequestPSv2.ps1
. .\windows\dependencies\Get-JsonValuePSv2.ps1
. .\windows\dependencies\Get-InstalledSoftware.ps1
#endregion

$settings = Get-Content .\settings.json
$atoken = Get-JsonValuePSv2 -Json $settings -Property 'aToken'
$bchost = Get-JsonValuePSv2 -Json $settings -Property 'host'
$pobjId = Get-JsonValuePSv2 -Json $settings -Property 'prodigal_object_id'
$sname = Get-JsonValuePSv2 -Json $settings -Property 'Name'
$tag = Get-JsonValuePSv2 -Json $settings -Property 'Tag if installed'

Write-Host "Checking for the installation of '$sname'"
Write-Host "Will apply tag: '$tag' if found."

Initialize-BcRunnerAuthenticationPSv2 -aToken $atoken -Domain $bchost.split('/')[-1]
#endregion

#region apply tag
$sw = Get-InstalledSoftware | Where-Object { $_.Name -like $sname }
if ($null -ne $sw) {
    Write-Host "'$sname' found, adding tag..."
    $set = New-BcSetPSv2
    Add-BcSetToSetPSv2 -TargetSetId $set -ObjectIds $pobjId
    Add-BcTagPSv2 -SetId $set -Tags $tag
} else {
    Write-Host "'$sname' not found."
}

#endregion