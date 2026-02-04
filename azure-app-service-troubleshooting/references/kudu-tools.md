# Kudu Diagnostic Tools Reference

Kudu is the deployment and diagnostic engine for Azure App Service.

**Access URL**: `https://<app-name>.scm.azurewebsites.net`

## Debug Console

Access: Kudu → Debug console → CMD or Bash

### Useful Commands

```bash
# View running processes
ps aux

# Check memory usage
free -m

# View disk usage
df -h

# Check environment variables
env | sort

# View network connections
netstat -tulpn

# DNS resolution
nslookup <hostname>

# TCP connectivity test
tcpping <host>:<port>

# HTTP request test
curl -v https://api.example.com/health
```

### File System Locations

| Path | Description |
|------|-------------|
| `/home` | Persistent storage (survives restarts/scale) |
| `/home/site/wwwroot` | Application code |
| `/home/site/deployments` | Deployment history |
| `/home/LogFiles` | Application and platform logs |
| `/home/data` | Application data |
| `/tmp` | Temporary files (not persistent) |

## REST APIs

### Deployment API

```bash
# List deployments
curl https://<app>.scm.azurewebsites.net/api/deployments \
  -u <username>:<password>

# Get deployment log
curl https://<app>.scm.azurewebsites.net/api/deployments/<id>/log \
  -u <username>:<password>

# Trigger deployment from zip
curl -X POST https://<app>.scm.azurewebsites.net/api/zipdeploy \
  -u <username>:<password> \
  -H "Content-Type: application/zip" \
  --data-binary @app.zip
```

### Process API

```bash
# List all processes
curl https://<app>.scm.azurewebsites.net/api/processes \
  -u <username>:<password>

# Get process details
curl https://<app>.scm.azurewebsites.net/api/processes/<id> \
  -u <username>:<password>

# Get process dump (Windows)
curl https://<app>.scm.azurewebsites.net/api/processes/<id>/dump \
  -u <username>:<password> > dump.dmp
```

### VFS (Virtual File System) API

```bash
# List directory
curl https://<app>.scm.azurewebsites.net/api/vfs/site/wwwroot/ \
  -u <username>:<password>

# Download file
curl https://<app>.scm.azurewebsites.net/api/vfs/site/wwwroot/web.config \
  -u <username>:<password>

# Upload file
curl -X PUT https://<app>.scm.azurewebsites.net/api/vfs/site/wwwroot/newfile.txt \
  -u <username>:<password> \
  -H "Content-Type: text/plain" \
  --data "file contents"
```

### Environment Info

```bash
# Get environment info
curl https://<app>.scm.azurewebsites.net/api/environment \
  -u <username>:<password>

# Get settings
curl https://<app>.scm.azurewebsites.net/api/settings \
  -u <username>:<password>
```

## Log Files

### Access via Kudu Console

```bash
cd /home/LogFiles

# Application logs
cat /home/LogFiles/Application/*.txt

# HTTP logs
cat /home/LogFiles/http/RawLogs/*.log

# Docker/container logs (Linux)
cat /home/LogFiles/docker/*.log

# Detailed error logs (Windows)
cat /home/LogFiles/DetailedErrors/*.htm

# Deployment logs
cat /home/LogFiles/Git/trace/*.txt
```

### Log File Types

| Log Type | Path | Content |
|----------|------|---------|
| Application | `/home/LogFiles/Application/` | App stdout/stderr |
| HTTP | `/home/LogFiles/http/RawLogs/` | IIS/nginx logs |
| Docker | `/home/LogFiles/docker/` | Container logs |
| Deployment | `/home/LogFiles/Git/` | Git deployment logs |
| Kudu | `/home/LogFiles/kudu/` | Kudu process logs |

### Download Logs via API

```bash
# Download all logs as zip
curl https://<app>.scm.azurewebsites.net/api/dump \
  -u <username>:<password> > logs.zip

# Download specific logs
curl https://<app>.scm.azurewebsites.net/api/vfs/LogFiles/Application/ \
  -u <username>:<password>
```

## Process Explorer (Windows)

Access: Kudu → Process Explorer

Features:
- View all running processes (w3wp, node, dotnet, etc.)
- See CPU, memory, handles per process
- Generate memory dumps
- View threads and modules
- Kill processes

### Generate Memory Dump

```bash
# Via API
curl -X POST https://<app>.scm.azurewebsites.net/api/processes/0/dump?dumpType=2 \
  -u <username>:<password> > fulldump.dmp
```

Dump types:
- `0` = Mini dump
- `1` = Mini dump with heap
- `2` = Full dump

## Environment Variables

### View via Console

```bash
# All environment variables
env

# Specific variable
echo $WEBSITE_SITE_NAME
echo $WEBSITE_INSTANCE_ID
```

### Useful Environment Variables

| Variable | Description |
|----------|-------------|
| `WEBSITE_SITE_NAME` | App name |
| `WEBSITE_INSTANCE_ID` | Instance identifier |
| `WEBSITE_HOSTNAME` | Default hostname |
| `WEBSITE_RESOURCE_GROUP` | Resource group |
| `WEBSITES_PORT` | Port app should listen on |
| `IDENTITY_ENDPOINT` | Managed Identity endpoint |
| `IDENTITY_HEADER` | Managed Identity header |

## Network Diagnostics

### From Kudu Console

```bash
# TCP ping (test connectivity)
tcpping sql-server.database.windows.net:1433

# DNS lookup
nslookup storage-account.blob.core.windows.net

# HTTP request
curl -v -H "Host: myapp.azurewebsites.net" http://localhost/health

# Check outbound IP
curl https://ipinfo.io/ip
```

### VNet Integration Check

```bash
# Verify VNet connectivity
curl https://<app>.scm.azurewebsites.net/api/vnetcheck

# Test DNS from VNet-integrated app
nslookup <private-resource>.privatelink.database.windows.net
```

## Site Extensions (Windows)

### Install via Kudu

```bash
# List installed extensions
curl https://<app>.scm.azurewebsites.net/api/siteextensions \
  -u <username>:<password>

# Install extension
curl -X PUT https://<app>.scm.azurewebsites.net/api/siteextensions/<extension-id> \
  -u <username>:<password>
```

### Useful Extensions

| Extension | Purpose |
|-----------|---------|
| Application Insights Profiler | Performance profiling |
| Snapshot Debugger | Production debugging |
| PHP Manager | PHP configuration |
| Log Browser | Enhanced log viewing |

## Diagnostic Tools URL Summary

| Tool | URL |
|------|-----|
| Kudu Home | `https://<app>.scm.azurewebsites.net` |
| Debug Console | `https://<app>.scm.azurewebsites.net/DebugConsole` |
| Process Explorer | `https://<app>.scm.azurewebsites.net/ProcessExplorer` |
| Environment | `https://<app>.scm.azurewebsites.net/Env` |
| REST API | `https://<app>.scm.azurewebsites.net/api/...` |
| Log Stream | `https://<app>.scm.azurewebsites.net/api/logstream` |

## Authentication

### Basic Auth Credentials

Get from publish profile:
```bash
az webapp deployment list-publishing-profiles \
  --name <app-name> \
  --resource-group <rg> \
  --query "[?publishMethod=='MSDeploy'].{user:userName,pass:userPWD}"
```

### AAD Authentication

```bash
# Get AAD token
az account get-access-token --resource https://management.azure.com

# Use in header
curl https://<app>.scm.azurewebsites.net/api/deployments \
  -H "Authorization: Bearer <token>"
```
