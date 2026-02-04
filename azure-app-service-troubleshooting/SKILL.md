---
name: azure-app-service-troubleshooting
description: Diagnose and resolve Azure App Service issues including HTTP errors, startup failures, performance problems, deployment failures, and connectivity issues. Use when troubleshooting 500 errors, application crashes, slow performance, cold starts, deployment stuck, networking problems, or analyzing application logs.
---

## When to Apply

Reference these guidelines when:

- Investigating HTTP 500 errors or application crashes
- Debugging application startup failures
- Analyzing slow response times or timeouts
- Troubleshooting deployment failures
- Diagnosing networking or connectivity issues
- Investigating memory or CPU problems

## Quick Diagnostic Commands

```bash
# Check app status
az webapp show --name <app> --resource-group <rg> --query state

# Stream live logs
az webapp log tail --name <app> --resource-group <rg>

# Check configuration
az webapp config show --name <app> --resource-group <rg>

# View app settings
az webapp config appsettings list --name <app> --resource-group <rg>

# SSH into container (Linux)
az webapp ssh --name <app> --resource-group <rg>
```

## HTTP Error Troubleshooting

### 500 Internal Server Error

**Common Causes:**
- Application code exception
- Missing dependencies
- Configuration errors
- Database connection failures

**Diagnostic Steps:**

```bash
# 1. Enable detailed logging
az webapp log config \
  --name <app> --resource-group <rg> \
  --application-logging filesystem \
  --detailed-error-messages true \
  --level verbose

# 2. Stream logs to find error
az webapp log tail --name <app> --resource-group <rg>

# 3. Download logs for analysis
az webapp log download --name <app> --resource-group <rg> --log-file ./logs.zip
```

**Check Application Insights:**
```kql
exceptions
| where timestamp > ago(1h)
| order by timestamp desc
| take 50
```

### 502 Bad Gateway

**Common Causes:**
- Application not responding to health checks
- Application startup timeout
- Worker process crash

**Solutions:**
```bash
# Restart app
az webapp restart --name <app> --resource-group <rg>

# Check health check configuration
az webapp config show --name <app> --resource-group <rg> --query healthCheckPath

# Increase startup timeout (default 230s)
az webapp config appsettings set \
  --name <app> --resource-group <rg> \
  --settings WEBSITES_CONTAINER_START_TIME_LIMIT=600
```

### 503 Service Unavailable

**Common Causes:**
- App stopped or restarting
- Out of memory
- Reaching plan limits

**Solutions:**
```bash
# Check app state
az webapp show --name <app> --resource-group <rg> --query state

# Start if stopped
az webapp start --name <app> --resource-group <rg>

# Scale up if resource constrained
az appservice plan update --name <plan> --resource-group <rg> --sku S2
```

### 504 Gateway Timeout

**Common Causes:**
- Long-running requests (>230s)
- Backend service timeout
- Database query timeout

**Solutions:**
- Increase request timeout (max 230s for standard App Service)
- Use async patterns for long operations
- Implement background jobs for long tasks

## Startup Failures

### Check Startup Logs

```bash
# Linux apps - check Docker logs
az webapp log tail --name <app> --resource-group <rg>

# Check container startup
az webapp log show --name <app> --resource-group <rg>
```

### Common Startup Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| "Application Error" page | App crashed on startup | Check logs for exceptions |
| Container never starts | Wrong startup command | Set explicit startup command |
| Port binding error | App not on correct port | Bind to `$PORT` or `8080` |
| Missing dependencies | Requirements not installed | Check requirements.txt or package.json |

### Fix Startup Command

```bash
# Python - Flask
az webapp config set \
  --name <app> --resource-group <rg> \
  --startup-file "gunicorn --bind=0.0.0.0:8000 app:app"

# Python - Django
az webapp config set \
  --name <app> --resource-group <rg> \
  --startup-file "gunicorn --bind=0.0.0.0:8000 myproject.wsgi"

# Node.js
az webapp config set \
  --name <app> --resource-group <rg> \
  --startup-file "node server.js"
```

### Container Startup Timeout

```bash
# Increase container startup timeout (default 230s, max 1800s)
az webapp config appsettings set \
  --name <app> --resource-group <rg> \
  --settings WEBSITES_CONTAINER_START_TIME_LIMIT=600
```

## Performance Issues

### Slow Response Times

**Diagnostic Steps:**

```bash
# Check metrics
az monitor metrics list \
  --resource "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Web/sites/<app>" \
  --metric ResponseTime \
  --interval PT1M

# Check CPU/Memory
az monitor metrics list \
  --resource "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Web/serverfarms/<plan>" \
  --metric CpuPercentage,MemoryPercentage \
  --interval PT1M
```

**Application Insights Query:**
```kql
requests
| where timestamp > ago(1h)
| summarize 
    P50 = percentile(duration, 50),
    P95 = percentile(duration, 95),
    P99 = percentile(duration, 99)
    by bin(timestamp, 5m)
| render timechart
```

**Solutions:**
```bash
# Enable Always On (prevents cold starts)
az webapp config set --name <app> --resource-group <rg> --always-on true

# Scale up
az appservice plan update --name <plan> --resource-group <rg> --sku S2

# Scale out
az appservice plan update --name <plan> --resource-group <rg> --number-of-workers 3
```

### Cold Start Issues

**Causes:**
- App idle timeout (Always On disabled)
- Deployment slot swap
- Instance restart

**Solutions:**
```bash
# Enable Always On (requires Basic+)
az webapp config set --name <app> --resource-group <rg> --always-on true

# Use Run From Package (faster startup)
az webapp config appsettings set \
  --name <app> --resource-group <rg> \
  --settings WEBSITE_RUN_FROM_PACKAGE=1

# Configure warm-up slots before swap
# Add warm-up paths in web.config or application
```

### High CPU/Memory

```bash
# Profile from Kudu
# Navigate to: https://<app>.scm.azurewebsites.net/DiagnosticServices

# Check process info
az webapp list-instances --name <app> --resource-group <rg>
```

**Application Insights:**
```kql
performanceCounters
| where timestamp > ago(1h)
| where name == "% Processor Time" or name == "Available Bytes"
| summarize avg(value) by bin(timestamp, 5m), name
| render timechart
```

## Deployment Failures

### ZIP Deploy Fails

**Common Issues:**
- ZIP structure incorrect (app nested in folder)
- File too large
- Permissions issue

```bash
# Check deployment status
az webapp deployment source show --name <app> --resource-group <rg>

# View deployment logs
az webapp log deployment show --name <app> --resource-group <rg>

# Verify ZIP structure
unzip -l app.zip | head -20
```

### Slot Swap Fails

**Common Causes:**
- App fails health check in staging
- Configuration error in staging
- Warm-up timeout

```bash
# Check staging slot health
curl -I https://<app>-staging.azurewebsites.net/health

# Swap with preview (two-phase)
az webapp deployment slot swap \
  --name <app> --resource-group <rg> \
  --slot staging --action preview

# If preview succeeds, complete swap
az webapp deployment slot swap \
  --name <app> --resource-group <rg> \
  --slot staging --action swap
```

## Network Connectivity Issues

### Can't Access Backend Services

```bash
# From Kudu console - test connectivity
tcpping <hostname>:<port>
nameresolver <hostname>

# Check VNet integration
az webapp vnet-integration list --name <app> --resource-group <rg>

# Verify NSG rules allow traffic
az network nsg rule list --nsg-name <nsg> --resource-group <rg>
```

### DNS Resolution Fails

```bash
# Check from Kudu console
nameresolver <hostname>

# For private endpoints, verify DNS zone linked
az network private-dns link vnet list \
  --zone-name privatelink.database.windows.net \
  --resource-group <rg>
```

## Kudu Diagnostic Tools

Access Kudu at: `https://<app>.scm.azurewebsites.net`

| Tool | URL | Use Case |
|------|-----|----------|
| Process Explorer | `/ProcessExplorer` | Memory, CPU, threads |
| Log Stream | `/api/logstream` | Real-time logs |
| Debug Console | `/DebugConsole` | File system, commands |
| Environment | `/Env` | App settings, variables |
| Site Extensions | `/SiteExtensions` | Install diagnostics |

### Useful Kudu Commands

```bash
# List processes
ps

# Network test
tcpping <host>:<port>
nameresolver <hostname>

# Check disk space
df -h

# View environment variables
printenv
```

## Auto-Heal Configuration

Automatically restart app based on conditions:

```bash
# Enable auto-heal via REST API or Portal
# Triggers: slow requests, HTTP errors, memory limit
```

**Example auto-heal rules (via ARM template):**
```json
{
  "autoHealEnabled": true,
  "autoHealRules": {
    "triggers": {
      "slowRequests": {
        "timeTaken": "00:00:30",
        "count": 10,
        "timeInterval": "00:02:00"
      },
      "statusCodes": [
        {
          "status": 500,
          "count": 10,
          "timeInterval": "00:02:00"
        }
      ]
    },
    "actions": {
      "actionType": "Recycle",
      "minProcessExecutionTime": "00:05:00"
    }
  }
}
```

## Common Issues Quick Reference

| Issue | Likely Cause | Quick Fix |
|-------|--------------|-----------|
| 500 errors | App exception | Check logs, fix code |
| App not starting | Wrong runtime/startup | Verify config, set startup command |
| Slow performance | Under-provisioned | Scale up, enable Always On |
| Deployment fails | Bad package structure | Verify ZIP, check logs |
| Can't connect to DB | Network/config | Check VNet integration, connection string |
| Cold starts | Always On disabled | Enable Always On (Basic+) |
| Out of memory | Memory leak or undersized | Scale up, profile app |
| SSL errors | Certificate issue | Check binding, verify hostname |

## References

- **KQL Queries**: See [references/diagnostic-queries.md](references/diagnostic-queries.md)
- **Auto-Heal Patterns**: See [references/auto-heal.md](references/auto-heal.md)
