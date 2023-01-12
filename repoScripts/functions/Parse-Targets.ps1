Function Parse-Targets {
    [cmdletbinding()]
    param (
        [string]$Targets
    )
    foreach ($target in $Targets.Split(',').Trim()) {
        switch -Regex ($target) {
            # IP Range: IP-IP
            '^(\d{1,3}\.){3}\d{1,3}\-(\d{1,3}\.){3}\d{1,3}$' {
                Write-Host "Target '$target' is a range"
                @{
                    Type    = 'Range'
                    StartIp = $target.Split('-')[0]
                    EndIp   = $target.Split('-')[1]
                }
            }
            # CIDR: IP/Subnet
            '^(\d{1,3}\.){3}\d{1,3}\/\d{1,2}$' {
                Write-Host "Target '$target' is a CIDR"
                $subnet = Get-IPv4Subnet -IPAddress $target.Split('/')[0] -PrefixLength $target.Split('/')[1]
                @{
                    Type    = 'CIDR'
                    StartIp = $subnet.FirstHostIP
                    EndIp   = $subnet.LastHostIP
                }
            }
            # Individual IP
            '^(\d{1,3}\.){3}\d{1,3}$' {
                Write-Host "Target '$target' is an individual IP"
                @{
                    Type    = 'Single'
                    StartIp = $target
                    EndIp   = $null
                }
            }
            default {
                Write-Host "Target is not a valid IP range, CIDR, or address. Attempting DNS lookup."
                try {
                    $dnsRes = Resolve-DnsName $target -ErrorAction SilentlyContinue
                    Write-Host "Resolved '$target' to '$($dnsRes.IPAddress)'"
                    @{
                        Type    = 'Single'
                        StartIp = $dnsRes.IPAddress
                        EndIp   = $null
                    }
                } catch {
                    Write-Host "Invalid target: '$target'"
                }
            }
        }
    }
}