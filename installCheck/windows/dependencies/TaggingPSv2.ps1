Function New-BcSetPSv2 {
    param (
        
    )
    $method = 'Post'
    $path = "/api/v2/sets"
    $resp = Invoke-BcApi -Method $method -Path $path
    Get-JsonValuePSv2 -Json $resp -Property 'Id'
}

Function Add-BcSetToSetPSv2 {
    param (
        [string]$TargetSetId,
        [string[]]$ObjectIds
    )
    $method = 'Put'
    $path = "/api/v2/sets/$TargetSetId/members"
    $body = '["' + ($ObjectIds -join '","') + '"]'
    Invoke-BcApi -Method $method -Path $path -Body $body
}

Function Add-BcTagPSv2 {
    param (
        [string]$SetId,
        [string[]]$Tags
    )
    $method = 'Put'
    $path = "/api/v2/tags"
    $body = '{"setId":"' + $SetId + '","tags":["' + ($Tags -join '","') + '"]}'
    Invoke-BcApi -Method $method -Path $path -Body $body
}

Function Invoke-BcApi {
    param (
        [string]$Method = 'Get',
        [string]$Path,
        [string]$Body
    )

    if ($Body.Length -gt 0) {
        Invoke-WebRequestPSv2 -Method $method -Uri "https://$($env:BrazenCloudDomain)$Path" -Body $Body -Headers @{
            Authorization = "Session $($env:BrazenCloudSessionToken)"
        }
    } else {
        Invoke-WebRequestPSv2 -Method $method -Uri "https://$($env:BrazenCloudDomain)$Path" -Headers @{
            Authorization = "Session $($env:BrazenCloudSessionToken)"
        }
    }
}