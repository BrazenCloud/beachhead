param (
    [string]$UtilityPath,
    [string]$Server = 'portal.brazencloud.com'
)

if ($PSBoundParameters.Keys -notcontains 'UtilityPath') {
    if (Test-Path (Get-Item 'C:\Program Files\Runway\*\runway.exe')[0].FullName) {
        $UtilityPath = (Get-Item 'C:\Program Files\Runway\*\runway.exe')[0].FullName
    } else {
        Throw 'No utility path could be found'
    }
}

& $UtilityPath -N -S $Server who

$manifests = Get-ChildItem $PSScriptRoot\..\ -Filter manifest.txt -Recurse

foreach ($manifest in $manifests) {
    $namespace = "beachhead:$($manifest.Directory.Name)"

    Write-Host "----------------------------------------------"
    Write-Host "Publishing: '$namespace'..."

    & $UtilityPath -q -N -S $Server build -i $($manifest.FullName) -o "$($namespace.Replace(':','-')).apt" -p $namespace
}

Get-ChildItem *.apt | ForEach-Object { Remove-Item $_.FullName -Force }
Get-Item .\logs | Remove-Item -Force -Recurse