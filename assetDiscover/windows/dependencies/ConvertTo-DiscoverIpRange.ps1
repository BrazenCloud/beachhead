# expects IP-IP
Function ConvertTo-DiscoverIpRange {
    param (
        [string]$Range
    )
    #Write-Host "Range: $Range"
    $ips = $range.Split('-')
    #Write-Host "First ip: $($ips[0])"
    #Write-Host "Last ip: $($ips[1])"
    $firstIpSplit = $ips[0].Split('.')
    $lastIpSplit = $ips[1].Split('.')
    if ($firstIpSplit[0] -lt $lastIpSplit[0]) {
        ConvertTo-DiscoverIpRange -Range "$($firstIpSplit -join '.')-$($firstIpSplit[0]).255.255.255"
        for ([int]$x = ([int]$firstIpSplit[0] + 1); $x -lt [int]$lastIpSplit[0]; $x++) {
            ConvertTo-DiscoverIpRange -Range "$x.0.0.0-$x.255.255.255"
        }
        ConvertTo-DiscoverIpRange -Range "$x.0.0.0-$($lastIpSplit -join '.')"
    } elseif ($firstIpSplit[1] -lt $lastIpSplit[1]) {
        #10.0.0.1-10.1.1.1
        ConvertTo-DiscoverIpRange -Range "$($firstIpSplit -join '.')-$($firstIpSplit[0..1] -join '.').255.255"
        for ([int]$x = ([int]$firstIpSplit[1] + 1); $x -lt [int]$lastIpSplit[1]; $x++) {
            ConvertTo-DiscoverIpRange -Range "$($firstIpSplit[0]).$x.0.0-$($firstIpSplit[0]).$x.255.255"
        }
        ConvertTo-DiscoverIpRange -Range "$($firstIpSplit[0]).$x.0.0-$($lastIpSplit -join '.')"
    } elseif ($firstIpSplit[2] -lt $lastIpSplit[2]) {
        ConvertTo-DiscoverIpRange -Range "$($firstIpSplit -join '.')-$($firstIpSplit[0..2] -join '.').255"
        for ([int]$x = ([int]$firstIpSplit[2] + 1); $x -lt [int]$($lastIpSplit[2]); $x++) {
            ConvertTo-DiscoverIpRange -Range "$($firstIpSplit[0..1] -join '.').$x.0-$($firstIpSplit[0..1] -join '.').$x.255"
        }
        ConvertTo-DiscoverIpRange -Range "$($firstIpSplit[0..1] -join '.').$x.0-$($lastIpSplit -join '.')"
    } elseif ($firstIpSplit[3] -ne $lastIpSplit[3]) {
        #Write-Host "output: $($firstIpSplit -join '.')-$($lastIpSplit[3])"
        "$($firstIpSplit -join '.')-$($lastIpSplit[3])"
    }#>
}