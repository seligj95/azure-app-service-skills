---
name: azure-app-service-deployment
description: Deploy applications to Azure App Service using CI/CD pipelines, GitHub Actions, Azure Pipelines, deployment slots, and Run From Package. Use when setting up automated deployments, configuring staging environments, implementing blue-green deployments, swapping slots, or troubleshooting deployment failures.
---

## When to Apply

Reference these guidelines when:

- Setting up CI/CD pipelines for App Service
- Configuring GitHub Actions or Azure Pipelines deployments
- Using deployment slots for staging and production
- Implementing zero-downtime deployments
- Troubleshooting deployment failures

## Deployment Methods

| Method | Best For | Complexity |
|--------|----------|------------|
| `az webapp up` | Quick deployments, prototyping | Low |
| GitHub Actions | Automated CI/CD from GitHub | Medium |
| Azure Pipelines | Enterprise CI/CD with Azure DevOps | Medium |
| ZIP Deploy | Simple file-based deployments | Low |
| Run From Package | Production deployments (recommended) | Low |
| Local Git | Developer-driven deployments | Low |
| Container Registry | Docker container deployments | Medium |

## GitHub Actions Deployment

### Authentication Methods (Recommended Order)

1. **OpenID Connect (OIDC)** - Most secure, no secrets stored
2. **Service Principal** - For programmatic access
3. **Publish Profile** - Simple but less secure

### OpenID Connect Setup (Recommended)

```bash
# 1. Create Microsoft Entra app
az ad app create --display-name "github-deploy-app"

# 2. Create service principal
az ad sp create --id <app-id>

# 3. Assign Website Contributor role
az role assignment create \
  --role "Website Contributor" \
  --assignee-object-id <sp-object-id> \
  --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Web/sites/<app>

# 4. Create federated credential
az ad app federated-credential create --id <app-object-id> --parameters '{
  "name": "github-main-branch",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<org>/<repo>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

**GitHub Secrets Required:**
- `AZURE_CLIENT_ID` - Application (client) ID
- `AZURE_TENANT_ID` - Directory (tenant) ID
- `AZURE_SUBSCRIPTION_ID` - Subscription ID

### Workflow Examples

#### Node.js with OpenID Connect

```yaml
name: Deploy Node.js to Azure App Service

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

env:
  AZURE_WEBAPP_NAME: my-app
  NODE_VERSION: '20'

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: 'npm'

      - name: Install and build
        run: |
          npm ci
          npm run build --if-present
          npm run test --if-present

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy to Azure Web App
        uses: azure/webapps-deploy@v3
        with:
          app-name: ${{ env.AZURE_WEBAPP_NAME }}
          package: .
```

#### Python with Publish Profile

```yaml
name: Deploy Python to Azure App Service

on:
  push:
    branches: [main]

env:
  AZURE_WEBAPP_NAME: my-python-app
  PYTHON_VERSION: '3.11'

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Create venv and install dependencies
        run: |
          python -m venv venv
          source venv/bin/activate
          pip install -r requirements.txt

      - name: Deploy to Azure Web App
        uses: azure/webapps-deploy@v3
        with:
          app-name: ${{ env.AZURE_WEBAPP_NAME }}
          publish-profile: ${{ secrets.AZURE_WEBAPP_PUBLISH_PROFILE }}
          package: .
```

#### .NET with Slot Deployment

```yaml
name: Deploy .NET to Azure App Service (Slot)

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

env:
  AZURE_WEBAPP_NAME: my-dotnet-app
  DOTNET_VERSION: '8.0.x'

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: ${{ env.DOTNET_VERSION }}

      - name: Build and publish
        run: |
          dotnet restore
          dotnet build --configuration Release
          dotnet publish -c Release -o ./publish

      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy to staging slot
        uses: azure/webapps-deploy@v3
        with:
          app-name: ${{ env.AZURE_WEBAPP_NAME }}
          slot-name: staging
          package: ./publish

      - name: Swap slots
        run: |
          az webapp deployment slot swap \
            --name ${{ env.AZURE_WEBAPP_NAME }} \
            --resource-group ${{ secrets.AZURE_RESOURCE_GROUP }} \
            --slot staging \
            --target-slot production
```

## Deployment Slots

### Best Practices

| Practice | Description |
|----------|-------------|
| Always use staging slot | Never deploy directly to production |
| Configure slot settings | Mark environment-specific settings as slot settings |
| Warm up before swap | Configure warm-up rules to pre-load app |
| Test staging thoroughly | Verify at `https://<app>-staging.azurewebsites.net` |
| Keep rollback ready | Swap back if issues detected |

### CLI Commands

```bash
# Create staging slot
az webapp deployment slot create \
  --name <app> --resource-group <rg> --slot staging

# Deploy to staging
az webapp deployment source config-zip \
  --name <app> --resource-group <rg> --slot staging --src ./app.zip

# Configure slot setting (doesn't swap with slot)
az webapp config appsettings set \
  --name <app> --resource-group <rg> --slot staging \
  --slot-settings ENVIRONMENT=staging

# Swap staging to production
az webapp deployment slot swap \
  --name <app> --resource-group <rg> --slot staging

# Swap with preview (two-phase swap)
az webapp deployment slot swap \
  --name <app> --resource-group <rg> --slot staging --action preview

# Complete swap after preview
az webapp deployment slot swap \
  --name <app> --resource-group <rg> --slot staging --action swap

# Cancel swap
az webapp deployment slot swap \
  --name <app> --resource-group <rg> --slot staging --action reset
```

### Warm-up Configuration

Add to `web.config` or configure via CLI:

```xml
<system.webServer>
  <applicationInitialization>
    <add initializationPage="/health" />
    <add initializationPage="/api/warmup" />
  </applicationInitialization>
</system.webServer>
```

## Run From Package (Recommended)

Deploy as immutable ZIP package for faster, atomic deployments.

```bash
# Enable Run From Package
az webapp config appsettings set \
  --name <app> --resource-group <rg> \
  --settings WEBSITE_RUN_FROM_PACKAGE=1

# Deploy ZIP
az webapp deployment source config-zip \
  --name <app> --resource-group <rg> --src ./app.zip
```

**Benefits:**
- Faster cold starts
- Atomic deployments (no partial deploys)
- App files are read-only (more secure)
- Reduced storage I/O

## Publish Profile Setup

```bash
# Download publish profile
az webapp deployment list-publishing-profiles \
  --name <app> --resource-group <rg> --xml > publish-profile.xml

# Store as GitHub secret: AZURE_WEBAPP_PUBLISH_PROFILE
```

## Azure Pipelines

### YAML Pipeline Example

```yaml
trigger:
  - main

pool:
  vmImage: 'ubuntu-latest'

variables:
  azureSubscription: 'my-azure-connection'
  webAppName: 'my-app'
  resourceGroup: 'my-rg'

stages:
  - stage: Build
    jobs:
      - job: Build
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '20.x'

          - script: |
              npm ci
              npm run build
            displayName: 'Build'

          - task: ArchiveFiles@2
            inputs:
              rootFolderOrFile: '$(Build.SourcesDirectory)'
              includeRootFolder: false
              archiveFile: '$(Build.ArtifactStagingDirectory)/app.zip'

          - publish: $(Build.ArtifactStagingDirectory)/app.zip
            artifact: drop

  - stage: Deploy
    dependsOn: Build
    jobs:
      - deployment: Deploy
        environment: 'production'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureWebApp@1
                  inputs:
                    azureSubscription: $(azureSubscription)
                    appName: $(webAppName)
                    package: '$(Pipeline.Workspace)/drop/app.zip'
                    deploymentMethod: 'zipDeploy'
```

## Troubleshooting Deployments

| Issue | Solution |
|-------|----------|
| Deployment stuck | Check Kudu logs at `https://<app>.scm.azurewebsites.net` |
| ZIP deploy fails | Verify ZIP structure (app at root, not nested folder) |
| OIDC auth fails | Check federated credential subject matches branch/environment |
| Slot swap fails | Check slot settings, verify app starts in staging |
| Cold start after deploy | Enable Run From Package, configure warm-up |

```bash
# Check deployment logs
az webapp log deployment show --name <app> --resource-group <rg>

# Stream live logs during deployment
az webapp log tail --name <app> --resource-group <rg>
```

## References

- **GitHub Actions Workflows**: See [references/github-actions.md](references/github-actions.md) for more workflow examples
- **Slot Configuration**: See [references/slots.md](references/slots.md) for advanced slot patterns
