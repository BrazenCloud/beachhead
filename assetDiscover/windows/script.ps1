#region dependencies
. .\windows\dependencies\subnets.ps1
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
#endregion

$settings = Get-Content .\settings.json | ConvertFrom-Json

#region PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if ($settings.'Use PowerShell 7'.ToString() -eq 'true') {
        pwsh.exe -ExecutionPolicy Bypass -File $($MyInvocation.MyCommand.Definition)
    }
}
#endregion

Initialize-BcRunnerAuthentication -Settings $settings -WarningAction SilentlyContinue
#endregion

#region calculate network with cidr, if none passed
if ($settings.Targets.Length -eq 0) {
    # first find network
    $route = (Get-NetRoute | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } | Sort-Object RouteMetric)[0]
    $ip = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4

    # find first ip
    $targets = (Get-Ipv4Subnet -IPAddress $ip.IPAddress -PrefixLength $ip.PrefixLength).CidrID
    
} else {
    $targets = $settings.Targets
}
Write-Host "Scanning targets: $targets"
#endregion

# scan each target
$x = 0
foreach ($target in $targets.Split(',')) {
    $x++
    ..\..\..\runway.exe -N discover --json "map$x.json" --range $target
}

# identify the group to upload to
$groupId = if ($settings.'Group ID'.length -gt 0) {
    $settings.'Group ID'
} else {
    (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]
}

# upload the maps
foreach ($mapFile in (Get-Item map*.json)) {
    $map = Get-Content $mapFile.FullName | ConvertFrom-Json
    $htArr = foreach ($obj in $map.EndpointData) {
        $ht = @{}
        foreach ($prop in $obj.PSObject.Properties.Name) {
            $ht[$prop] = $obj.$prop
        }
        $ht
    }

    Invoke-BcMapAsset -EndpointData ([BrazenCloudSdk.PowerShell.Models.IAssetMapEndpoint[]]$htArr) -GroupId $groupId
}