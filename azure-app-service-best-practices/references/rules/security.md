# Security Best Practices

Detailed explanations for security rules.

## security-managed-identity

**Priority:** CRITICAL

Use Managed Identity instead of storing credentials in app settings.

### Why It Matters

- App settings are visible in Azure Portal to anyone with read access
- Credentials in settings can be exposed through deployment APIs
- Manual credential rotation is error-prone and risky
- Managed Identity provides automatic credential rotation

### Bad Practice

```bash
# ❌ Storing database credentials in app settings
az webapp config appsettings set --name myapp --resource-group myrg \
  --settings "DB_PASSWORD=SuperSecret123"
```

### Good Practice

```bash
# ✅ Enable Managed Identity
az webapp identity assign --name myapp --resource-group myrg

# Grant identity access to resources (e.g., Key Vault)
az keyvault set-policy --name myvault \
  --object-id <identity-principal-id> \
  --secret-permissions get list

# Reference Key Vault secret in app setting
az webapp config appsettings set --name myapp --resource-group myrg \
  --settings "DB_PASSWORD=@Microsoft.KeyVault(SecretUri=https://myvault.vault.azure.net/secrets/db-password/)"
```

---

## security-https-only

**Priority:** CRITICAL

Enforce HTTPS-only connections to prevent data interception.

### Why It Matters

- HTTP traffic can be intercepted and modified
- Credentials and session tokens exposed over HTTP
- Required for compliance (PCI-DSS, HIPAA, etc.)
- Browser warnings for non-HTTPS sites

### Implementation

```bash
az webapp update --name myapp --resource-group myrg --https-only true
```

### Verification

```bash
# Should return "true"
az webapp show --name myapp --resource-group myrg --query httpsOnly
```

---

## security-min-tls

**Priority:** CRITICAL

Require TLS 1.2 or higher for all connections.

### Why It Matters

- TLS 1.0 and 1.1 have known vulnerabilities
- Required by PCI-DSS 3.2.1 and later
- Modern browsers deprecate older TLS versions

### Implementation

```bash
az webapp config set --name myapp --resource-group myrg --min-tls-version 1.2
```

---

## security-disable-ftp

**Priority:** HIGH

Disable FTP/FTPS access to prevent insecure file transfers.

### Why It Matters

- FTP credentials can be brute-forced
- FTP traffic (non-FTPS) is unencrypted
- Modern deployment methods (Git, ZIP, CI/CD) are more secure
- Reduces attack surface

### Implementation

```bash
# Completely disable FTP
az webapp config set --name myapp --resource-group myrg --ftps-state Disabled

# Or allow FTPS only (if FTP is required)
az webapp config set --name myapp --resource-group myrg --ftps-state FtpsOnly
```

---

## security-keyvault-refs

**Priority:** HIGH

Store secrets in Azure Key Vault and reference them from app settings.

### Why It Matters

- Centralized secret management
- Audit logging for secret access
- Automatic rotation capabilities
- Separation of duties (app devs vs. security admins)

### Implementation

1. **Create Key Vault and secret:**
```bash
az keyvault create --name myvault --resource-group myrg
az keyvault secret set --vault-name myvault --name db-password --value "SecretValue"
```

2. **Enable Managed Identity on app:**
```bash
az webapp identity assign --name myapp --resource-group myrg
```

3. **Grant access to Key Vault:**
```bash
PRINCIPAL_ID=$(az webapp identity show --name myapp --resource-group myrg --query principalId -o tsv)
az keyvault set-policy --name myvault --object-id $PRINCIPAL_ID --secret-permissions get list
```

4. **Reference secret in app setting:**
```bash
az webapp config appsettings set --name myapp --resource-group myrg \
  --settings "DB_PASSWORD=@Microsoft.KeyVault(SecretUri=https://myvault.vault.azure.net/secrets/db-password/)"
```

---

## security-vnet-integration

**Priority:** MEDIUM

Use VNet integration to secure outbound connections and securely access backend services.

### Why It Matters

- Private connectivity to databases, storage, other services
- Traffic stays within Azure backbone
- Required for accessing private endpoints
- Enables network-level access controls

### Implementation

```bash
# Integrate with existing VNet subnet
az webapp vnet-integration add \
  --name myapp \
  --resource-group myrg \
  --vnet myvnet \
  --subnet app-subnet
```

**Subnet requirements:**
- Minimum /28 subnet dedicated to App Service
- Must be delegated to Microsoft.Web/serverFarms
- Cannot have other resources in the subnet

---

## security-private-endpoints

**Priority:** MEDIUM (HIGH for sensitive workloads)

Use private endpoints to restrict inbound traffic to private networks only.

### Why It Matters

- App not accessible from public internet
- Required for highly sensitive/regulated workloads
- Combined with VNet integration for full private networking
- Access only through VPN, ExpressRoute, or other private connections

### Implementation

```bash
# Create private endpoint
az network private-endpoint create \
  --name myapp-pe \
  --resource-group myrg \
  --vnet-name myvnet \
  --subnet pe-subnet \
  --private-connection-resource-id $(az webapp show --name myapp --resource-group myrg --query id -o tsv) \
  --group-id sites \
  --connection-name myapp-connection
```
