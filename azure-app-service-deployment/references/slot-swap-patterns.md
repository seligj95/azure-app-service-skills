# Deployment Slot Patterns

## Slot Swap Strategies

### Standard Swap (Recommended)

Deploy to staging, validate, then swap to production.

```bash
# Create staging slot
az webapp deployment slot create \
  --name <app-name> \
  --resource-group <rg> \
  --slot staging

# Deploy to staging
az webapp deploy \
  --name <app-name> \
  --resource-group <rg> \
  --slot staging \
  --src-path ./app.zip

# Validate staging (manual or automated tests)
curl https://<app-name>-staging.azurewebsites.net/health

# Swap staging to production
az webapp deployment slot swap \
  --name <app-name> \
  --resource-group <rg> \
  --slot staging \
  --target-slot production
```

### Swap with Preview (Two-Phase Swap)

Test with production settings before completing swap.

```bash
# Phase 1: Apply production config to staging (no traffic switch)
az webapp deployment slot swap \
  --name <app-name> \
  --resource-group <rg> \
  --slot staging \
  --target-slot production \
  --action preview

# Validate staging with production config
curl https://<app-name>-staging.azurewebsites.net/health

# Phase 2: Complete the swap
az webapp deployment slot swap \
  --name <app-name> \
  --resource-group <rg> \
  --slot staging \
  --target-slot production \
  --action swap

# OR cancel if issues found
az webapp deployment slot swap \
  --name <app-name> \
  --resource-group <rg> \
  --slot staging \
  --target-slot production \
  --action reset
```

### Rollback Pattern

Swap back if issues detected in production.

```bash
# Swap back (staging still has previous production code)
az webapp deployment slot swap \
  --name <app-name> \
  --resource-group <rg> \
  --slot staging \
  --target-slot production
```

## Warm-Up Configuration

### Application Initialization

Configure warm-up requests to run before swap completes.

```xml
<!-- web.config for .NET apps -->
<system.webServer>
  <applicationInitialization>
    <add initializationPage="/" />
    <add initializationPage="/api/health" />
    <add initializationPage="/api/warmup" />
  </applicationInitialization>
</system.webServer>
```

### Custom Warm-Up via App Settings

```bash
# Set warm-up path
az webapp config appsettings set \
  --name <app-name> \
  --resource-group <rg> \
  --settings WEBSITE_SWAP_WARMUP_PING_PATH="/health" \
             WEBSITE_SWAP_WARMUP_PING_STATUSES="200,202"
```

### Health Check for Swap Validation

```bash
# Configure health check (used during swap)
az webapp config set \
  --name <app-name> \
  --resource-group <rg> \
  --generic-configurations '{"healthCheckPath": "/health"}'
```

## Slot-Specific Settings

### Marking Settings as Slot-Specific

Slot settings don't swap - they stay with the slot.

```bash
# App settings that stay with slot
az webapp config appsettings set \
  --name <app-name> \
  --resource-group <rg> \
  --slot staging \
  --slot-settings \
    ENVIRONMENT=staging \
    FEATURE_FLAG_X=true

# Connection strings that stay with slot
az webapp config connection-string set \
  --name <app-name> \
  --resource-group <rg> \
  --slot staging \
  --connection-string-type SQLAzure \
  --slot-settings \
    DB_CONNECTION="Server=staging-db.database.windows.net;..."
```

### Common Slot Settings Pattern

| Setting | Slot-Specific? | Reason |
|---------|----------------|--------|
| `ENVIRONMENT` | Yes | Different per slot |
| `APPINSIGHTS_INSTRUMENTATIONKEY` | Yes | Track telemetry separately |
| `DATABASE_CONNECTION` | Yes | Different databases |
| `REDIS_CONNECTION` | Maybe | Depends on architecture |
| `API_KEY` | No | Same key across environments |
| `WEBSITE_RUN_FROM_PACKAGE` | No | Same deployment pattern |

## Traffic Routing

### Gradual Traffic Shift (Canary Deployment)

```bash
# Route 10% of traffic to staging
az webapp traffic-routing set \
  --name <app-name> \
  --resource-group <rg> \
  --distribution staging=10

# Increase to 25%
az webapp traffic-routing set \
  --name <app-name> \
  --resource-group <rg> \
  --distribution staging=25

# Complete rollout (100% to staging, then swap)
az webapp traffic-routing clear \
  --name <app-name> \
  --resource-group <rg>

az webapp deployment slot swap \
  --name <app-name> \
  --resource-group <rg> \
  --slot staging
```

### A/B Testing Configuration

```bash
# Split traffic 50/50 between production and staging
az webapp traffic-routing set \
  --name <app-name> \
  --resource-group <rg> \
  --distribution staging=50
```

## Auto-Swap Configuration

### Enable Auto-Swap

Automatically swap staging to production after deployment succeeds.

```bash
# Enable auto-swap on staging slot
az webapp deployment slot auto-swap \
  --name <app-name> \
  --resource-group <rg> \
  --slot staging \
  --auto-swap-slot production
```

**Warning**: Only use auto-swap for low-risk deployments. Prefer manual swap with validation for production workloads.

## Multi-Slot Pipeline Pattern

```
                    ┌─────────────┐
                    │    Build    │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   Deploy    │
                    │     Dev     │
                    └──────┬──────┘
                           │ Auto Tests
                           ▼
                    ┌─────────────┐
                    │   Deploy    │
                    │   Staging   │
                    └──────┬──────┘
                           │ Manual Approval
                           ▼
                    ┌─────────────┐
                    │    Swap     │
                    │ Production  │
                    └─────────────┘
```

### Implementation

```bash
# Create both slots
az webapp deployment slot create --name <app> --resource-group <rg> --slot dev
az webapp deployment slot create --name <app> --resource-group <rg> --slot staging

# CI/CD deploys to dev
# Auto tests validate dev
# Promote dev → staging
az webapp deployment slot swap --name <app> --resource-group <rg> --slot dev --target-slot staging

# Manual approval gate
# Swap staging → production
az webapp deployment slot swap --name <app> --resource-group <rg> --slot staging --target-slot production
```

## Slot Limits by SKU

| SKU | Max Slots |
|-----|-----------|
| Free, Shared | 0 |
| Basic | 0 |
| Standard | 5 |
| Premium V2/V3/V4 | 20 |
| Isolated V2 | 20 |
