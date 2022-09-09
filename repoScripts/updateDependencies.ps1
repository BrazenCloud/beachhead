$sc = Get-Content $PSScriptRoot\scriptCopies.json | ConvertFrom-Json -AsHashtable

# clean first
$dirs = foreach ($script in $sc.Keys) {
    foreach ($dir in $sc[$script]) { 
        $dir 
    }
}
$dirs | Select-Object -Unique | ForEach-Object {
    Remove-Item $PSScriptRoot\..\$_\windows\dependencies -Force -Recurse
}

# apply second
foreach ($script in $sc.Keys) {
    foreach ($dir in $sc[$script]) {
        if (-not (Test-Path $PSScriptRoot\..\$dir\windows\dependencies)) {
            New-Item $PSScriptRoot\..\$dir\windows\dependencies -ItemType Directory | Out-Null
        }
        Write-Host "$script -> $dir"
        Copy-Item $PSScriptRoot\..\$script $PSScriptRoot\..\$dir\windows\dependencies\$script -Force
    }
}