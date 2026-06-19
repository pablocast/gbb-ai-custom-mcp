# <img src="docs/img/foundry-mcp-setup/ai-foundry.png" height="32" alt="Azure AI Foundry" />  Foundry -> Entra-Protected FastMCP Gateway

This repo deploys a custom MCP gateway to Azure Container Apps and secures it with Microsoft Entra ID for Foundry agent access.

## Architecture

1. Azure AI Foundry account and project are provisioned by Bicep.
2. A custom MCP server (Python FastMCP) runs in Azure Container Apps.
3. Gateway endpoints require a valid Entra bearer token.
4. Foundry project managed identity is granted an app role on the gateway enterprise app.
5. Foundry MCP connection calls the gateway endpoint with audience-scoped tokens.

## Current implementation

- MCP server: Python FastMCP in `gateway/src/server.py`
- Transport path: `/mcp` (SSE transport)
- Health path: `/healthz`
- Auth checks:
  - issuer matches tenant
  - audience matches configured gateway audience (plus safe compatibility variants)
  - optional caller allow-list via `ALLOWED_CLIENT_IDS`

## MCP tools

The FastMCP server exposes:

1. `get_cities(country)`
2. `get_weather(city)`

## Repo layout

- `infra/main.bicep`: Azure resources (ACA, ACR, Log Analytics, Foundry account/project/model deployment).
- `infra/main.parameters.json`: azd parameter mapping.
- `azure.yaml`: azd service + infra config.
- `gateway/Dockerfile`: container build (Python).
- `gateway/requirements.txt`: Python dependencies.
- `gateway/src/server.py`: FastMCP server + Entra middleware.
- `scripts/00-set-env.example.sh`: environment template.
- `scripts/01-create-entra-app.sh`: create/update gateway app registration and service principal.
- `scripts/02-assign-foundry-mi-app-role.sh`: assign app role to Foundry project managed identity.

## Prerequisites

1. Azure CLI logged in to target subscription.
2. Azure Developer CLI (`azd`).
3. Docker.
4. Permission to manage Entra app registrations and app role assignments.

## Deployment flow

### 1) Prepare environment

```bash
cp scripts/00-set-env.example.sh .env.sh
# edit .env.sh with real values
source .env.sh
```

### 2) Create/update gateway Entra app

```bash
bash scripts/01-create-entra-app.sh
```

Copy printed values into azd env:

```bash
azd env set GATEWAY_APP_ID "<app-id-guid>"
azd env set GATEWAY_APP_ID_URI "api://<app-id-guid>"
```

### 3) Deploy infrastructure and gateway

```bash
azd up
```

### 4) Assign Foundry project MI to gateway app role

```bash
source .env.sh
bash scripts/02-assign-foundry-mi-app-role.sh
```

## Endpoints

After deployment, get the URL from azd env:

```bash
azd env get-values | grep CONTAINER_APP_URL
```

Then use:

- MCP endpoint: `<CONTAINER_APP_URL>/mcp`
- Health endpoint: `<CONTAINER_APP_URL>/healthz`

## Quick verification (Foundry UI)

### 1) Create or edit the MCP tool connection

In Foundry, go to Tools and create (or edit) a remote MCP tool with:

1. Remote MCP server endpoint: `https://<your-container-app-fqdn>/mcp`
2. Authentication: `Microsoft Entra`
3. Type: `Project Managed Identity`
4. Audience: `api://<gateway-app-id>`

Expected result:

1. Tool connection saves successfully.
2. Foundry can enumerate tools from the endpoint.

![Setup MCP connection](docs/images/foundry-mcp-setup/setup_connection.png)

### 2) Use the tool in an agent

1. Open the tool page and select `Use in an agent`.
2. Choose an existing agent (or create one).
3. Confirm the tool appears in the agent tool list.

Expected result:

1. The tool is listed under agent tools.
2. No auth or endpoint errors in the tool panel.

![Use tool in agent](docs/images/foundry-mcp-setup/configure_agent.png)

### 3) Call the agent in Playground

In the agent Playground, send a prompt that triggers the tool, for example:

1. `weather in seattle`
2. `get weather for lisbon`

Expected result:

1. Trace shows tool invocation (for example `mcp_list_tools` and weather tool call).
2. Agent response returns weather data from the MCP server.

![Call the agent in Playground](docs/images/foundry-mcp-setup/using_agent.png)

## Troubleshooting

1. `401 unexpected aud claim value`
	- Ensure Foundry connection audience equals `GATEWAY_APP_ID_URI`.

2. `resource tagged with azd-service-name not found`
	- Run `azd provision` then `azd deploy` to update tags.

3. `soft-deleted resource blocks deployment`
	- Purge the soft-deleted resource (for example, Foundry account) and rerun `azd up`.

4. MCP enumeration timeout or 404
	- Confirm latest image is active on Container App.
	- Re-run `azd deploy` and verify endpoint path is `/mcp`.
