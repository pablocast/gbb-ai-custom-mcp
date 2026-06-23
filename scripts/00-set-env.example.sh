#!/usr/bin/env bash
set -euo pipefail

# Subscription + region
export AZ_SUBSCRIPTION_ID="<subscription-id>"
export AZ_LOCATION="eastus"
export AZ_RESOURCE_GROUP="rg-gbb-mcp"

# Naming
export NAME_PREFIX="gbbmcp"

# Entra / gateway API app registration
export ENTRA_TENANT_ID="<tenant-id>"
export GATEWAY_APP_DISPLAY_NAME="gbb-customer-mcp-gateway"
# Usually set to api://<appId-guid> by script 01.
export GATEWAY_APP_ID="<appId-guid>"
export GATEWAY_APP_ID_URI="api://<appId-guid>"

# Optional app role name enforced by your gateway logic
export GATEWAY_REQUIRED_APP_ROLE="Mcp.AppInvoke"

# Foundry identity client id allow-list (comma-separated), optional
export ALLOWED_CLIENT_IDS=""

# ACR + ACA names (override if desired)
export ACR_NAME="${NAME_PREFIX}acr"
export ACA_ENV_NAME="${NAME_PREFIX}-aca-env"
export ACA_APP_NAME="${NAME_PREFIX}-gateway"
export IMAGE_REPO="customer-mcp-gateway"
export IMAGE_TAG="v1"

# Foundry project (for script 02)
export FOUNDRY_PROJECT_RESOURCE_ID="/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project>"
export FOUNDRY_CONNECTION_NAME="customer-mcp-gateway"
