# BrazenCloud Beachhead

BrazenCloud Beachhead is a Incident Response deployment tool built for IR teams to quickly and easily deploy their tooling to an environment.

## Prerequisites

- A BrazenCloud account

## Setup

Before an IR engagement, Beachhead will take a small amount of setup:

- All agents to be deployed need to have an action(s) and parameter combination to deploy them.
  - This does not have to be an agent specific action. For instance, you can use the `deploy:msi` action if you are deploying the agent from an MSI.
- An agent will need to be deployed and given an appropriate service account.

## Deployment

Select the beachhead agent and deploy the `beachhead:assessor` job to it.

## Track coverage

When the `beachhead:monitor` job runs, it will create 2 additional indexes: `coverage` and `coverageSummary`.

## Build configuration

## Beachhead Jobs

![](https://lucid.app/publicSegments/view/6b22d320-2d5e-465e-8a6d-2fdc61dbdb0f/image.png)

### Assessor

The `beachhead:assessor` is the action that kicks off Beachhead. It will initiate the following jobs automatically:

- `map:discover`: Periodically run Asset discovery.
- `runway:deploy`: Periodically attempt to autodeploy the BrazenCloud agent.
- `beachhead:deployer`: Periodically scan for endpoints with the BrazenCloud agent that need the other agents installed.
- `beachhead:monitor`: Periodically update the coverage report.

### Deployer

### Monitor

### Alternate Deployer