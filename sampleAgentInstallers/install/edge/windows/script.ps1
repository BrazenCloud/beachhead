$settings = Get-Content .\settings.json | ConvertFrom-Json

$uri = 'https://brazenclouddlsstaging.z20.web.core.windows.net/MicrosoftEdgeEnterpriseX64.msi'


Write-Host 'Downloading MSI...'
Invoke-WebRequest -Uri $uri -UseBasicParsing -OutFile .\installer.msi

Write-Host 'Starting install...'
Start-Process msiexec -ArgumentList "/i installer.msi /qn /norestart /log .\results\msi.log" -WorkingDirectory .\ -Wait