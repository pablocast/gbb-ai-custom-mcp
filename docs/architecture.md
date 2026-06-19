# Architecture and security model

## Components

- Foundry Agent runtime
- Foundry Project identity (service principal / managed identity)
- Customer MCP Gateway app registration in Microsoft Entra ID
- Customer MCP Gateway running on Azure Container Apps

## Trust chain

1. Gateway is registered as an Entra application and exposes an API audience (Application ID URI).
2. Foundry Project identity requests an access token for that audience.
3. Foundry Agent invokes the MCP endpoint with `Authorization: Bearer <token>`.
4. Gateway validates token signature and claims:
   - `iss` must be expected tenant issuer.
   - `aud` must equal gateway Application ID URI.
   - optional hardening: `appid`/`azp` allow-list, `roles` or `scp` checks.

## Why this pattern is recommended

- Identity is centrally managed in Entra.
- Credentials are not embedded in the agent runtime.
- Token is audience-scoped and short-lived.
- Standard zero-trust API protection pattern.

## Minimum Azure resources

- Resource group
- Azure Container Registry (for gateway image)
- Log Analytics workspace
- Container Apps environment
- Container App (gateway)
- Entra app registration + service principal for gateway API

## Foundry MCP tool settings

At minimum configure:

- MCP endpoint URL: `https://<gateway-fqdn>/mcp`
- Auth type: Entra / AAD token flow
- Audience / Resource: gateway Application ID URI (for example `api://<gateway-app-id>`)

## Production hardening

- Restrict ingress using APIM or Front Door + WAF.
- Use private networking and Private Endpoints where possible.
- Enforce app role assignments and check `roles` claim.
- Add caller allow-list on `appid` or object ID.
- Send structured audit logs to Log Analytics.
