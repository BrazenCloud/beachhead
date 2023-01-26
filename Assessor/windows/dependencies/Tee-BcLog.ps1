Function Tee-BcLog {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('Info', 'Error')]
        [string]$Level,
        [Parameter(Mandatory)]
        [string]$Message,
        [Parameter(Mandatory)]
        [string]$JobName,
        [Parameter(Mandatory)]
        [string]$Group
    )
    $timestamp = (Get-Date -Format 'o')
    $logHt = [ordered]@{
        TimeStamp = $timestamp
        Level     = $Level
        Job       = $JobName
        Message   = $Message
    }
    Invoke-BcBulkDataStoreInsert -GroupId $Group -IndexName 'beachheadlogs' -Data ($logHt | ForEach-Object { ConvertTo-Json $_ -Compress })
    Write-Host "$timestamp [$Level] $Message"
}