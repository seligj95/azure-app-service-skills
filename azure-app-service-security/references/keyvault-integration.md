# Key Vault Integration Patterns

## Key Vault References in App Settings

The recommended pattern - App Service automatically retrieves secrets from Key Vault.

### Setup Steps

```bash
# 1. Enable Managed Identity on App Service
az webapp identity assign --name <app-name> --resource-group <rg>

# 2. Get the identity principal ID
PRINCIPAL_ID=$(az webapp identity show \
  --name <app-name> \
  --resource-group <rg> \
  --query principalId -o tsv)

# 3. Grant Key Vault access
az keyvault set-policy \
  --name <keyvault-name> \
  --object-id $PRINCIPAL_ID \
  --secret-permissions get list

# 4. Create/update secret in Key Vault
az keyvault secret set \
  --vault-name <keyvault-name> \
  --name "DatabasePassword" \
  --value "super-secret-password"

# 5. Create Key Vault reference in app settings
az webapp config appsettings set \
  --name <app-name> \
  --resource-group <rg> \
  --settings DATABASE_PASSWORD="@Microsoft.KeyVault(SecretUri=https://<keyvault-name>.vault.azure.net/secrets/DatabasePassword/)"
```

### Reference Formats

```bash
# Full reference with version (recommended for production)
@Microsoft.KeyVault(SecretUri=https://myvault.vault.azure.net/secrets/mysecret/abc123def456)

# Latest version (auto-updates within 24 hours)
@Microsoft.KeyVault(SecretUri=https://myvault.vault.azure.net/secrets/mysecret/)

# Shorthand format
@Microsoft.KeyVault(VaultName=myvault;SecretName=mysecret)

# With version
@Microsoft.KeyVault(VaultName=myvault;SecretName=mysecret;SecretVersion=abc123def456)
```

### Reference Status Check

```bash
# Check if references are resolving
az webapp config appsettings list \
  --name <app-name> \
  --resource-group <rg> \
  --query "[?contains(value, 'KeyVault')].{name:name, status:keyVaultReferenceStatus}"
```

Status values:
- `Resolved` - Secret retrieved successfully
- `SecretNotFound` - Secret doesn't exist
- `VaultNotFound` - Key Vault doesn't exist
- `Unauthorized` - Identity lacks permissions

## Using Key Vault RBAC (Recommended over Access Policies)

### Setup with RBAC

```bash
# Enable RBAC on Key Vault
az keyvault update \
  --name <keyvault-name> \
  --resource-group <rg> \
  --enable-rbac-authorization true

# Assign "Key Vault Secrets User" role
PRINCIPAL_ID=$(az webapp identity show --name <app-name> --resource-group <rg> --query principalId -o tsv)
KEYVAULT_ID=$(az keyvault show --name <keyvault-name> --resource-group <rg> --query id -o tsv)

az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Key Vault Secrets User" \
  --scope $KEYVAULT_ID
```

### Role Comparison

| Access Method | Role/Policy | Permissions |
|---------------|-------------|-------------|
| RBAC | Key Vault Secrets User | Get, List secrets |
| RBAC | Key Vault Secrets Officer | Get, List, Set, Delete secrets |
| Access Policy | Secret: Get, List | Get, List secrets |

## Direct SDK Access

For scenarios requiring dynamic secret access in code.

### .NET

```csharp
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;

var client = new SecretClient(
    new Uri("https://<keyvault-name>.vault.azure.net/"),
    new DefaultAzureCredential());

// Get secret
KeyVaultSecret secret = await client.GetSecretAsync("DatabasePassword");
string password = secret.Value;

// List secrets
await foreach (SecretProperties secretProperties in client.GetPropertiesOfSecretsAsync())
{
    Console.WriteLine(secretProperties.Name);
}
```

### Python

```python
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

credential = DefaultAzureCredential()
client = SecretClient(
    vault_url="https://<keyvault-name>.vault.azure.net/",
    credential=credential)

# Get secret
secret = client.get_secret("DatabasePassword")
password = secret.value

# List secrets
secrets = client.list_properties_of_secrets()
for secret_props in secrets:
    print(secret_props.name)
```

### Node.js

```javascript
const { DefaultAzureCredential } = require("@azure/identity");
const { SecretClient } = require("@azure/keyvault-secrets");

const credential = new DefaultAzureCredential();
const client = new SecretClient(
    "https://<keyvault-name>.vault.azure.net/",
    credential);

// Get secret
const secret = await client.getSecret("DatabasePassword");
const password = secret.value;
```

## Connection String Patterns

### SQL with Key Vault Reference

```bash
# Store SQL password in Key Vault
az keyvault secret set \
  --vault-name <keyvault-name> \
  --name "SqlPassword" \
  --value "your-sql-password"

# Connection string referencing Key Vault
# Note: Only the password comes from Key Vault
az webapp config connection-string set \
  --name <app-name> \
  --resource-group <rg> \
  --connection-string-type SQLAzure \
  --settings DefaultConnection="Server=tcp:server.database.windows.net;Database=mydb;User ID=admin;Password=@Microsoft.KeyVault(VaultName=myvault;SecretName=SqlPassword);Encrypt=true;"
```

### Full Connection String in Key Vault

```bash
# Store entire connection string
az keyvault secret set \
  --vault-name <keyvault-name> \
  --name "DatabaseConnectionString" \
  --value "Server=tcp:server.database.windows.net;Database=mydb;User ID=admin;Password=secret;Encrypt=true;"

# Reference entire connection string
az webapp config connection-string set \
  --name <app-name> \
  --resource-group <rg> \
  --connection-string-type SQLAzure \
  --settings DefaultConnection="@Microsoft.KeyVault(VaultName=myvault;SecretName=DatabaseConnectionString)"
```

## Secret Rotation

### Automatic Rotation with Key Vault References

When using latest version URI (without version), App Service refreshes secrets within 24 hours:

```bash
# Update secret in Key Vault
az keyvault secret set \
  --vault-name <keyvault-name> \
  --name "DatabasePassword" \
  --value "new-password"

# Force immediate refresh (restart app)
az webapp restart --name <app-name> --resource-group <rg>
```

### Manual Rotation Pattern

```bash
# 1. Add new secret version
NEW_SECRET=$(az keyvault secret set \
  --vault-name <keyvault-name> \
  --name "DatabasePassword" \
  --value "new-password" \
  --query id -o tsv)

# 2. Update app setting with new version
az webapp config appsettings set \
  --name <app-name> \
  --resource-group <rg> \
  --settings DATABASE_PASSWORD="@Microsoft.KeyVault(SecretUri=$NEW_SECRET)"

# 3. App restarts automatically, uses new secret
```

## Network-Secured Key Vault

### Private Endpoint Access

```bash
# Create private endpoint for Key Vault
az network private-endpoint create \
  --name kv-private-endpoint \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --subnet <subnet-name> \
  --private-connection-resource-id <keyvault-resource-id> \
  --group-id vault \
  --connection-name keyvault-connection

# Configure private DNS zone
az network private-dns zone create \
  --resource-group <rg> \
  --name "privatelink.vaultcore.azure.net"

az network private-dns link vnet create \
  --resource-group <rg> \
  --zone-name "privatelink.vaultcore.azure.net" \
  --name keyvault-dns-link \
  --virtual-network <vnet-name> \
  --registration-enabled false

# App Service must have VNet Integration to access
az webapp vnet-integration add \
  --name <app-name> \
  --resource-group <rg> \
  --vnet <vnet-name> \
  --subnet <integration-subnet>
```

## Troubleshooting

### Check Reference Status

```bash
az webapp config appsettings list \
  --name <app-name> \
  --resource-group <rg> \
  --output table
```

### Common Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `SecretNotFound` | Secret doesn't exist | Verify secret name, check Key Vault |
| `Unauthorized` | Missing permissions | Grant Key Vault access |
| `VaultNotFound` | Wrong vault name | Check vault name spelling |
| Network timeout | Key Vault blocked | Use VNet integration + private endpoint |

### Test from Kudu Console

```bash
# Test Key Vault access
curl "$IDENTITY_ENDPOINT?resource=https://vault.azure.net&api-version=2019-08-01" \
  -H "X-IDENTITY-HEADER: $IDENTITY_HEADER"
```
