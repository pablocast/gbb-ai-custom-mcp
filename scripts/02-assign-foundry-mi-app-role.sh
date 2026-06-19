#!/usr/bin/env bash
set -euo pipefail

# Assign the gateway application role to Foundry Project managed identity service principal.
# Requires Graph permissions to manage app role assignments.

required_vars=(
  AZ_SUBSCRIPTION_ID
  FOUNDRY_PROJECT_RESOURCE_ID
  GATEWAY_APP_ID
  GATEWAY_REQUIRED_APP_ROLE
)
for v in "${required_vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "Missing required env var: $v"
    exit 1
  fi
done

az account set --subscription "$AZ_SUBSCRIPTION_ID"

echo "Resolving Foundry project managed identity principal id"
normalized_foundry_project_resource_id="$FOUNDRY_PROJECT_RESOURCE_ID"
if [[ "$normalized_foundry_project_resource_id" != /* ]]; then
  normalized_foundry_project_resource_id="/$normalized_foundry_project_resource_id"
fi

foundry_principal_id="$(MSYS_NO_PATHCONV=1 az resource show \
  --ids "$normalized_foundry_project_resource_id" \
  --api-version 2025-12-01 \
  --query identity.principalId -o tsv 2>/dev/null || true)"

if [[ -z "$foundry_principal_id" ]]; then
  echo "Could not resolve Foundry project managed identity principal id"
  echo "Check FOUNDRY_PROJECT_RESOURCE_ID and API version support in your subscription"
  echo "Current value: $FOUNDRY_PROJECT_RESOURCE_ID"
  exit 1
fi

echo "Resolving gateway service principal and app role id"
gateway_sp_object_id="$(az ad sp show --id "$GATEWAY_APP_ID" --query id -o tsv)"
app_role_id="$(az ad app show --id "$GATEWAY_APP_ID" --query "appRoles[?value=='$GATEWAY_REQUIRED_APP_ROLE'] | [0].id" -o tsv)"

if [[ -z "$gateway_sp_object_id" || -z "$app_role_id" ]]; then
  echo "Could not resolve gateway service principal or app role"
  echo "Check GATEWAY_APP_ID and GATEWAY_REQUIRED_APP_ROLE"
  exit 1
fi

echo "Assigning app role '$GATEWAY_REQUIRED_APP_ROLE' to Foundry managed identity"
az rest \
  --method POST \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/${foundry_principal_id}/appRoleAssignments" \
  --headers "Content-Type=application/json" \
  --body "{\"principalId\":\"${foundry_principal_id}\",\"resourceId\":\"${gateway_sp_object_id}\",\"appRoleId\":\"${app_role_id}\"}"

echo "Done."
