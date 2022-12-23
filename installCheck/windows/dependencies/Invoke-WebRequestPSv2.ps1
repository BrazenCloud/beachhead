Function Invoke-WebRequestPSv2 {
    param (
        [string]$URI,
        [string]$Method = 'Get',
        [hashtable]$Headers,
        [switch]$RawResponse,
        [string]$Body
    )

    #tls1.2
    $p = [Enum]::ToObject([System.Net.SecurityProtocolType], 3072)
    [System.Net.ServicePointManager]::SecurityProtocol = $p

    # Create the webrequest
    $WebRequest = [System.Net.WebRequest]::Create($URI)
    # Set Method and content type
    $WebRequest.Method = $Method
    $WebRequest.ContentType = "application/json"
    # Add headers
    foreach ($h in $Headers.Keys) {
        $WebRequest.Headers.Add($h, $Headers[$h])
    }

    # add body, if exists
    if ($Body.Length -gt 0) {
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)

        $WebRequest.ContentLength = $bodyBytes.Length

        $rstream = $WebRequest.GetRequestStream()
        $rstream.Write($bodyBytes, 0, $bodyBytes.Length)
        $rstream.Close()
    } else {
        $WebRequest.ContentLength = 0
    }

    $Response = $WebRequest.GetResponse()
    if ($RawResponse.IsPresent) {
        $Response
    } else {
        $ResponseStream = $Response.GetResponseStream()
        $ReadStream = New-Object System.IO.StreamReader $ResponseStream
        $ReadStream.ReadToEnd()
    }
}