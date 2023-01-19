$settings = Get-Content .\settings.json | ConvertFrom-Json

$uri = 'https://brazenclouddlsstaging.z20.web.core.windows.net/Firefox%20Setup%20104.0.1.msi'


Write-Host 'Downloading MSI...'
Invoke-WebRequest -Uri $uri -UseBasicParsing -OutFile .\installer.msi

Write-Host 'Starting install...'
Start-Process msiexec -ArgumentList "/i installer.msi /qn /norestart /log .\results\msi.log" -WorkingDirectory .\ -Wait