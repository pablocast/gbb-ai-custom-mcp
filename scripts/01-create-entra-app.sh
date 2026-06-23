#!/usr/bin/env bash
set -euo pipefail

# Requires: az login, Azure CLI with Graph permissions to manage app registrations.
# Input: environment variables from .env.sh

required_vars=(AZ_SUBSCRIPTION_ID ENTRA_TENANT_ID GATEWAY_APP_DISPLAY_NAME GATEWAY_REQUIRED_APP_ROLE)
for v in "${required_vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "Missing required env var: $v"
    exit 1
  fi
done

az account set --subscription "$AZ_SUBSCRIPTION_ID"

# UUID helper that works on Linux, macOS, and Windows Git Bash
new_uuid() {
  python3 -c "import uuid; print(uuid.uuid4())"
}

echo "Looking for existing app registration: $GATEWAY_APP_DISPLAY_NAME"
app_id="$(az ad app list --display-name "$GATEWAY_APP_DISPLAY_NAME" --query "[0].appId" -o tsv)"

if [[ -z "$app_id" || "$app_id" == "None" ]]; then
  echo "Creating Entra app registration: $GATEWAY_APP_DISPLAY_NAME"
  app_id="$(az ad app create \
    --display-name "$GATEWAY_APP_DISPLAY_NAME" \
    --sign-in-audience AzureADMyOrg \
    --query appId -o tsv)"
  if [[ -z "$app_id" ]]; then
    echo "Failed to create app registration"
    exit 1
  fi
else
  echo "Using existing app registration: $app_id"
fi

echo "Creating service principal (idempotent)"
sp_object_id="$(az ad sp list --filter "appId eq '${app_id}'" --query "[0].id" -o tsv)"
if [[ -z "$sp_object_id" || "$sp_object_id" == "None" ]]; then
  sp_object_id="$(az ad sp create --id "$app_id" --query id -o tsv)"
else
  echo "Using existing service principal: $sp_object_id"
fi

app_object_id="$(az ad app show --id "$app_id" --query id -o tsv)"
app_id_uri="api://$app_id"
scope_id="$(new_uuid)"
role_id="$(new_uuid)"

existing_role="$(az ad app show --id "$app_object_id" --query "appRoles[?value=='${GATEWAY_REQUIRED_APP_ROLE}'].id | [0]" -o tsv)"
existing_scope="$(az ad app show --id "$app_object_id" --query "api.oauth2PermissionScopes[?value=='Mcp.Invoke'].id | [0]" -o tsv)"

# Ensure identifier URI is set
current_uri="$(az ad app show --id "$app_object_id" --query "identifierUris[0]" -o tsv)"
if [[ -z "$current_uri" || "$current_uri" == "None" ]]; then
  echo "Setting Application ID URI: $app_id_uri"
  az ad app update --id "$app_object_id" --identifier-uris "$app_id_uri"
else
  echo "Application ID URI already set: $current_uri"
  app_id_uri="$current_uri"
fi

if [[ -n "$existing_role" && "$existing_role" != "None" && -n "$existing_scope" && "$existing_scope" != "None" ]]; then
  echo "App roles and scopes already set, skipping patch"
else
  echo "Patching app registration via Graph API (API settings + app roles)"
  patch_body="$(mktemp).json"
  cat > "$patch_body" <<JSONBODY
{
  "api": {
    "requestedAccessTokenVersion": 2,
    "oauth2PermissionScopes": [
      {
        "adminConsentDescription": "Allow callers to invoke MCP gateway API",
        "adminConsentDisplayName": "Invoke MCP Gateway",
        "id": "${scope_id}",
        "isEnabled": true,
        "type": "Admin",
        "value": "Mcp.Invoke"
      }
    ]
  },
  "appRoles": [
    {
      "allowedMemberTypes": ["Application"],
      "description": "Allows application caller to invoke MCP gateway.",
      "displayName": "${GATEWAY_REQUIRED_APP_ROLE}",
      "id": "${role_id}",
      "isEnabled": true,
      "value": "${GATEWAY_REQUIRED_APP_ROLE}"
    }
  ]
}
JSONBODY
  az rest \
    --method PATCH \
    --url "https://graph.microsoft.com/v1.0/applications/${app_object_id}" \
    --headers "Content-Type=application/json" \
    --body "@${patch_body}"
  rm -f "$patch_body"
fi

echo "Done."
echo "GATEWAY_APP_ID=$app_id"
echo "GATEWAY_APP_OBJECT_ID=$app_object_id"
echo "GATEWAY_SP_OBJECT_ID=$sp_object_id"
echo "GATEWAY_APP_ID_URI=$app_id_uri"
echo
echo "Run these next:"
echo "  export GATEWAY_APP_ID=\"$app_id\""
echo "  export GATEWAY_APP_ID_URI=\"$app_id_uri\""
echo "  azd env set GATEWAY_APP_ID \"$app_id\""
echo "  azd env set GATEWAY_APP_ID_URI \"$app_id_uri\""
