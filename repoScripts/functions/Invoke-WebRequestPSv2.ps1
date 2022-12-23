Function Invoke-WebRequestPSv2 {
    param (
        [string]$URI,
        [string]$Method = 'Get',
        [hashtable]$Headers,
        [switch]$RawResponse
    )

    #tls1.2
    $p = [Enum]::ToObject([System.Net.SecurityProtocolType], 3072)
    [System.Net.ServicePointManager]::SecurityProtocol = $p

    $WebRequest = [System.Net.WebRequest]::Create($URI)
    $WebRequest.Method = $Method
    foreach ($h in $Headers.Keys) {
        $WebRequest.Headers.Add($h, $Headers[$h])
    }
    $WebRequest.ContentType = "application/json"
    $Response = $WebRequest.GetResponse()
    if ($RawResponse.IsPresent) {
        $Response
    } else {
        $ResponseStream = $Response.GetResponseStream()
        $ReadStream = New-Object System.IO.StreamReader $ResponseStream
        $ReadStream.ReadToEnd()
    }
}