# Azure App Service Troubleshooting

Diagnostic commands and solutions for common issues.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Common Issues](#common-issues)
- [Debug Commands](#debug-commands)
- [Performance Issues](#performance-issues)

---

## Quick Diagnostics

```bash
# Check app status
az webapp show --name <app-name> --resource-group <rg-name> --query state

# View app configuration
az webapp config show --name <app-name> --resource-group <rg-name>

# List app settings
az webapp config appsettings list --name <app-name> --resource-group <rg-name>

# Stream live logs
az webapp log tail --name <app-name> --resource-group <rg-name>
```

---

## Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| **500 Internal Server Error** | Application error | Enable logs: `az webapp log config --application-logging filesystem`, then `az webapp log tail` |
| **App not starting** | Wrong runtime/startup | Check: `az webapp config show --query linuxFxVersion`, verify runtime matches app |
| **Deployment fails** | Bad ZIP structure | Verify ZIP contains app at root, check: `az webapp log deployment show` |
| **Env vars not loading** | Not set or cached | Verify: `az webapp config appsettings list`, restart app after changes |
| **Custom domain fails** | DNS not configured | Verify CNAME/A record, check: `az webapp config hostname list` |
| **SSL errors** | Certificate not bound | Check: `az webapp config ssl list`, verify hostname matches |
| **Slow performance** | Undersized plan | Scale up: `az appservice plan update --sku S1` |
| **Cold start delays** | Always On disabled | Enable: `az webapp config set --always-on true` (Basic+ required) |
| **Out of memory** | Insufficient resources | Scale up SKU, check for memory leaks |
| **Git deploy fails** | Bad credentials | Reset: `az webapp deployment user set` |

---

## Debug Commands

### Application Info

```bash
# Full app details
az webapp show --name <app-name> --resource-group <rg-name>

# Configuration
az webapp config show --name <app-name> --resource-group <rg-name>

# Runtime info
az webapp config show --name <app-name> --resource-group <rg-name> --query linuxFxVersion
```

### Logs

```bash
# Enable all logging
az webapp log config \
  --name <app-name> \
  --resource-group <rg-name> \
  --application-logging filesystem \
  --detailed-error-messages true \
  --failed-request-tracing true \
  --web-server-logging filesystem

# Stream logs
az webapp log tail --name <app-name> --resource-group <rg-name>

# Download logs
az webapp log download --name <app-name> --resource-group <rg-name> --log-file ./logs.zip
```

### Access & SSH

```bash
# SSH into container (Linux apps)
az webapp ssh --name <app-name> --resource-group <rg-name>

# Open Kudu console
az webapp browse --name <app-name> --resource-group <rg-name> --logs
```

### Deployment Status

```bash
# Show deployment source
az webapp deployment source show --name <app-name> --resource-group <rg-name>

# List publishing profiles
az webapp deployment list-publishing-profiles --name <app-name> --resource-group <rg-name>
```

---

## Performance Issues

### Cold Starts

```bash
# Enable Always On (requires Basic tier or higher)
az webapp config set \
  --name <app-name> \
  --resource-group <rg-name> \
  --always-on true
```

### Scaling

```bash
# Scale up (more powerful instance)
az appservice plan update \
  --name <plan-name> \
  --resource-group <rg-name> \
  --sku S1

# Scale out (more instances)
az appservice plan update \
  --name <plan-name> \
  --resource-group <rg-name> \
  --number-of-workers 3
```

### Health Check

```bash
# Configure health check path
az webapp config set \
  --name <app-name> \
  --resource-group <rg-name> \
  --generic-configurations '{"healthCheckPath": "/health"}'
```

---

## Error-Specific Solutions

### "Application Error" Page

1. Enable logging:
   ```bash
   az webapp log config --name <app> --resource-group <rg> --application-logging filesystem
   ```
2. Stream logs:
   ```bash
   az webapp log tail --name <app> --resource-group <rg>
   ```
3. Check for missing dependencies or startup errors

### Deployment Stuck

1. Restart the app:
   ```bash
   az webapp restart --name <app> --resource-group <rg>
   ```
2. If using Kudu, check deployment logs at `https://<app>.scm.azurewebsites.net`

### CORS Errors

```bash
# Add allowed origins
az webapp cors add \
  --name <app-name> \
  --resource-group <rg-name> \
  --allowed-origins https://your-frontend.com

# For development (not production)
az webapp cors add --name <app> --resource-group <rg> --allowed-origins "*"
```
