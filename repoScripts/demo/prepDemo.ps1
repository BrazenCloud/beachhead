param (
    [Parameter(Mandatory)]
    [string]$GroupName
)

$agentInstalls = Get-Content $PSScriptRoot\agentInstalls.json | ConvertFrom-Json

if (-not (Get-BcAuthenticationCurrentUser)) {
    Throw 'Connect to BrazenCloud using Connect-BrazenCloud.'
}

$group = (Get-BcGroup).Items | Where-Object { $_.Name -eq $GroupName }

if (-not ($null -ne $group -and $group.Count -eq 1)) {
    Throw 'Group Name does not match any group.'
}

. $PSScriptRoot\..\functions\Invoke-BcBulkDatastoreInsert2.ps1
. $PSScriptRoot\..\functions\Remove-BcDatastoreQuery2.ps1

try {
    Remove-BcDatastoreQuery2 -IndexName 'deployerconfig' -GroupId $group.Id -Query @{query = @{match_all = @{} } }
} catch {}

Invoke-BcBulkDatastoreInsert2 -IndexName 'deployerconfig' -GroupId $group.Id -Data $agentInstalls