# Managed Identity Configuration

## System-Assigned Managed Identity

### Enable System-Assigned Identity

```bash
# Enable on existing app
az webapp identity assign \
  --name <app-name> \
  --resource-group <rg>

# Returns:
# {
#   "principalId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "type": "SystemAssigned"
# }
```

### Grant Permissions to Resources

```bash
# Get the managed identity principal ID
PRINCIPAL_ID=$(az webapp identity show \
  --name <app-name> \
  --resource-group <rg> \
  --query principalId -o tsv)

# Grant access to Key Vault
az keyvault set-policy \
  --name <keyvault-name> \
  --object-id $PRINCIPAL_ID \
  --secret-permissions get list

# Grant access to Storage Account (Blob Data Reader)
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage Blob Data Reader" \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<storage-name>

# Grant access to Azure SQL
az sql server ad-admin create \
  --server <sql-server-name> \
  --resource-group <rg> \
  --display-name <app-name> \
  --object-id $PRINCIPAL_ID
```

## User-Assigned Managed Identity

### Create and Assign User Identity

```bash
# Create user-assigned identity
az identity create \
  --name <identity-name> \
  --resource-group <rg>

# Get identity resource ID
IDENTITY_ID=$(az identity show \
  --name <identity-name> \
  --resource-group <rg> \
  --query id -o tsv)

# Assign to web app
az webapp identity assign \
  --name <app-name> \
  --resource-group <rg> \
  --identities $IDENTITY_ID
```

### Use User-Assigned Identity in Code

```csharp
// .NET - specify client ID for user-assigned identity
var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
{
    ManagedIdentityClientId = "<user-assigned-identity-client-id>"
});
```

```python
# Python - specify client ID
from azure.identity import ManagedIdentityCredential
credential = ManagedIdentityCredential(client_id="<user-assigned-identity-client-id>")
```

## Using Managed Identity in Code

### .NET SDK

```csharp
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Azure.Storage.Blobs;

// Key Vault access
var kvClient = new SecretClient(
    new Uri("https://<keyvault-name>.vault.azure.net/"),
    new DefaultAzureCredential());

KeyVaultSecret secret = await kvClient.GetSecretAsync("my-secret");

// Blob Storage access
var blobClient = new BlobServiceClient(
    new Uri("https://<storage-name>.blob.core.windows.net/"),
    new DefaultAzureCredential());
```

### Python SDK

```python
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import BlobServiceClient

credential = DefaultAzureCredential()

# Key Vault access
kv_client = SecretClient(
    vault_url="https://<keyvault-name>.vault.azure.net/",
    credential=credential)

secret = kv_client.get_secret("my-secret")

# Blob Storage access
blob_client = BlobServiceClient(
    account_url="https://<storage-name>.blob.core.windows.net/",
    credential=credential)
```

### Node.js SDK

```javascript
const { DefaultAzureCredential } = require("@azure/identity");
const { SecretClient } = require("@azure/keyvault-secrets");
const { BlobServiceClient } = require("@azure/storage-blob");

const credential = new DefaultAzureCredential();

// Key Vault access
const kvClient = new SecretClient(
    "https://<keyvault-name>.vault.azure.net/",
    credential);

const secret = await kvClient.getSecret("my-secret");

// Blob Storage access
const blobClient = new BlobServiceClient(
    "https://<storage-name>.blob.core.windows.net/",
    credential);
```

### Java SDK

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;

// Key Vault access
SecretClient secretClient = new SecretClientBuilder()
    .vaultUrl("https://<keyvault-name>.vault.azure.net/")
    .credential(new DefaultAzureCredentialBuilder().build())
    .buildClient();

KeyVaultSecret secret = secretClient.getSecret("my-secret");
```

## SQL Connection with Managed Identity

### Connection String (No Password)

```
Server=tcp:<server>.database.windows.net,1433;Database=<database>;Authentication=Active Directory Managed Identity
```

### Grant SQL Access

```sql
-- Run in SQL database
CREATE USER [<app-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [<app-name>];
ALTER ROLE db_datawriter ADD MEMBER [<app-name>];
```

### Entity Framework Core

```csharp
// Add to DbContext configuration
services.AddDbContext<MyDbContext>(options =>
{
    var connection = new SqlConnection(Configuration.GetConnectionString("DefaultConnection"));
    connection.AccessToken = new DefaultAzureCredential().GetToken(
        new TokenRequestContext(new[] { "https://database.windows.net/.default" })).Token;
    options.UseSqlServer(connection);
});
```

## Common RBAC Roles

| Resource | Role | Permissions |
|----------|------|-------------|
| Key Vault | Key Vault Secrets User | Get, List secrets |
| Storage (Blob) | Storage Blob Data Reader | Read blobs |
| Storage (Blob) | Storage Blob Data Contributor | Read, Write, Delete blobs |
| Storage (Queue) | Storage Queue Data Contributor | Send, Receive messages |
| Service Bus | Azure Service Bus Data Receiver | Receive messages |
| Service Bus | Azure Service Bus Data Sender | Send messages |
| Event Hubs | Azure Event Hubs Data Receiver | Receive events |
| Cosmos DB | Cosmos DB Built-in Data Reader | Read data |
| SQL | N/A (use SQL roles) | Database access |

## Troubleshooting

### Verify Identity is Enabled

```bash
az webapp identity show --name <app-name> --resource-group <rg>
```

### Check Role Assignments

```bash
PRINCIPAL_ID=$(az webapp identity show --name <app-name> --resource-group <rg> --query principalId -o tsv)
az role assignment list --assignee $PRINCIPAL_ID --all
```

### Test Token Acquisition (from Kudu console)

```bash
# Get token for Key Vault
curl "$IDENTITY_ENDPOINT?resource=https://vault.azure.net&api-version=2019-08-01" -H "X-IDENTITY-HEADER: $IDENTITY_HEADER"

# Get token for Storage
curl "$IDENTITY_ENDPOINT?resource=https://storage.azure.com&api-version=2019-08-01" -H "X-IDENTITY-HEADER: $IDENTITY_HEADER"
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `ManagedIdentityCredential authentication failed` | Identity not enabled | Enable system/user identity |
| `Access denied` / `403 Forbidden` | Missing RBAC role | Grant appropriate role |
| `The resource principal named X was not found` | App not registered in AAD | Wait a few minutes, AAD propagation |
