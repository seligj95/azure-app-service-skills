---
name: azure-app-service-security
description: Secure Azure App Service applications with authentication, Managed Identity, Key Vault integration, network restrictions, and compliance configurations. Use when implementing authentication (Easy Auth), configuring Managed Identity, integrating Key Vault secrets, setting up access restrictions, or hardening App Service security posture.
---

## When to Apply

Reference these guidelines when:

- Implementing authentication for App Service apps
- Configuring Managed Identity for secure service access
- Integrating Azure Key Vault for secrets management
- Setting up network access restrictions
- Hardening security configuration
- Meeting compliance requirements

## Security Checklist

| Category | Configuration | Priority |
|----------|---------------|----------|
| Transport | HTTPS Only, TLS 1.2+ | CRITICAL |
| Identity | Managed Identity | CRITICAL |
| Secrets | Key Vault References | CRITICAL |
| Access | FTP Disabled | HIGH |
| Auth | Easy Auth or custom | MEDIUM |
| Network | Access Restrictions | MEDIUM |

## Managed Identity

### Enable System-Assigned Identity

```bash
# Enable managed identity
az webapp identity assign --name <app> --resource-group <rg>

# Get principal ID
az webapp identity show --name <app> --resource-group <rg> --query principalId -o tsv
```

### Enable User-Assigned Identity

```bash
# Create user-assigned identity
az identity create --name <identity-name> --resource-group <rg>

# Get identity resource ID
IDENTITY_ID=$(az identity show --name <identity-name> --resource-group <rg> --query id -o tsv)

# Assign to app
az webapp identity assign --name <app> --resource-group <rg> --identities $IDENTITY_ID
```

### Grant Access to Resources

```bash
# Grant Key Vault access
az keyvault set-policy --name <vault> \
  --object-id <principal-id> \
  --secret-permissions get list

# Grant Storage Blob access
az role assignment create \
  --role "Storage Blob Data Reader" \
  --assignee <principal-id> \
  --scope "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<storage>"

# Grant SQL Database access
az sql server ad-admin create \
  --resource-group <rg> \
  --server <sql-server> \
  --display-name "AppServiceIdentity" \
  --object-id <principal-id>
```

## Key Vault Integration

### Create Key Vault Reference

```bash
# Store secret in Key Vault
az keyvault secret set --vault-name <vault> --name "DbPassword" --value "secret123"

# Reference in app setting (system-assigned identity)
az webapp config appsettings set \
  --name <app> --resource-group <rg> \
  --settings "DB_PASSWORD=@Microsoft.KeyVault(SecretUri=https://<vault>.vault.azure.net/secrets/DbPassword/)"

# Reference with specific version
az webapp config appsettings set \
  --name <app> --resource-group <rg> \
  --settings "DB_PASSWORD=@Microsoft.KeyVault(SecretUri=https://<vault>.vault.azure.net/secrets/DbPassword/<version>)"

# Reference with user-assigned identity
az webapp config appsettings set \
  --name <app> --resource-group <rg> \
  --settings "DB_PASSWORD=@Microsoft.KeyVault(VaultName=<vault>;SecretName=DbPassword;IdentityClientId=<client-id>)"
```

### Key Vault Access Policy

```bash
# Get app's managed identity principal ID
PRINCIPAL_ID=$(az webapp identity show --name <app> --resource-group <rg> --query principalId -o tsv)

# Grant access
az keyvault set-policy \
  --name <vault> \
  --object-id $PRINCIPAL_ID \
  --secret-permissions get list
```

### Key Vault RBAC (Recommended)

```bash
# Grant Key Vault Secrets User role
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $PRINCIPAL_ID \
  --scope "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>"
```

## Authentication (Easy Auth)

### Enable Microsoft Entra ID Authentication

```bash
# Create app registration
az ad app create --display-name "<app>-auth" --sign-in-audience AzureADMyOrg

# Get app ID
APP_ID=$(az ad app list --display-name "<app>-auth" --query [0].appId -o tsv)

# Create client secret
az ad app credential reset --id $APP_ID --append

# Configure Easy Auth
az webapp auth microsoft update \
  --name <app> --resource-group <rg> \
  --client-id $APP_ID \
  --client-secret "<secret>" \
  --issuer "https://login.microsoftonline.com/<tenant-id>/v2.0"

# Enable authentication
az webapp auth update \
  --name <app> --resource-group <rg> \
  --enabled true \
  --action LoginWithAzureActiveDirectory
```

### Auth Configuration Options

```bash
# Require authentication for all requests
az webapp auth update \
  --name <app> --resource-group <rg> \
  --enabled true \
  --unauthenticated-client-action RedirectToLoginPage

# Allow anonymous (authenticate when needed)
az webapp auth update \
  --name <app> --resource-group <rg> \
  --enabled true \
  --unauthenticated-client-action AllowAnonymous

# Return 401 for unauthenticated API calls
az webapp auth update \
  --name <app> --resource-group <rg> \
  --enabled true \
  --unauthenticated-client-action Return401
```

## Transport Security

### Enable HTTPS Only

```bash
az webapp update --name <app> --resource-group <rg> --https-only true
```

### Set Minimum TLS Version

```bash
az webapp config set --name <app> --resource-group <rg> --min-tls-version 1.2
```

### Disable FTP

```bash
# Completely disable FTP
az webapp config set --name <app> --resource-group <rg> --ftps-state Disabled

# Or allow FTPS only
az webapp config set --name <app> --resource-group <rg> --ftps-state FtpsOnly
```

### Disable HTTP 2.0 (if TLS issues)

```bash
az webapp config set --name <app> --resource-group <rg> --http20-enabled false
```

## Access Restrictions

### IP-Based Restrictions

```bash
# Allow specific IP
az webapp config access-restriction add \
  --name <app> --resource-group <rg> \
  --rule-name "Office" \
  --priority 100 \
  --ip-address "203.0.113.0/24" \
  --action Allow

# Deny all except allowed
az webapp config access-restriction set \
  --name <app> --resource-group <rg> \
  --default-action Deny
```

### Service Tag Restrictions

```bash
# Allow Azure Front Door
az webapp config access-restriction add \
  --name <app> --resource-group <rg> \
  --rule-name "FrontDoor" \
  --priority 100 \
  --service-tag AzureFrontDoor.Backend \
  --action Allow

# Allow API Management
az webapp config access-restriction add \
  --name <app> --resource-group <rg> \
  --rule-name "APIM" \
  --priority 110 \
  --service-tag ApiManagement \
  --action Allow
```

### VNet-Based Restrictions

```bash
# Allow from specific subnet
az webapp config access-restriction add \
  --name <app> --resource-group <rg> \
  --rule-name "VNetSubnet" \
  --priority 100 \
  --vnet-name <vnet> \
  --subnet <subnet> \
  --action Allow
```

### SCM Site Restrictions

```bash
# Restrict Kudu/SCM site separately
az webapp config access-restriction add \
  --name <app> --resource-group <rg> \
  --rule-name "AdminOnly" \
  --priority 100 \
  --ip-address "10.0.0.0/8" \
  --scm-site true \
  --action Allow

# Match main site restrictions to SCM
az webapp config access-restriction set \
  --name <app> --resource-group <rg> \
  --use-same-restrictions-for-scm-site true
```

## Security Headers

Configure via `web.config` or application code:

```xml
<system.webServer>
  <httpProtocol>
    <customHeaders>
      <add name="X-Content-Type-Options" value="nosniff" />
      <add name="X-Frame-Options" value="DENY" />
      <add name="X-XSS-Protection" value="1; mode=block" />
      <add name="Content-Security-Policy" value="default-src 'self'" />
      <add name="Strict-Transport-Security" value="max-age=31536000; includeSubDomains" />
    </customHeaders>
  </httpProtocol>
</system.webServer>
```

## Compliance Configuration

### Disable Remote Debugging

```bash
az webapp config set --name <app> --resource-group <rg> --remote-debugging-enabled false
```

### Enable Client Certificates

```bash
# Require client certificates
az webapp update \
  --name <app> --resource-group <rg> \
  --client-affinity-enabled false \
  --set clientCertEnabled=true \
  --set clientCertMode=Required

# Optional client certificates
az webapp update \
  --name <app> --resource-group <rg> \
  --set clientCertEnabled=true \
  --set clientCertMode=Optional
```

### Audit Security Configuration

```bash
# Check HTTPS-only
az webapp show --name <app> --resource-group <rg> --query httpsOnly

# Check TLS version
az webapp config show --name <app> --resource-group <rg> --query minTlsVersion

# Check FTP state
az webapp config show --name <app> --resource-group <rg> --query ftpsState

# Check managed identity
az webapp identity show --name <app> --resource-group <rg>

# List access restrictions
az webapp config access-restriction show --name <app> --resource-group <rg>
```

## Security Hardening Script

```bash
#!/bin/bash
# Harden App Service security configuration

APP_NAME=$1
RESOURCE_GROUP=$2

echo "Hardening $APP_NAME..."

# HTTPS Only
az webapp update -n $APP_NAME -g $RESOURCE_GROUP --https-only true

# TLS 1.2
az webapp config set -n $APP_NAME -g $RESOURCE_GROUP --min-tls-version 1.2

# Disable FTP
az webapp config set -n $APP_NAME -g $RESOURCE_GROUP --ftps-state Disabled

# Disable remote debugging
az webapp config set -n $APP_NAME -g $RESOURCE_GROUP --remote-debugging-enabled false

# Enable managed identity
az webapp identity assign -n $APP_NAME -g $RESOURCE_GROUP

# HTTP/2
az webapp config set -n $APP_NAME -g $RESOURCE_GROUP --http20-enabled true

echo "✅ Security hardening complete"
```

## References

- **Key Vault Patterns**: See [references/keyvault.md](references/keyvault.md) for advanced Key Vault integration
- **Authentication Providers**: See [references/auth-providers.md](references/auth-providers.md) for Google, GitHub, etc.
