# Troubleshooting Runbooks

## HTTP 5xx Error Runbook

### Step 1: Identify Error Type

```bash
# Check recent HTTP logs
az monitor activity-log list \
  --resource-group <rg> \
  --resource-type Microsoft.Web/sites \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
```

### Step 2: Check Application Logs

**Via Azure Portal:**
1. App Service → Diagnose and Solve Problems
2. Select "Availability and Performance"
3. Review HTTP Server Errors

**Via Kudu Console:**
```bash
# Access: https://<app-name>.scm.azurewebsites.net/DebugConsole

# View log files
cd /home/LogFiles

# Application stderr (Linux)
cat /home/LogFiles/stderr.log

# Windows detailed errors
cat /home/LogFiles/DetailedErrors/*.htm
```

### Step 3: Enable Detailed Logging

```bash
# Enable application logging
az webapp log config \
  --name <app-name> \
  --resource-group <rg> \
  --application-logging filesystem \
  --detailed-error-messages true \
  --failed-request-tracing true \
  --level verbose

# Stream logs
az webapp log tail --name <app-name> --resource-group <rg>
```

### Step 4: Resolution by Error Code

| Error | Common Cause | Resolution |
|-------|--------------|------------|
| 500 | Unhandled exception | Check application logs, fix code |
| 502 | Backend timeout | Increase timeout, check dependencies |
| 503 | App overloaded/starting | Scale up/out, check Always On |
| 504 | Gateway timeout | Check slow dependencies, optimize code |

---

## Application Startup Failure Runbook

### Step 1: Check Startup Logs

```bash
# View container logs (Linux)
az webapp log download \
  --name <app-name> \
  --resource-group <rg>

# Check docker logs
cat /home/LogFiles/docker/*.log
```

### Step 2: Verify Configuration

```bash
# Check startup command
az webapp config show \
  --name <app-name> \
  --resource-group <rg> \
  --query "linuxFxVersion"

# Check app settings
az webapp config appsettings list \
  --name <app-name> \
  --resource-group <rg>
```

### Step 3: Common Startup Issues

| Issue | Symptom | Resolution |
|-------|---------|------------|
| Missing dependency | Module not found | Check requirements.txt/package.json |
| Wrong startup command | Container exits immediately | Fix startup command |
| Port binding | App not responding | Listen on `$PORT` or 8080 |
| Memory exceeded | OOM killed | Scale up SKU |
| Permission denied | Cannot execute | Check file permissions |

### Step 4: Test Locally

```bash
# Build and test container locally
docker build -t myapp .
docker run -p 8080:8080 -e PORT=8080 myapp
```

---

## Performance Degradation Runbook

### Step 1: Check Resource Metrics

```bash
# Check CPU and memory
az monitor metrics list \
  --resource <app-service-plan-id> \
  --metric "CpuPercentage" "MemoryPercentage" \
  --interval PT5M \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
```

### Step 2: Identify Slow Requests

**Application Insights KQL:**
```kql
requests
| where timestamp > ago(1h)
| where duration > 2000
| summarize count(), avg(duration) by name
| order by avg_duration desc
```

### Step 3: Check Dependencies

```kql
dependencies
| where timestamp > ago(1h)
| summarize 
    avg(duration), 
    percentile(duration, 95),
    count()
    by target, type
| order by avg_duration desc
```

### Step 4: Resolution Actions

| Cause | Resolution |
|-------|------------|
| High CPU | Scale up or out |
| High memory | Increase SKU, check for leaks |
| Slow database | Optimize queries, add caching |
| Slow external API | Add caching, increase timeouts |
| Thread starvation | Use async patterns |

---

## Connectivity Failure Runbook

### Step 1: Diagnose Target

```bash
# From Kudu console
tcpping <target-host>:<port>
nameserver
nslookup <target-host>
```

### Step 2: Check VNet Configuration

```bash
# Verify VNet integration
az webapp vnet-integration list \
  --name <app-name> \
  --resource-group <rg>

# Check route configuration
az webapp config appsettings list \
  --name <app-name> \
  --resource-group <rg> \
  --query "[?name=='WEBSITE_VNET_ROUTE_ALL']"
```

### Step 3: Check NSG Rules

```bash
az network nsg rule list \
  --nsg-name <nsg-name> \
  --resource-group <rg> \
  --output table
```

### Step 4: Resolution by Target

| Target | Check | Resolution |
|--------|-------|------------|
| Azure SQL | Firewall rules, AAD auth | Add App Service IP or VNet |
| Storage | Firewall, private endpoint | Configure network rules |
| External API | Egress IPs, NAT gateway | Whitelist outbound IPs |
| On-premises | VPN/ExpressRoute, DNS | Check hybrid connectivity |

---

## Memory/CPU High Usage Runbook

### Step 1: Identify the Cause

```bash
# Check process list (from Kudu)
# Windows: Process Explorer in Kudu
# Linux: 
top -b -n 1
ps aux --sort=-%mem | head -20
```

### Step 2: Profile the Application

**For .NET:**
```bash
# Enable profiling
az webapp config appsettings set \
  --name <app-name> \
  --resource-group <rg> \
  --settings COR_ENABLE_PROFILING=1 \
             COR_PROFILER={324F817A-7420-4E6D-B3C1-143FBED6D855}
```

**For Node.js:**
```javascript
// Add to app
const v8 = require('v8');
console.log(v8.getHeapStatistics());
```

### Step 3: Enable Auto-Heal

```bash
# Auto-heal on high memory
az webapp config set \
  --name <app-name> \
  --resource-group <rg> \
  --auto-heal-enabled true

# Configure auto-heal rules (see auto-heal reference)
```

### Step 4: Resolution Actions

| Issue | Resolution |
|-------|------------|
| Memory leak | Profile app, fix leak, restart regularly |
| CPU spike | Optimize code, scale out |
| Too many requests | Add caching, scale out |
| Large payloads | Stream responses, paginate |

---

## Deployment Failure Runbook

### Step 1: Check Deployment Logs

```bash
# View deployment history
az webapp deployment list-publishing-profiles \
  --name <app-name> \
  --resource-group <rg>

# Check Kudu deployment logs
# https://<app-name>.scm.azurewebsites.net/api/deployments
```

### Step 2: Common Deployment Issues

| Error | Cause | Resolution |
|-------|-------|------------|
| `WEBSITE_RUN_FROM_PACKAGE` failed | Package URL invalid | Check SAS token, URL |
| Build failed | Missing dependencies | Check build logs |
| Timeout | Large package | Increase timeout, optimize package |
| Permission denied | Locked files | Stop app before deploy |

### Step 3: Verify Post-Deployment

```bash
# Check app is running
az webapp show \
  --name <app-name> \
  --resource-group <rg> \
  --query "state"

# Check health endpoint
curl -I https://<app-name>.azurewebsites.net/health
```

---

## Certificate Expiration Runbook

### Step 1: Check Certificate Status

```bash
# List certificates
az webapp config ssl list \
  --resource-group <rg> \
  --query "[].{name:name, expiration:expirationDate, thumbprint:thumbprint}"
```

### Step 2: Renew Certificate

**App Service Managed Certificate:**
```bash
# Managed certificates auto-renew
# If stuck, delete and recreate
az webapp config ssl delete \
  --certificate-thumbprint <thumbprint> \
  --resource-group <rg>

az webapp config ssl create \
  --name <app-name> \
  --resource-group <rg> \
  --hostname <hostname>
```

**Custom Certificate:**
```bash
# Upload new certificate
az webapp config ssl upload \
  --name <app-name> \
  --resource-group <rg> \
  --certificate-file ./new-cert.pfx \
  --certificate-password <password>

# Bind to hostname
az webapp config ssl bind \
  --name <app-name> \
  --resource-group <rg> \
  --certificate-thumbprint <new-thumbprint> \
  --ssl-type SNI
```

### Step 3: Set Up Alerting

```bash
# Create alert for certificate expiring
az monitor metrics alert create \
  --name "Cert-Expiring-Soon" \
  --resource-group <rg> \
  --scopes <app-service-resource-id> \
  --condition "avg CertificateExpirationDate < 30" \
  --window-size 1d \
  --action-group <action-group-id>
```

---

## Quick Diagnostic Commands

```bash
# Overall health check
az webapp show --name <app> --resource-group <rg> --query "{state:state, enabled:enabled, availability:availabilityState}"

# Recent errors (App Insights)
az monitor app-insights query \
  --app <app-insights-id> \
  --analytics-query "exceptions | where timestamp > ago(1h) | summarize count() by type"

# Check outbound IPs
az webapp show --name <app> --resource-group <rg> --query "outboundIpAddresses"

# Restart app
az webapp restart --name <app> --resource-group <rg>

# View live logs
az webapp log tail --name <app> --resource-group <rg>
```
