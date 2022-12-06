targetScope = 'subscription'

//------------------------------------------------------------------------------
// Options: parameters having broad impact on the deployement.
//------------------------------------------------------------------------------

@description('location where all the resources are to be deployed')
param location string = deployment().location

@description('short string used to identify deployment environment')
@allowed([
  'dev'
  'prod'
])
param environment string = 'dev'

@description('short string used to generate all resources')
@minLength(5)
@maxLength(13)
param prefix string = uniqueString(environment, subscription().id, location)

@description('additonal tags to attach to resources created')
param tags object = {}

@description('when true, all resources will be deployed under a single resource-group')
param useSingleResourceGroup bool = false

@description('deployment timestamp')
param timestamp string = utcNow('g')

//------------------------------------------------------------------------------
// Features: additive components
//------------------------------------------------------------------------------

@description('when true, log analytics workspace and related resources will be deployed')
param deployDiagnostics bool = false

@description('existing log analytics workspace to use for logging all diagnostic information')
@metadata({
  group: 'resource group name'
  name: 'resource name'
})
param externalLogAnalyticsWorkspace object = {}

//------------------------------------------------------------------------------
// Variables
//------------------------------------------------------------------------------

@description('resources prefix')
var rsPrefix = '${environment}-${prefix}'

@description('deployments prefix')
var dplPrefix = 'dpl-${environment}-${prefix}'

@description('tags for all resources')
var allTags = union(tags, {
  'last deployed': timestamp
  source: 'azbatch-starter:v0.1'
})

@description('resource group names')
var resourceGroupNames = {
  diagnosticsRG:  {
    name: useSingleResourceGroup? 'rg-${rsPrefix}' : 'rg-${rsPrefix}-diag'
    enabled: deployDiagnostics && empty(externalLogAnalyticsWorkspace)
  }

  batchRG: {
    name: useSingleResourceGroup? 'rg-${rsPrefix}' : 'rg-${rsPrefix}-batch'
    enabled: true
  }
}

//------------------------------------------------------------------------------
// Resources
//------------------------------------------------------------------------------

// dev notes: `union()` is used to remove duplicates
var uniqueGroups = union(filter(map(items(resourceGroupNames), arg => arg.value.enabled ? arg.value.name : ''), name => !empty(name)), [])

@description('all resource groups')
resource resourceGroups 'Microsoft.Resources/resourceGroups@2021-04-01' = [for name in uniqueGroups: {
  name: name
  location: location
  tags: allTags
}]

@description('deployment for diagnostics resources')
module dplDiagnostics 'modules/diagnostics.bicep' = if (resourceGroupNames.diagnosticsRG.enabled) {
  name: '${dplPrefix}-diagnostics'
  scope: resourceGroup(resourceGroupNames.diagnosticsRG.name)
  params: {
    rsPrefix: rsPrefix
    location: location
    tags: allTags
  }
  dependsOn: [
    // this is necessary to ensure all resource groups have been deployed
    // before we attempt to deploy resources under those resource groups.
    resourceGroups
  ]
}

@description('deployment for batch resources')
module dplBatch 'modules/batch.bicep' = {
  name: '${dplPrefix}-batch'
  scope: resourceGroup(resourceGroupNames.batchRG.name)
  params: {
    location: location
    dplPrefix: dplPrefix
    rsPrefix: rsPrefix
    tags: allTags
  }
  dependsOn: [
    // this is necessary to ensure all resource groups have been deployed
    // before we attempt to deploy resources under those resource groups.
    resourceGroups
  ]
}

var enableDiagnostics = deployDiagnostics || !empty(externalLogAnalyticsWorkspace)
@description('log analytics workspace to use for all diagnostic logging')
resource logAnalyticWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = if (enableDiagnostics) {
  name: empty(externalLogAnalyticsWorkspace) ? dplDiagnostics.outputs.logAnalyticsWorkspace.name : externalLogAnalyticsWorkspace.name
  scope: resourceGroup(empty(externalLogAnalyticsWorkspace) ? dplDiagnostics.outputs.logAnalyticsWorkspace.group : externalLogAnalyticsWorkspace.group)
}

@description('log analytics workspace id')
output logAnalyticWorkspceId string = enableDiagnostics ? logAnalyticWorkspace.id : ''

@description('resource groups created')
output resourceGroupNames array = uniqueGroups