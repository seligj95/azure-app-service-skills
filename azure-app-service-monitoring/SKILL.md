---
name: azure-app-service-monitoring
description: Monitor Azure App Service applications with Application Insights, Log Analytics, alerts, and diagnostics. Use when setting up APM, configuring alerts, analyzing logs, creating dashboards, troubleshooting performance issues, or implementing availability tests.
---

## When to Apply

Reference these guidelines when:

- Setting up Application Insights for App Service
- Creating alerts for errors, performance, or availability
- Analyzing application logs and metrics
- Building monitoring dashboards
- Troubleshooting performance issues
- Configuring availability tests

## Monitoring Stack

```
Application Insights ─── APM, traces, dependencies, exceptions
        │
Log Analytics ───────── Centralized log queries (KQL)
        │
Azure Monitor ───────── Metrics, alerts, dashboards
        │
Diagnostic Settings ─── Route logs to storage/Event Hubs
```

## Application Insights Setup

### Enable via CLI

```bash
# Create Application Insights resource
az monitor app-insights component create \
  --app <app-insights-name> \
  --location <region> \
  --resource-group <rg> \
  --application-type web

# Get connection string
az monitor app-insights component show \
  --app <app-insights-name> \
  --resource-group <rg> \
  --query connectionString -o tsv

# Configure App Service with App Insights
az webapp config appsettings set \
  --name <app> --resource-group <rg> \
  --settings APPLICATIONINSIGHTS_CONNECTION_STRING="<connection-string>" \
             ApplicationInsightsAgent_EXTENSION_VERSION="~3"
```

### Auto-Instrumentation (Codeless)

For supported runtimes, enable without code changes:

| Runtime | Extension Setting |
|---------|-------------------|
| .NET | `ApplicationInsightsAgent_EXTENSION_VERSION=~3` |
| Node.js | `ApplicationInsightsAgent_EXTENSION_VERSION=~3` |
| Java | `ApplicationInsightsAgent_EXTENSION_VERSION=~3` |
| Python | Requires SDK (no codeless support) |

## Key Metrics to Monitor

### Platform Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `Http5xx` | Server errors | > 5 per 5 min |
| `Http4xx` | Client errors | > 100 per 5 min |
| `ResponseTime` | Average response time | > 2000ms |
| `CpuPercentage` | CPU usage | > 80% for 5 min |
| `MemoryPercentage` | Memory usage | > 80% for 5 min |
| `HealthCheckStatus` | Health check failures | < 100% |

### Application Insights Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `requests/failed` | Failed requests | > 1% error rate |
| `requests/duration` | Request duration | P95 > 3s |
| `exceptions/count` | Unhandled exceptions | > 10 per 5 min |
| `dependencies/failed` | Failed dependencies | > 5 per 5 min |
| `availabilityResults/availabilityPercentage` | Availability | < 99% |

## Alerts Configuration

### Create Metric Alert

```bash
# Alert on HTTP 5xx errors
az monitor metrics alert create \
  --name "High-5xx-Errors" \
  --resource-group <rg> \
  --scopes "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Web/sites/<app>" \
  --condition "total Http5xx > 5" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action <action-group-id> \
  --severity 2

# Alert on high response time
az monitor metrics alert create \
  --name "High-Response-Time" \
  --resource-group <rg> \
  --scopes "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Web/sites/<app>" \
  --condition "avg ResponseTime > 2000" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action <action-group-id> \
  --severity 3

# Alert on high CPU
az monitor metrics alert create \
  --name "High-CPU" \
  --resource-group <rg> \
  --scopes "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Web/serverfarms/<plan>" \
  --condition "avg CpuPercentage > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action <action-group-id> \
  --severity 2
```

### Create Action Group

```bash
az monitor action-group create \
  --name "AppServiceAlerts" \
  --resource-group <rg> \
  --short-name "AppSvcAlert" \
  --email-receiver name="Team" email="team@example.com" \
  --webhook-receiver name="Slack" uri="https://hooks.slack.com/..."
```

## Log Analytics Queries (KQL)

### Enable Diagnostic Settings

```bash
# Send App Service logs to Log Analytics
az monitor diagnostic-settings create \
  --name "app-diagnostics" \
  --resource "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Web/sites/<app>" \
  --workspace <log-analytics-workspace-id> \
  --logs '[
    {"category": "AppServiceHTTPLogs", "enabled": true},
    {"category": "AppServiceConsoleLogs", "enabled": true},
    {"category": "AppServiceAppLogs", "enabled": true},
    {"category": "AppServicePlatformLogs", "enabled": true}
  ]'
```

### Common KQL Queries

#### HTTP Errors Analysis

```kql
AppServiceHTTPLogs
| where TimeGenerated > ago(24h)
| where ScStatus >= 500
| summarize ErrorCount = count() by bin(TimeGenerated, 1h), CsUriStem
| order by ErrorCount desc
```

#### Slow Requests

```kql
AppServiceHTTPLogs
| where TimeGenerated > ago(1h)
| where TimeTaken > 5000
| project TimeGenerated, CsUriStem, TimeTaken, ScStatus, CIp
| order by TimeTaken desc
| take 100
```

#### Exception Analysis (Application Insights)

```kql
exceptions
| where timestamp > ago(24h)
| summarize Count = count() by type, outerMessage
| order by Count desc
| take 20
```

#### Request Performance Percentiles

```kql
requests
| where timestamp > ago(1h)
| summarize 
    P50 = percentile(duration, 50),
    P90 = percentile(duration, 90),
    P95 = percentile(duration, 95),
    P99 = percentile(duration, 99)
    by bin(timestamp, 5m)
| render timechart
```

#### Dependency Failures

```kql
dependencies
| where timestamp > ago(1h)
| where success == false
| summarize FailureCount = count() by target, type, resultCode
| order by FailureCount desc
```

#### App Service Instance Health

```kql
AppServiceHTTPLogs
| where TimeGenerated > ago(1h)
| summarize 
    RequestCount = count(),
    ErrorCount = countif(ScStatus >= 500),
    AvgDuration = avg(TimeTaken)
    by ComputerName
| extend ErrorRate = round(100.0 * ErrorCount / RequestCount, 2)
```

## Availability Tests

### Create URL Ping Test

```bash
# Create availability test
az monitor app-insights web-test create \
  --resource-group <rg> \
  --app-insights <app-insights-name> \
  --name "Homepage-Availability" \
  --web-test-kind "ping" \
  --locations "us-va-ash-azr" "emea-nl-ams-azr" "apac-sg-sin-azr" \
  --frequency 300 \
  --timeout 120 \
  --enabled true \
  --defined-web-test-name "Homepage" \
  --request-url "https://<app>.azurewebsites.net/health"
```

### Multi-Step Test (Standard Test)

```bash
# Create standard test with multiple validations
az monitor app-insights web-test create \
  --resource-group <rg> \
  --app-insights <app-insights-name> \
  --name "API-Health-Check" \
  --web-test-kind "standard" \
  --locations "us-va-ash-azr" "emea-nl-ams-azr" \
  --frequency 300 \
  --timeout 30 \
  --enabled true \
  --http-verb "GET" \
  --request-url "https://<app>.azurewebsites.net/api/health" \
  --expected-status-code 200 \
  --content-match "healthy"
```

## Health Check Configuration

```bash
# Configure health check path
az webapp config set \
  --name <app> --resource-group <rg> \
  --generic-configurations '{"healthCheckPath": "/health"}'

# View health check status
az webapp show \
  --name <app> --resource-group <rg> \
  --query "siteConfig.healthCheckPath"
```

**Health Check Behavior:**
- Probed every 1 minute per instance
- Instance marked unhealthy after 10 consecutive failures
- Unhealthy instances removed from load balancer (2+ instances)
- 1 hour before unhealthy instance replaced

## Live Metrics & Debugging

```bash
# Stream live logs
az webapp log tail --name <app> --resource-group <rg>

# Enable application logging
az webapp log config \
  --name <app> --resource-group <rg> \
  --application-logging filesystem \
  --level verbose

# Download logs
az webapp log download \
  --name <app> --resource-group <rg> \
  --log-file ./logs.zip
```

## Recommended Alert Set

| Alert | Condition | Severity |
|-------|-----------|----------|
| High Error Rate | Http5xx > 5 in 5 min | Sev 2 |
| High Latency | ResponseTime avg > 3s | Sev 3 |
| Health Check Failed | HealthCheckStatus < 100% | Sev 1 |
| High CPU | CpuPercentage > 85% for 5 min | Sev 2 |
| High Memory | MemoryPercentage > 85% for 5 min | Sev 2 |
| Availability Down | availabilityPercentage < 99% | Sev 1 |

## References

- **KQL Queries**: See [references/kql-queries.md](references/kql-queries.md) for more query examples
- **Dashboard Templates**: See [references/dashboards.md](references/dashboards.md) for Azure Dashboard JSON templates
