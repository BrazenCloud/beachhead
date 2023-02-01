Function Tee-BcLog {
    [cmdletbinding()]
    param (
        [ValidateSet('Info', 'Error')]
        [string]$Level,
        [string]$Message,
        [string]$JobName,
        [string]$Group,
        [switch]$Complete
    )
    $timestamp = (Get-Date -Format 'o')
    $logHt = [ordered]@{
        timeStamp = $timestamp
        level     = $Level
        job       = $JobName
        message   = $Message
    }
    if ($Complete.IsPresent) {
        $logHt['completed'] = $true
    }
    Invoke-BcBulkDataStoreInsert -GroupId $Group -IndexName 'deployerlogs' -Data ($logHt | ForEach-Object { ConvertTo-Json $_ -Compress }) | Out-Null
    Write-Host "$timestamp [$Level] $Message"
}