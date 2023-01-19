#region dependencies
. .\windows\dependencies\subnets.ps1
. .\windows\dependencies\Get-IpAddressesInRange.ps1
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
. .\windows\dependencies\Parse-Targets.ps1
. .\windows\dependencies\ConvertTo-DiscoverIpRange.ps1
#endregion

$settings = Get-Content .\settings.json | ConvertFrom-Json

#region PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if (-not (Test-Path '..\..\..\pwsh\pwsh.exe')) {
        Throw 'Pwsh missing, rerun assessor'
    }
    Write-Host 'Executing pwsh...'
    ..\..\..\pwsh\pwsh.exe -ExecutionPolicy Bypass -File $($MyInvocation.MyCommand.Definition)
} else {
    #endregion

    Initialize-BcRunnerAuthentication -Settings $settings -WarningAction SilentlyContinue
    #endregion

    #region calculate network with cidr, if none passed
    $route = (Get-NetRoute | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } | Sort-Object RouteMetric)[0]
    $ip = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4

    # find first ip
    $subnet = Get-Ipv4Subnet -IPAddress $ip.IPAddress -PrefixLength $ip.PrefixLength
    $localIPs = Get-IpAddressesInRange -First $subnet.FirstHostIP -Last $subnet.LastHostIP
    if ($settings.Targets.Length -eq 0) {
        # first find network
        $subnet = Get-IPv4Subnet -IPAddress $subnet.CidrID.Split('/')[0] -PrefixLength $subnet.CidrID.Split('/')[1]
        $deployTargets = @(
            @{
                Type    = 'CIDR'
                StartIp = $subnet.FirstHostIP
                EndIp   = $subnet.LastHostIP
            }
        )
    } else {
        $deployTargets = Parse-Targets -Targets $settings.Targets
    }
    Write-Host "Scanning targets: $($settings.Targets)"
    #endregion

    # scan each target
    $x = 0
    foreach ($target in $deployTargets) {
        Write-Host "Target: $($target | ConvertTo-Json)"
        if ($localIPs -contains $target['StartIp']) {
            if ($target['Type'] -eq 'Single') {
                $x++
                ..\..\..\runway.exe -N discover --json "map$x.json" --range $target['StartIp']
            } else {
                foreach ($range in ConvertTo-DiscoverIpRange -Range "$($target['StartIp'])-$($target['EndIp'])") {
                    $x++
                    ..\..\..\runway.exe -N discover --json "map$x.json" --range $range
                }
            }
        } else {
            Write-Host "Target range not on local subnet, unable to scan with asset discovery."
        }
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
}