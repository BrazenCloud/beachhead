#region dependencies
. .\windows\dependencies\TaggingPSv2.ps1
. .\windows\dependencies\Initialize-BcRunnerAuthenticationPSv2.ps1
. .\windows\dependencies\Invoke-WebRequestPSv2.ps1
. .\windows\dependencies\Get-JsonValuePSv2.ps1
. .\windows\dependencies\Get-InstalledSoftware.ps1
. .\windows\dependencies\Invoke-BcDataStoreBulkInsertPSv2.ps1
. .\windows\dependencies\Remove-BcDataStoreEntryPSv2.ps1
. .\windows\dependencies\Get-BcEaGroupPSv2.ps1
. .\windows\dependencies\Invoke-BcQueryDataStorePSv2.ps1
#endregion

$settings = Get-Content .\settings.json
$atoken = Get-JsonValuePSv2 -Json $settings -Property 'aToken'
$bchost = Get-JsonValuePSv2 -Json $settings -Property 'host'
$pobjId = Get-JsonValuePSv2 -Json $settings -Property 'prodigal_object_id'
$sname = Get-JsonValuePSv2 -Json $settings -Property 'Search Name'
$aname = Get-JsonValuePSv2 -Json $settings -Property 'Agent Name'
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
    Write-Host "Reporting install failure."
    
    # supporting back to PSv2, of course

    # get local IP
    $ip = ((route print | find " 0.0.0.0").Trim() -split ' +')[3].Trim()
    # get local runner's group
    $group = Get-BcEaGroupPSv2 -EndpointAssetId $pobjId
    # get the entry in beachheadcoverage that matches this runner's IP
    $query = "{\`"query\`":{\`"query_string\`": {\`"query\`": \`"$ip\`",\`"default_field\`": \`"ipAddress\`"}}}"
    $fullEntry = Invoke-BcQueryDataStorePSv2 -Query $query -IndexName 'beachheadcoverage' -GroupId $group
    # pull the entry out of the Elastic JSON
    if ($fullEntry -match '\[(?<entry>[^]]+)\]') {
        $entry = $Matches.entry
        # pull the fail count from the entry
        $searchStr = "$($aname.Replace(' ', ''))FailCount"
        $regex = "`"$searchStr`":(?<count>\d),"
        if ($entry -match $regex) {
            # increment the fail count
            $newCount = ([int]$Matches.Count) + 1
            $entry = $entry -replace $regex, "`"$($aname.Replace(' ', ''))FailCount`":$newCount,"
            # format the entry for reupload
            $entry = $entry -replace '"', '\"'
            # remove the existing entry from Elastic
            $deleteQuery = "{\`"query\`": {\`"match\`": {\`"ipAddress\`": \`"$ip\`"}}}"
            Remove-BcDataStoreEntryPSv2 -GroupId $group -IndexName 'beachheadcoverage' -DeleteQuery $deleteQuery
            # replace it with the new one
            Invoke-BcBulkDataStoreInsertPSv2 -GroupId $group -IndexName 'beachheadcoverage' -Entries $entry
        } else {
            Write-Host "Entry: $entry"
            Throw 'Entry does not match regex.'
        }
    } else {
        Throw 'Unable to update agent failure.'
    }
}

#endregion