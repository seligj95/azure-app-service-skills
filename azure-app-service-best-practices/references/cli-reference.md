# Azure App Service CLI Reference

Detailed command reference for Azure App Service management.

## Table of Contents

- [az webapp up](#az-webapp-up)
- [az webapp create](#az-webapp-create)
- [az appservice plan](#az-appservice-plan)
- [az webapp config](#az-webapp-config)
- [az webapp deployment](#az-webapp-deployment)
- [az webapp log](#az-webapp-log)
- [az webapp identity](#az-webapp-identity)

---

## az webapp up

**Recommended for quick deployments.** Creates resources and deploys in one command.

```bash
# Deploy from current directory (auto-detects runtime)
az webapp up --name <app-name> --resource-group <rg-name>

# Specify runtime explicitly
az webapp up --name <app-name> --resource-group <rg-name> --runtime "NODE:20-lts"
az webapp up --name <app-name> --resource-group <rg-name> --runtime "PYTHON:3.11"
az webapp up --name <app-name> --resource-group <rg-name> --runtime "DOTNETCORE:8.0"

# Deploy to specific region with plan
az webapp up --name <app-name> --resource-group <rg-name> --location eastus --sku B1

# Deploy from ZIP file
az webapp up --name <app-name> --resource-group <rg-name> --src-path ./app.zip
```

**Key flags:**
| Flag | Description |
|------|-------------|
| `--name, -n` | Web app name (globally unique) |
| `--resource-group, -g` | Resource group name |
| `--runtime, -r` | Runtime stack |
| `--sku` | Plan tier (F1, B1, S1, P1V2, etc.) |
| `--location, -l` | Azure region |
| `--html` | Deploy as static HTML |
| `--src-path` | Path to ZIP or folder |

---

## az webapp create

Create a web app in an existing App Service plan.

```bash
# Create web app
az webapp create \
  --name <app-name> \
  --resource-group <rg-name> \
  --plan <plan-name> \
  --runtime "NODE:20-lts"

# Create from Docker container
az webapp create \
  --name <app-name> \
  --resource-group <rg-name> \
  --plan <plan-name> \
  --deployment-container-image-name <registry>/<image>:<tag>
```

---

## az appservice plan

Manage App Service plans (compute resources).

```bash
# Create Linux plan (recommended)
az appservice plan create \
  --name <plan-name> \
  --resource-group <rg-name> \
  --sku B1 \
  --is-linux

# Create Windows plan
az appservice plan create \
  --name <plan-name> \
  --resource-group <rg-name> \
  --sku S1

# Create free tier
az appservice plan create \
  --name <plan-name> \
  --resource-group <rg-name> \
  --sku F1 \
  --is-linux

# Scale up
az appservice plan update \
  --name <plan-name> \
  --resource-group <rg-name> \
  --sku S1
```

**SKU tiers:**
| SKU | Description | Use Case |
|-----|-------------|----------|
| F1 | Free | Dev/test |
| B1-B3 | Basic | Dev/test, low traffic |
| S1-S3 | Standard | Production, autoscale |
| P1V2-P3V2 | Premium V2 | High performance |
| P1V3-P3V3 | Premium V3 | Best performance |

---

## az webapp config

### App Settings (Environment Variables)

```bash
# Set app settings
az webapp config appsettings set \
  --name <app-name> \
  --resource-group <rg-name> \
  --settings KEY1=value1 KEY2=value2

# List all settings
az webapp config appsettings list \
  --name <app-name> \
  --resource-group <rg-name>

# Delete a setting
az webapp config appsettings delete \
  --name <app-name> \
  --resource-group <rg-name> \
  --setting-names KEY1
```

### Connection Strings

```bash
# Set connection string
az webapp config connection-string set \
  --name <app-name> \
  --resource-group <rg-name> \
  --connection-string-type SQLAzure \
  --settings "DefaultConnection=Server=tcp:server.database.windows.net..."

# Types: SQLAzure, SQLServer, MySql, PostgreSQL, Custom
```

### Startup Command

```bash
# Set startup command (Linux)
az webapp config set \
  --name <app-name> \
  --resource-group <rg-name> \
  --startup-file "gunicorn --bind=0.0.0.0 app:app"
```

### Always On

```bash
# Enable Always On (prevents cold starts, requires Basic+)
az webapp config set \
  --name <app-name> \
  --resource-group <rg-name> \
  --always-on true
```

---

## az webapp deployment

### Deployment Slots

```bash
# Create staging slot
az webapp deployment slot create \
  --name <app-name> \
  --resource-group <rg-name> \
  --slot staging

# Deploy to slot
az webapp deployment source config-zip \
  --name <app-name> \
  --resource-group <rg-name> \
  --slot staging \
  --src ./app.zip

# Swap slots (zero-downtime)
az webapp deployment slot swap \
  --name <app-name> \
  --resource-group <rg-name> \
  --slot staging \
  --target-slot production

# List slots
az webapp deployment slot list \
  --name <app-name> \
  --resource-group <rg-name>
```

### Deployment Sources

```bash
# Local Git
az webapp deployment source config-local-git \
  --name <app-name> \
  --resource-group <rg-name>

# GitHub (manual integration)
az webapp deployment source config \
  --name <app-name> \
  --resource-group <rg-name> \
  --repo-url https://github.com/<owner>/<repo> \
  --branch main \
  --manual-integration

# ZIP deploy
az webapp deployment source config-zip \
  --name <app-name> \
  --resource-group <rg-name> \
  --src ./app.zip
```

### Publish Profile (for GitHub Actions)

```bash
az webapp deployment list-publishing-profiles \
  --name <app-name> \
  --resource-group <rg-name> \
  --xml
```

---

## az webapp log

```bash
# Enable logging
az webapp log config \
  --name <app-name> \
  --resource-group <rg-name> \
  --application-logging filesystem \
  --detailed-error-messages true \
  --web-server-logging filesystem

# Stream live logs
az webapp log tail \
  --name <app-name> \
  --resource-group <rg-name>

# Download logs
az webapp log download \
  --name <app-name> \
  --resource-group <rg-name> \
  --log-file ./logs.zip
```

---

## az webapp identity

Configure managed identity for secure service access.

```bash
# Enable system-assigned managed identity
az webapp identity assign \
  --name <app-name> \
  --resource-group <rg-name>

# Assign user-assigned managed identity
az webapp identity assign \
  --name <app-name> \
  --resource-group <rg-name> \
  --identities <identity-resource-id>
```

---

## Common Operations

```bash
# Restart
az webapp restart --name <app-name> --resource-group <rg-name>

# Stop
az webapp stop --name <app-name> --resource-group <rg-name>

# Start
az webapp start --name <app-name> --resource-group <rg-name>

# Show details
az webapp show --name <app-name> --resource-group <rg-name>

# SSH into container (Linux)
az webapp ssh --name <app-name> --resource-group <rg-name>

# CORS
az webapp cors add \
  --name <app-name> \
  --resource-group <rg-name> \
  --allowed-origins https://example.com
```

---

## Runtime Values Reference

| Language | Runtime Value |
|----------|---------------|
| Node.js 20 | `NODE:20-lts` |
| Node.js 18 | `NODE:18-lts` |
| Python 3.11 | `PYTHON:3.11` |
| Python 3.10 | `PYTHON:3.10` |
| .NET 8 | `DOTNETCORE:8.0` |
| .NET 6 | `DOTNETCORE:6.0` |
| Java 17 | `JAVA:17-java17` |
| PHP 8.2 | `PHP:8.2` |
