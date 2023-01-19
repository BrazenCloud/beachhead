param (
    [string]$UtilityPath,
    [string]$Server = 'portal.brazencloud.com',
    [switch]$SampleActions
)

# Find utility, if not passed
if ($PSBoundParameters.Keys -notcontains 'UtilityPath') {
    if (Test-Path (Get-Item 'C:\Program Files\Runway\*\runway.exe')[0].FullName) {
        $UtilityPath = (Get-Item 'C:\Program Files\Runway\*\runway.exe')[0].FullName
    } else {
        Throw 'No utility path could be found'
    }
}

# Show who is logged in
& $UtilityPath -N -S $Server who

# Load manifests
if ($SampleActions.IsPresent) {
    $manifests = Get-ChildItem $PSScriptRoot\..\sampleAgentInstallers -Filter manifest.txt -Recurse
    $actionPrefix = 'install'
} else {
    $manifests = Get-ChildItem $PSScriptRoot\..\ -Filter manifest.txt -Recurse | Where-Object { $_.Directory.Parent.Parent.Name -ne 'sampleAgentInstallers' }
    $actionPrefix = 'beachhead'
}

foreach ($manifest in $manifests) {
    $namespace = "$actionPrefix`:$($manifest.Directory.Name)"

    Write-Host "----------------------------------------------"
    Write-Host "Publishing: '$namespace'..."

    & $UtilityPath -q -N -S $Server build -i $($manifest.FullName) -o "$($namespace.Replace(':','-')).apt" -p $namespace --PUBLIC
}

Get-ChildItem *.apt | ForEach-Object { Remove-Item $_.FullName -Force }
Get-Item .\logs | Remove-Item -Force -Recurse