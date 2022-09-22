Function Get-IpAddressesInRange {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ipaddress]$First,
        [Parameter(Mandatory)]
        [ipaddress]$Last
    )
    $Ip_Adresa_Od = $First.ToString() -split "\."
    $Ip_Adresa_Do = $Last.ToString() -split "\."

    #change endianness
    [array]::Reverse($Ip_Adresa_Od)
    [array]::Reverse($Ip_Adresa_Do)

    #convert octets to integer
    $start = [bitconverter]::ToUInt32([byte[]]$Ip_Adresa_Od, 0)
    $end = [bitconverter]::ToUInt32([byte[]]$Ip_Adresa_Do, 0)

    for ($ip = $start; $ip -lt $end; $ip++) { 
        #convert integer back to byte array
        $get_ip = [bitconverter]::getbytes($ip)

        #change endianness
        [array]::Reverse($get_ip)

        $new_ip = $get_ip -join "."
        [ipaddress]$new_ip
    }
}