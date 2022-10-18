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
        Copy-Item $PSScriptRoot\functions\$script $PSScriptRoot\..\$dir\windows\dependencies\$script -Force
    }
}

# update script dependencies third
$regex = '^\#region dependencies(\r\n|\n)(\. \.\\.*(\r\n|\n))*\#endregion'
foreach ($dir in (Get-ChildItem $PSScriptRoot\..\ -Directory)) {
    Write-Host $dir.Name
    $scriptPath = "$($Dir.FullName)\windows\script.ps1"
    if (Test-Path $scriptPath) {
        $content = Get-Content $scriptPath -Raw
        if ($content -match $regex) {
            $depends = $sc.Keys | Where-Object { $sc[$_] -contains $dir.Name }
            $str = foreach ($d in $depends) {
                ". .\windows\dependencies\$d"
            }
            "#region dependencies`n$($str -join "`n")`n#endregion"
            $content = $content -replace $regex, "#region dependencies`n$($str -join "`n")`n#endregion"
            $content.Trim() | Out-File $scriptPath -Encoding utf8 -NoNewline
        } else {
            Write-Host 'not match regex'
        }
    }
}