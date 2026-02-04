# KQL Queries for App Service Monitoring

## Application Insights Queries

### Request Performance Analysis

```kql
// Request duration percentiles over time
requests
| where timestamp > ago(24h)
| summarize 
    p50 = percentile(duration, 50),
    p90 = percentile(duration, 90),
    p95 = percentile(duration, 95),
    p99 = percentile(duration, 99)
    by bin(timestamp, 5m)
| render timechart
```

```kql
// Slowest endpoints
requests
| where timestamp > ago(1h)
| summarize 
    avgDuration = avg(duration),
    p95Duration = percentile(duration, 95),
    count = count()
    by name
| where count > 10
| order by p95Duration desc
| take 20
```

```kql
// Failed requests by endpoint
requests
| where timestamp > ago(1h)
| where success == false
| summarize failedCount = count() by name, resultCode
| order by failedCount desc
```

### Error Analysis

```kql
// Exceptions over time
exceptions
| where timestamp > ago(24h)
| summarize count() by bin(timestamp, 15m), type
| render timechart
```

```kql
// Top exceptions with stack traces
exceptions
| where timestamp > ago(1h)
| summarize count() by type, outerMessage
| order by count_ desc
| take 10
```

```kql
// Exception details for investigation
exceptions
| where timestamp > ago(1h)
| where type == "System.NullReferenceException"  // replace with actual type
| project timestamp, outerMessage, innermostMessage, details
| take 50
```

### Dependency Performance

```kql
// Slow external dependencies
dependencies
| where timestamp > ago(1h)
| summarize 
    avgDuration = avg(duration),
    p95Duration = percentile(duration, 95),
    failRate = 100.0 * countif(success == false) / count()
    by target, type
| order by p95Duration desc
```

```kql
// Database query performance
dependencies
| where timestamp > ago(1h)
| where type == "SQL"
| summarize 
    avgDuration = avg(duration),
    count = count()
    by data  // SQL query text
| order by avgDuration desc
| take 20
```

```kql
// Failed dependencies
dependencies
| where timestamp > ago(1h)
| where success == false
| summarize count() by target, type, resultCode
| order by count_ desc
```

### User Analytics

```kql
// Active users by hour
pageViews
| where timestamp > ago(24h)
| summarize users = dcount(user_Id) by bin(timestamp, 1h)
| render timechart
```

```kql
// Page load times
pageViews
| where timestamp > ago(4h)
| summarize 
    avgLoad = avg(duration),
    p95Load = percentile(duration, 95)
    by name
| order by p95Load desc
```

### Availability and Health

```kql
// Availability test results
availabilityResults
| where timestamp > ago(24h)
| summarize 
    successRate = 100.0 * countif(success == true) / count(),
    avgDuration = avg(duration)
    by name, location
| order by successRate asc
```

```kql
// Health check failures
requests
| where timestamp > ago(1h)
| where name endswith "/health" or name endswith "/healthz"
| summarize 
    healthyCount = countif(success == true),
    unhealthyCount = countif(success == false)
    by bin(timestamp, 5m)
| extend healthRate = 100.0 * healthyCount / (healthyCount + unhealthyCount)
| render timechart
```

## Azure Monitor / Log Analytics Queries

### App Service Platform Logs

```kql
// HTTP server errors (5xx)
AppServiceHTTPLogs
| where TimeGenerated > ago(1h)
| where ScStatus >= 500
| summarize count() by ScStatus, CsUriStem
| order by count_ desc
```

```kql
// Response time analysis
AppServiceHTTPLogs
| where TimeGenerated > ago(24h)
| summarize 
    p50 = percentile(TimeTaken, 50),
    p90 = percentile(TimeTaken, 90),
    p99 = percentile(TimeTaken, 99)
    by bin(TimeGenerated, 15m)
| render timechart
```

```kql
// Request volume by status code
AppServiceHTTPLogs
| where TimeGenerated > ago(24h)
| summarize count() by ScStatus, bin(TimeGenerated, 1h)
| render columnchart
```

### Platform Errors

```kql
// App Service platform errors
AppServicePlatformLogs
| where TimeGenerated > ago(24h)
| where Level == "Error" or Level == "Warning"
| project TimeGenerated, Level, Message
| order by TimeGenerated desc
```

```kql
// Console/stdout logs
AppServiceConsoleLogs
| where TimeGenerated > ago(1h)
| where ResultDescription contains "error" or ResultDescription contains "exception"
| project TimeGenerated, ResultDescription
| order by TimeGenerated desc
```

### Resource Metrics

```kql
// CPU and memory usage
AzureMetrics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.WEB"
| where MetricName in ("CpuPercentage", "MemoryPercentage")
| summarize avg(Average) by MetricName, bin(TimeGenerated, 15m)
| render timechart
```

```kql
// Request count and response time
AzureMetrics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.WEB"
| where MetricName in ("Requests", "AverageResponseTime")
| summarize avg(Average) by MetricName, bin(TimeGenerated, 15m)
| render timechart
```

### Deployment Events

```kql
// Recent deployments
AppServiceAuditLogs
| where TimeGenerated > ago(7d)
| where OperationName contains "Deploy"
| project TimeGenerated, OperationName, User, Description
| order by TimeGenerated desc
```

## Alert Query Examples

### High Error Rate

```kql
requests
| where timestamp > ago(5m)
| summarize 
    total = count(),
    failed = countif(success == false)
| extend errorRate = 100.0 * failed / total
| where errorRate > 5  // Alert if >5% error rate
```

### Slow Response Time

```kql
requests
| where timestamp > ago(5m)
| summarize p95Duration = percentile(duration, 95)
| where p95Duration > 2000  // Alert if p95 > 2 seconds
```

### Memory Pressure

```kql
AzureMetrics
| where TimeGenerated > ago(10m)
| where MetricName == "MemoryPercentage"
| summarize avgMemory = avg(Average)
| where avgMemory > 85  // Alert if memory > 85%
```

## Dashboard Queries

### Overview Tile

```kql
requests
| where timestamp > ago(1h)
| summarize 
    Requests = count(),
    Failed = countif(success == false),
    AvgDuration = avg(duration)
| extend SuccessRate = round(100.0 * (Requests - Failed) / Requests, 2)
```

### Traffic by Geography

```kql
requests
| where timestamp > ago(24h)
| summarize count() by client_CountryOrRegion
| order by count_ desc
| take 10
| render piechart
```
