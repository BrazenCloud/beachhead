#$settings = Get-Content .\settings.json | ConvertFrom-Json

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$uri = 'https://brazenclouddlsstaging.z20.web.core.windows.net/MicrosoftEdgeEnterpriseX64.msi'


Write-Host 'Downloading MSI...'
Invoke-WebRequest -Uri $uri -UseBasicParsing -OutFile .\installer.msi

Write-Host 'Starting install...'
Start-Process msiexec -ArgumentList "/i installer.msi /qn /norestart /log .\results\msi.log" -WorkingDirectory .\ -Wait