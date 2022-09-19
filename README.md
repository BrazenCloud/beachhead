# BrazenCloud Beachhead

BrazenCloud Beachhead is a Incident Response deployment tool built for IR teams to quickly and easily deploy their tooling to an environment.

In order to use BrazenCloud Beachhead, you need:

- A BrazenCloud account
- Playbooks to deploy your agents
- A customer specific group

## Process

When an IR engagement is started, here are the step to utilize BrazenCloud Beachhead:

1. Create a new group
2. Upload the agent installation configs
3. Install a BrazenCloud agent in the customer's network and give it an appropriate service account
4. Run the `beachhead:assessor` action on the initial agent
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

Each agent that you need deployed via BrazenCloud Beachhead needs to have a configuration. Here is an example that uses Firefox:

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

When the `beachhead:monitor` job runs, it will create 2 additional indexes: `coverage` and `coverageSummary`.

For a high level view of how the deployment is going, refer to the `coverageSummary` index.

For specific coverage information for each discovered asset, refer to the `coverage` index.

## Beachhead Jobs

For a visual representation of how Beachhead works:

![](https://lucid.app/publicSegments/view/6b22d320-2d5e-465e-8a6d-2fdc61dbdb0f/image.png)

### Assessor

The `beachhead:assessor` action kicks off Beachhead. It will initiate the following jobs automatically:

- `map:discover`: Periodically run Asset discovery.
- `runway:deploy`: Periodically attempt to autodeploy the BrazenCloud agent.
- `beachhead:deployer`: Periodically scan for endpoints with the BrazenCloud agent that need the other agents installed.
- `beachhead:monitor`: Periodically update the coverage report.

### Deployer

The `beachhead:deployer` action will run periodically at the interval specified by `beachhead:assessor` and for each agent to be installed, it will find the assets that do not have it installed and create a job to deploy it to them.

### Monitor

The `beachhead:monitor` action will run periodically at the interval specified by `beachhead:assessor` and update the coverage reports.

### Alternate Deployer

**This has not yet been implemented**

The `beachhead:alternateDeployer` action will run periodically at the interval specified by `beachhead:assessor` and for any assets that do not have the BrazenCloud agent, it will attempt to deploy via alternate methods. Specifically Remote PowerShell or WMI.