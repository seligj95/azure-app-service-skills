# Alert Configuration Templates

## Metric Alert Rules

### HTTP Server Errors (5xx)

```bash
az monitor metrics alert create \
  --name "AppService-HTTP-5xx-Errors" \
  --resource-group <rg> \
  --scopes <app-service-resource-id> \
  --condition "total Http5xx > 10" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2 \
  --action-group <action-group-id> \
  --description "Alert when HTTP 5xx errors exceed threshold"
```

### High Response Time

```bash
az monitor metrics alert create \
  --name "AppService-High-Response-Time" \
  --resource-group <rg> \
  --scopes <app-service-resource-id> \
  --condition "avg AverageResponseTime > 2000" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2 \
  --action-group <action-group-id> \
  --description "Alert when average response time exceeds 2 seconds"
```

### High CPU

```bash
az monitor metrics alert create \
  --name "AppService-High-CPU" \
  --resource-group <rg> \
  --scopes <app-service-plan-resource-id> \
  --condition "avg CpuPercentage > 80" \
  --window-size 10m \
  --evaluation-frequency 5m \
  --severity 2 \
  --action-group <action-group-id> \
  --description "Alert when CPU exceeds 80%"
```

### High Memory

```bash
az monitor metrics alert create \
  --name "AppService-High-Memory" \
  --resource-group <rg> \
  --scopes <app-service-plan-resource-id> \
  --condition "avg MemoryPercentage > 85" \
  --window-size 10m \
  --evaluation-frequency 5m \
  --severity 2 \
  --action-group <action-group-id> \
  --description "Alert when memory exceeds 85%"
```

### Health Check Failures

```bash
az monitor metrics alert create \
  --name "AppService-Health-Check-Failed" \
  --resource-group <rg> \
  --scopes <app-service-resource-id> \
  --condition "total HealthCheckStatus < 100" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 1 \
  --action-group <action-group-id> \
  --description "Alert when health check fails"
```

## Log-Based Alerts

### Application Insights - High Error Rate

```bash
az monitor scheduled-query create \
  --name "AppInsights-High-Error-Rate" \
  --resource-group <rg> \
  --scopes <app-insights-resource-id> \
  --condition-query "
    requests
    | where timestamp > ago(5m)
    | summarize total = count(), failed = countif(success == false)
    | extend errorRate = 100.0 * failed / total
    | where errorRate > 5
  " \
  --condition "count > 0" \
  --severity 2 \
  --evaluation-frequency 5m \
  --window-size 5m \
  --action-groups <action-group-id> \
  --description "Alert when error rate exceeds 5%"
```

### Exception Spike

```bash
az monitor scheduled-query create \
  --name "AppInsights-Exception-Spike" \
  --resource-group <rg> \
  --scopes <app-insights-resource-id> \
  --condition-query "
    exceptions
    | where timestamp > ago(5m)
    | summarize count()
  " \
  --condition "count > 50" \
  --severity 2 \
  --evaluation-frequency 5m \
  --window-size 5m \
  --action-groups <action-group-id> \
  --description "Alert on exception spike"
```

### Slow Dependency Calls

```bash
az monitor scheduled-query create \
  --name "AppInsights-Slow-Dependencies" \
  --resource-group <rg> \
  --scopes <app-insights-resource-id> \
  --condition-query "
    dependencies
    | where timestamp > ago(5m)
    | where duration > 5000
    | summarize count()
  " \
  --condition "count > 10" \
  --severity 3 \
  --evaluation-frequency 5m \
  --window-size 5m \
  --action-groups <action-group-id> \
  --description "Alert when dependencies are slow"
```

## Action Group Setup

### Create Action Group with Email and Webhook

```bash
az monitor action-group create \
  --name "AppService-Alerts" \
  --resource-group <rg> \
  --short-name "AppSvcAlert" \
  --email-receiver name="oncall" email="oncall@example.com" \
  --webhook-receiver name="slack" uri="https://hooks.slack.com/services/..."
```

### Action Group with Azure Function

```bash
az monitor action-group create \
  --name "AppService-Alerts-Advanced" \
  --resource-group <rg> \
  --short-name "AppSvcAdv" \
  --azure-function-receiver \
    name="alert-processor" \
    function-app-resource-id=<function-app-id> \
    function-name="ProcessAlert" \
    http-trigger-url=<function-trigger-url>
```

## Recommended Alert Strategy

### Critical (Severity 0-1)
| Alert | Threshold | Window | Action |
|-------|-----------|--------|--------|
| Health Check Failed | Any failure | 5m | Page on-call |
| HTTP 5xx Spike | >50 errors | 5m | Page on-call |
| App Stopped | Status = Stopped | 1m | Page on-call |

### Warning (Severity 2)
| Alert | Threshold | Window | Action |
|-------|-----------|--------|--------|
| High Error Rate | >5% | 5m | Notify team |
| High Response Time | p95 >2s | 5m | Notify team |
| High CPU | >80% | 10m | Notify team |
| High Memory | >85% | 10m | Notify team |

### Informational (Severity 3-4)
| Alert | Threshold | Window | Action |
|-------|-----------|--------|--------|
| Deployment Completed | Any | - | Log |
| Scaling Event | Any | - | Log |
| Certificate Expiring | <30 days | Daily | Notify team |

## Availability Test Alerts

### Create Availability Test

```bash
# Via Azure Portal or ARM template - CLI support is limited
# Use this ARM template snippet:
```

```json
{
  "type": "Microsoft.Insights/webtests",
  "apiVersion": "2022-06-15",
  "name": "availability-test",
  "location": "eastus",
  "properties": {
    "SyntheticMonitorId": "availability-test",
    "Name": "Homepage Availability",
    "Enabled": true,
    "Frequency": 300,
    "Timeout": 30,
    "Kind": "ping",
    "Locations": [
      {"Id": "us-va-ash-azr"},
      {"Id": "us-ca-sjc-azr"},
      {"Id": "emea-gb-db3-azr"}
    ],
    "Configuration": {
      "WebTest": "<WebTest Name=\"Homepage\" Url=\"https://your-app.azurewebsites.net/health\" />"
    }
  }
}
```

### Alert on Availability Test Failure

```bash
az monitor metrics alert create \
  --name "Availability-Test-Failed" \
  --resource-group <rg> \
  --scopes <availability-test-resource-id> \
  --condition "avg availabilityResults/availabilityPercentage < 100" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 1 \
  --action-group <action-group-id> \
  --description "Alert when availability test fails"
```

## Smart Detection (Automatic)

Application Insights automatically detects:
- Failure anomalies (sudden increase in failed requests)
- Performance anomalies (degraded response times)
- Memory leak detection
- Exception anomalies

Configure notifications:
1. Application Insights → Smart Detection
2. Configure email recipients for each detection type
