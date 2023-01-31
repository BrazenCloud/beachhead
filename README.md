# BrazenCloud Deployer

BrazenCloud Deployer is a Incident Response deployment tool built for IR teams to quickly and easily deploy their tooling to an environment.

In order to use BrazenCloud Deployer, you need:

- A BrazenCloud account
- Playbooks to deploy your agents
- A customer specific group

## Process

When an IR engagement is started, here are the step to utilize BrazenCloud Deployer:

1. Create a new group
2. Upload the agent installation configs
3. Install a BrazenCloud agent in the customer's network and give it an appropriate service account
4. Run the `deployer:start` action on the initial agent
5. View the coverage progress in the index

## Agent installation prerequisites

Before an IR engagement, all agents to be deployed (i.e. CarbonBlack) need to have a playbook consisting of actions and parameters that would result in the agent's installation on the endpoint. Typically this is a single action that installs the agent by executing an agent specific script.

If the agent is an MSI, you might consider using our `deploy:msi` action, using parameters to customize the installation. For custom agent deployments using a dedicated action, See our [Action Developer Guide](https://docs.runway.host/runway-documentation/action-developer-guides/overview).

## Creating a group in BrazenCloud

You can use the UI to create a new group by following the instructions in the documentation: [Managing Groups](https://docs.runway.host/runway-documentation/general-concepts/groups/managing-groups).

Or you can use the [PowerShell SDK](https://github.com/brazencloud/powershell) to create the group via a script:

```powershell
$splat = @{
    LicenseAllocatedRunners = 100 # number of licenses to assign
    Name                    = 'Customer 1'
    ParentGroupId           = (Get-BcAuthenticationCurrentUser).HomeContainerId # this example uses the user's root group ID
}
New-BcGroup @splat
```

## Setting the service logon account

When you install the BrazenCloud agent, it installs as a service called 'RunwayRunnerService'. You'll want to change the logon service account to be an account that has privileges to install software on the endpoints in your network. For instance, an Active Directory account that has local administrator rights in your domain.

You can do this via `services.msc`.

## Applying the agent installation config

Each agent that you need deployed via BrazenCloud Deployer needs to have a configuration. Here is an example that uses Firefox:

```json
[
    {
        "type": "agentInstall",
        "Name": "FireFox",
        "InstalledName": "Mozilla Firefox*",
        "actions": [
            {
                "name": "deploy:msi",
                "settings": {
                    "MSI URL": "https://brazenclouddlsstaging.z20.web.core.windows.net/Firefox%20Setup%20104.0.1.msi"
                }
            }
        ],
        "installedTag": "firefox:true"
    }
]
```

- **type**: For agent installation configs, this should always be: `agentInstall`
- **Name**: The name used to track coverage and is displayed in the logs.
- **InstalledName**: The name to search for in the installed applications. Wildcards are support here (`?`,`*`).
- **actions**: An array of actions and their parameters that installs the agent.
  - **name**: The name of the action to use
  - **settings**: An object containing each parameter name with the value to use.
- **installedTag**: The tag to apply to the asset in BrazenCloud when the agent has been installed.

With the config written, it needs to be put into the `beachheadconfig` index in the newly created group. This can be done using the API, most easily using the [PowerShell SDK](https://github.com/brazencloud/powershell) and the included [Invoke-BcBulkDatastoreInsert2](repoScripts/functions/Invoke-BcBulkDatastoreInsert2.ps1) function:

```powershell
# load up the Invoke-BcBulkDatastoreInsert2 function
. ./repoScripts/functions/Invoke-BcBulkDatastoreInsert2.ps1

# Get the data from your json file
$data = Get-Content ./sampleConfig.json | ConvertFrom-Json

# Get the group of the IR group
$groupId = ((Get-BcGroup).Items | ?{$_.Name -eq 'Customer 1'}).Id

# Add the config to the index
Invoke-BcBulkDatastoreInsert2 -Data $data -IndexName 'beachheadconfig' -GroupId $groupId
```

## Tracking coverage

When the `deployer:tracker` job runs, it will create 2 additional indexes: `beachheadcoverage` and `beachheadcoveragesummary`.

For a high level view of how the deployment is going, refer to the `beachheadcoveragesummary` index.

For specific coverage information for each discovered asset, refer to the `beachheadcoverage` index.

## Deployer Jobs

For a visual representation of how Deployer works:

![](https://lucid.app/publicSegments/view/6b22d320-2d5e-465e-8a6d-2fdc61dbdb0f/image.png)

### Assessor

The `deployer:start` action kicks off Deployer. It will initiate the following jobs automatically:

- `deployer:assetDiscover`: Periodically run Asset discovery.
- `deployer:brazenAgent`: Periodically deploy the BrazenCloud agent to discovered endpoints.
- `deployer:orchestrator`: Periodically scan for endpoints with the BrazenCloud agent that need the other agents installed.
- `deployer:tracker`: Periodically update the coverage report.

### Orchestrator

The `deployer:orchestrator` action will run periodically at the interval specified by `deployer:start` and for each agent to be installed, it will find the assets that do not have it installed and create a job to deploy it to them.

### Tracker

The `deployer:tracker` action will run periodically at the interval specified by `deployer:start` and update the coverage reports.

### BrazenAgent

The `deployer:brazenAgent` action runs periodically at the interval specified by `deployer:start` and will scan the group that the job is initiated from, find all discovered endpoints that do not currently have the BrazenCloud agent installed, and attempt to install the agent using the following deployment methods, in order:

1. **autodeploy**: This is a deployment method built into the agent that utilizes the `admin$` share.
2. **PowerShell remoting**: If the autodeploy method fails, PowerShell remoting is attempted
3. **WMI**: If PowerShell remoting fails, WMI commands are attempted.