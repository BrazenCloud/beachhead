#region dependencies
. .\windows\dependencies\subnets.ps1
. .\windows\dependencies\Get-IpAddressesInRange.ps1
. .\windows\dependencies\Initialize-BcRunnerAuthentication.ps1
. .\windows\dependencies\Parse-Targets.ps1
. .\windows\dependencies\ConvertTo-DiscoverIpRange.ps1
. .\windows\dependencies\Tee-BcLog.ps1
. .\windows\dependencies\DeployerJobs.ps1
#endregion

#region PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if (-not (Test-Path '..\..\..\pwsh\pwsh.exe')) {
        Throw 'Pwsh missing, rerun deployer:start'
    }
    Write-Host 'Relaunching in PowerShell 7...'
    ..\..\..\pwsh\pwsh.exe -ExecutionPolicy Bypass -File $($MyInvocation.MyCommand.Definition)
} else {
    #endregion
    Write-Host 'Initializing authentication...'
    $settings = Get-Content .\settings.json | ConvertFrom-Json
    Initialize-BcRunnerAuthentication -Settings $settings -WarningAction SilentlyContinue
    $group = (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]
    $logSplat = @{
        Level   = 'Info'
        Group   = $group
        JobName = 'Asset Discover'
    }
    Tee-BcLog @logSplat -Message 'BrazenCloud Asset Discover initialized'
    #endregion

    #region calculate network with cidr, if none passed
    Tee-BcLog @logSplat -Message 'Calculating local network subnet...'
    $ip = powershell.exe -c {
        $route = (Get-NetRoute | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } | Sort-Object RouteMetric)[0]    
        Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4
    }

    # find first IP and CDIR
    $subnet = Get-Ipv4Subnet -IPAddress $ip.IPAddress -PrefixLength $ip.PrefixLength
    Tee-BcLog @logSplat -Message "Subnet: $($subnet.CidrID)"
    $localIPs = Get-IpAddressesInRange -First $subnet.FirstHostIP -Last $subnet.LastHostIP
    if ($settings.Targets.Length -eq 0) {
        # first find network
        Tee-BcLog @logSplat -Message 'No targets passed, defaulting to local subnet.'
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
    #endregion

    # scan each target
    $x = 0
    foreach ($target in $deployTargets) {
        Tee-BcLog @logSplat -Message "Scanning target: $($target | ConvertTo-Json -Compress)"
        if ($localIPs -contains $target['StartIp']) {
            Tee-BcLog @logSplat -Message "Writing target scan to 'map$x.json'..."
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
            Tee-BcLog @logSplat -Message "Target range not on local subnet, unable to scan with asset discovery."
        }
    }

    # identify the group to upload to
    $groupId = if ($settings.'Group ID'.length -gt 0) {
        $settings.'Group ID'
    } else {
        (Get-BcEndpointAsset -EndpointId $settings.prodigal_object_id).Groups[0]
    }
    Tee-BcLog @logSplat -Message "Using group: $groupId as upload target..."

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
        Tee-BcLog @logSplat -Message "Uploading $($mapFile.Name)..."
        Invoke-BcMapAsset -EndpointData ([BrazenCloudSdk.PowerShell.Models.IAssetMapEndpoint[]]$htArr) -GroupId $groupId
    }

    # check if deployer is running, if not, wait and initiate it
    Start-DeployerJob -JobName 'Deployer' -Group $group
}