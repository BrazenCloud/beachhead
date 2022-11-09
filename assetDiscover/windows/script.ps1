#region dependencies
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
. .\windows\dependencies\subnets.ps1
#endregion

Initialize-BcRunnerAuthentication -Settings (Get-Content .\settings.json | ConvertFrom-Json)
#endregion

#region calculate network with cidr
# first find network
$route = (Get-NetRoute | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } | Sort-Object RouteMetric)[0]
$ip = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4

# find first ip
$subnet = Get-Ipv4Subnet -IPAddress $ip.IPAddress -PrefixLength $ip.PrefixLength

#endregion

..\..\..\runway.exe -N discover --json map.json --range $($subnet.CidrID)
$map = Get-Content .\map.json | ConvertFrom-Json
$htArr = foreach ($obj in $map.EndpointData) {
    $ht = @{}
    foreach ($prop in $obj.PSObject.Properties.Name) {
        $ht[$prop] = $obj.$prop
    }
    $ht
}

$groupId = if ($settings.'Group ID'.length -gt 0) {
    $settings.'Group ID'
} else {
    (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]
}

Invoke-BcMapAsset -EndpointData ([BrazenCloudSdk.PowerShell.Models.IAssetMapEndpoint[]]$htArr) -GroupId $groupId