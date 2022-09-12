$sc = Get-Content $PSScriptRoot\scriptCopies.json | ConvertFrom-Json -AsHashtable

# clean first
$dirs = foreach ($script in $sc.Keys) {
    foreach ($dir in $sc[$script]) { 
        $dir 
    }
}
$dirs | Select-Object -Unique | ForEach-Object {
    #Write-Host "Removing '$PSScriptRoot\..\$_\windows\dependencies'"
    Remove-Item $PSScriptRoot\..\$_\windows\dependencies -Force -Recurse
}

# apply second
foreach ($script in $sc.Keys) {
    foreach ($dir in $sc[$script]) {
        if (-not (Test-Path $PSScriptRoot\..\$dir\windows\dependencies)) {
            New-Item $PSScriptRoot\..\$dir\windows\dependencies -ItemType Directory | Out-Null
        }
        Write-Host "$script -> $dir"
        Copy-Item $PSScriptRoot\functions\$script $PSScriptRoot\..\$dir\windows\dependencies\$script -Force
    }
}