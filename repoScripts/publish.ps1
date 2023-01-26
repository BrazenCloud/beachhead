param (
    [string]$UtilityPath,
    [string]$Server = 'portal.brazencloud.com',
    [switch]$SampleActions,
    [string]$BrazenCloudModuleVersion = '0.3.3-beta5',
    [System.IO.DirectoryInfo]$PwshCachePath = 'C:\tmp',
    [string]$PwshDownloadUri = 'https://github.com/PowerShell/PowerShell/releases/download/v7.3.1/PowerShell-7.3.1-win-x64.zip',
    [switch]$UpdateModule
)

Function Test-ModulePresent {
    [CmdletBinding()]
    param (
        [string]$Name,
        [version]$Version,
        [string]$Prerelease
    )
    $modules = Get-Module $Name -ListAvailable
    foreach ($module in $modules) {
        if ($module.Version -eq $Version) {
            if ($PSBoundParameters.Keys -contains 'Prerelease') {
                if ($module.PrivateData.PSData.Prerelease -eq $Prerelease) {
                    return $true
                }
            } else {
                return $true
            }
        }
    }
    return $false
}

# Check for existing zip in zip cache path
if (-not (Test-Path $PwshCachePath\pwsh.zip)) {
    Write-Host 'Downloading pwsh...'
    Invoke-WebRequest -Uri $PwshDownloadUri -OutFile $PwshCachePath\pwsh.zip
}

# Add BrazenCloud module into the zip\modules directory, rezip
if ((-not (Test-Path $PwshCachePath\pwsh.7z)) -or ($UpdateModule.IsPresent)) {
    Write-Host 'Inserting the BrazenCloud Module...'
    if (Test-Path $PwshCachePath\pwsh.7z) {
        Remove-Item $PwshCachePath\pwsh.7z -Force -Confirm:$false
    }
    if (Test-Path $PwshCachePath\pwsh) {
        Remove-Item $PwshCachePath\pwsh -Force -Confirm:$false -Recurse
    }
    Expand-Archive -Path "$PwshCachePath\pwsh.zip" -DestinationPath "$PwshCachePath\pwsh"
    if (-not (Test-ModulePresent -Name BrazenCloud -Version 0.3.3 -Prerelease beta5)) {
        Install-Module -Name BrazenCloud -MinimumVersion 0.3.3 -AllowPrerelease
    }

    if ($BrazenCloudModuleVersion -like '*-*') {
        $whereSb = { $_.Version -eq [version]$BrazenCloudModuleVersion.Split('-')[0] -and $_.PrivateData.PSData.Prerelease -eq $BrazenCloudModuleVersion.Split('-')[1] }
    } else {
        $whereSb = { $_.Version -eq $BrazenCloudModuleVersion }
    }
    $bcModule = Get-Module BrazenCloud | Where-Object $whereSb
    $bcModulePath = Split-Path $bcModule.Path
    if (-not (Test-Path $PwshCachePath\pwsh\Modules\BrazenCloud)) {
        New-Item $PwshCachePath\pwsh\Modules\BrazenCloud -ItemType Directory
    }
    Copy-Item $bcModulePath -Destination "$PwshCachePath\pwsh\Modules\BrazenCloud" -Recurse

    & $PSScriptRoot\..\assessor\windows\7z\7za.exe a "$PwshCachePath\pwsh.7z" "$PwshCachePath\pwsh"

    Remove-Item "$PwshCachePath\pwsh" -Recurse -Force
}

if (-not (Test-Path $PSScriptRoot\..\assessor\windows\pwsh.7z) -or $UpdateModule.IsPresent) {
    if (Test-Path $PSScriptRoot\..\assessor\windows\pwsh.7z) {
        Remove-Item $PSScriptRoot\..\assessor\windows\pwsh.7z -Force -Confirm:$false
    }
    Write-Host 'Copying pwsh.7z to the action...'
    Copy-Item $PwshCachePath\pwsh.7z -Destination $PSScriptRoot\..\assessor\windows\pwsh.7z
}

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