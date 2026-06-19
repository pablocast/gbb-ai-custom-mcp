targetScope = 'resourceGroup'

@minLength(1)
param environmentName string
param location string = resourceGroup().location
@minLength(1)
param entraTenantId string
@minLength(1)
param gatewayAudience string
param allowedClientIds string = ''
param acaLocation string 
param modelDeploymentName string = 'gpt54mini'
param modelName string = 'gpt-5.4-mini'
param modelVersion string = '2026-03-17'
param modelSkuName string = 'GlobalStandard'
param modelCapacity string = '10'

var resourceToken = uniqueString(subscription().id, resourceGroup().id, location, environmentName)
var acaToken = uniqueString(subscription().id, resourceGroup().id, acaLocation, environmentName, 'aca2')

var acrName = 'azacr${resourceToken}'
var logAnalyticsName = 'azlog${resourceToken}'
var containerAppEnvName = 'azcae${acaToken}'
var userAssignedIdentityName = 'azidn${resourceToken}'
var containerAppName = 'azaca${acaToken}'
var foundryAccountName = 'azcog${resourceToken}'
var foundryProjectName = 'azprj${resourceToken}'

var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: userAssignedIdentityName
  location: location
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, userAssignedIdentity.id, acrPullRoleDefinitionId)
  scope: containerRegistry
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvName
  location: acaLocation
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryAccountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: foundryAccountName
    allowProjectManagement: true
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-12-01' = {
  parent: foundryAccount
  name: foundryProjectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: foundryProjectName
    description: 'Foundry project for MCP gateway integration'
  }
}

resource foundryModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-12-01' = {
  parent: foundryAccount
  name: modelDeploymentName
  sku: {
    name: modelSkuName
    capacity: int(modelCapacity)
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    raiPolicyName: 'Microsoft.Default'
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: acaLocation
  tags: {
    'azd-service-name': 'gateway'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        allowInsecure: false
        corsPolicy: {
          allowedOrigins: [
            '*'
          ]
          allowedMethods: [
            'GET'
            'POST'
            'OPTIONS'
          ]
          allowedHeaders: [
            '*'
          ]
          exposeHeaders: [
            '*'
          ]
          maxAge: 3600
        }
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: userAssignedIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'gateway'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          env: [
            {
              name: 'ENTRA_TENANT_ID'
              value: entraTenantId
            }
            {
              name: 'GATEWAY_AUDIENCE'
              value: gatewayAudience
            }
            {
              name: 'ALLOWED_CLIENT_IDS'
              value: allowedClientIds
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
  dependsOn: [
    acrPullRoleAssignment
  ]
}

output AZURE_LOCATION string = location
output CONTAINER_APP_NAME string = containerApp.name
output CONTAINER_APP_URL string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output ACR_NAME string = containerRegistry.name
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.properties.loginServer
output UAMI_PRINCIPAL_ID string = userAssignedIdentity.properties.principalId
output FOUNDRY_ACCOUNT_NAME string = foundryAccount.name
output FOUNDRY_ACCOUNT_RESOURCE_ID string = foundryAccount.id
output FOUNDRY_PROJECT_NAME string = foundryProject.name
output FOUNDRY_PROJECT_RESOURCE_ID string = foundryProject.id
output FOUNDRY_MODEL_DEPLOYMENT_NAME string = foundryModelDeployment.name
