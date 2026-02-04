---
name: azure-app-service-managed-instance
description: Guidance for Azure App Service Managed Instance (preview) - a plan-scoped hosting option for Windows web apps requiring OS customization, COM components, registry modifications, MSI installers, and optional private networking. Use when migrating legacy .NET Framework apps, configuring Windows-specific features, or needing RDP access for diagnostics.
---

## When to Use Managed Instance

Use Managed Instance when you need:

- **Legacy Windows compatibility**: COM components, registry modifications, MSI installers
- **IIS customization**: IIS Manager access, custom ACLs, Windows features
- **Network shares**: UNC paths, drive mapping to Azure Files or on-premises
- **RDP diagnostics**: Just-in-time RDP via Azure Bastion for troubleshooting
- **Migration with minimal refactoring**: "Lift and improve" for legacy .NET Framework apps

**Do NOT use** Managed Instance for:
- Linux or containerized workloads
- Multi-language apps (Python, Node.js, Java, PHP)
- Apps that don't need OS-level customization

## Current Limitations (Preview)

| Category | Limitation |
|----------|------------|
| Platform | Windows only (no Linux/containers) |
| SKUs | Pv4 and Pmv4 only |
| Regions | East Asia, West Central US, North Europe, East US, Australia East |
| Authentication | Entra ID and Managed Identity only (no domain join/NTLM/Kerberos) |
| Workloads | Web apps only (no WebJobs, TCP/NetPipes) |
| Configuration | Persistent changes require scripts (RDP is diagnostics-only) |

## SKU Options

### Standard Pv4 SKUs

| SKU | vCPU | Memory (MB) |
|-----|------|-------------|
| P0v4 | 1 | 2,048 |
| P1v4 | 2 | 5,952 |
| P2v4 | 4 | 13,440 |
| P3v4 | 8 | 28,672 |

### Memory-Optimized Pmv4 SKUs

| SKU | vCPU | Memory (MB) |
|-----|------|-------------|
| P1Mv4 | 2 | 13,440 |
| P2Mv4 | 4 | 28,672 |
| P3Mv4 | 8 | 60,160 |
| P4Mv4 | 16 | 121,088 |
| P5Mv4 | 32 | 246,016 |

## Quick Start

### Check Region Availability

```bash
# List regions with Managed Instance support
az appservice list-locations --managed-instance-enabled --sku P1v4
```

### Deploy with Azure Developer CLI

```bash
# Clone and deploy sample quickstart
mkdir managed-instance-quickstart
cd managed-instance-quickstart
azd init --template https://github.com/Azure-Samples/managed-instance-azure-app-service-quickstart.git
azd env set AZURE_LOCATION northeurope
azd up
```

### Deploy via Azure Portal

1. Create resource → Search "managed instance"
2. Select **Web App (for Managed Instance) (preview)**
3. Configure:
   - Runtime: ASP.NET V4.8 (or .NET 8.0)
   - Pricing plan: Pv4 or Pmv4
   - Configuration script (optional): Storage account, container, zip file

## Configuration (Install) Scripts

Install scripts run at instance startup for persistent OS customization.

### Requirements

- Script must be named `Install.ps1`
- Packaged as single `.zip` file
- Uploaded to Azure Blob Storage
- Plan-level managed identity with `Storage Blob Data Reader` role

### Example Script Structure

```
scripts.zip
├── Install.ps1         # Entry point (required)
├── myComponent.msi     # Dependencies
└── config.xml          # Configuration files
```

### Example Install.ps1

```powershell
# Install MSI component
$ComponentInstaller = "myComponent.msi"
try {
    $Component = Join-Path $PSScriptRoot $ComponentInstaller
    Start-Process $Component -ArgumentList "/q" -Wait -ErrorAction Stop
    Write-Host "Successfully installed $ComponentInstaller"
} catch {
    Write-Error "Failed to install ${ComponentInstaller}: $_"
    exit 1
}

# Register COM component
regsvr32 /s (Join-Path $PSScriptRoot "mycomponent.dll")

# Enable Windows feature
Enable-WindowsOptionalFeature -Online -FeatureName "MSMQ-Container" -All -NoRestart

# Install fonts
Get-ChildItem -Recurse -Include *.ttf, *.otf | ForEach-Object {
    $Destination = "$env:windir\Fonts\$($_.Name)"
    Copy-Item $_.FullName -Destination $Destination -Force
    $FontName = $_.BaseName + " (TrueType)"
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" `
        -Name $FontName -PropertyType String -Value $_.Name -Force | Out-Null
}
```

### Script Best Practices

- Make scripts **idempotent** (check before install)
- Avoid modifying protected Windows system directories
- Stagger heavy installations to reduce startup latency
- Log installation progress for troubleshooting
- Scripts run with **Administrator** privileges

### Script Logs

```
# On instance
C:\InstallScripts\<scriptName>\Install.log

# Via Azure Monitor/Log Analytics
# Enable diagnostic settings → App Service Console Logs
```

## Storage Mounts

Mount external storage accessible to your apps.

### Azure Files Mount

```bash
# 1. Create Key Vault secret with connection string
az keyvault secret set \
  --vault-name <vault-name> \
  --name storage-connection \
  --value "DefaultEndpointsProtocol=https;AccountName=<storage>;AccountKey=<key>;EndpointSuffix=core.windows.net"

# 2. Configure via Portal:
# Managed Instance → Configuration → Mounts → + New storage mount
# - Storage type: Azure Files
# - Select storage account and file share
# - Select Key Vault and secret
# - Choose drive letter (e.g., E:)
```

### Custom UNC Path Mount

For SMB shares (on-premises, VMs, or non-Microsoft):

```bash
# 1. Store credentials in Key Vault
az keyvault secret set \
  --vault-name <vault-name> \
  --name unc-credentials \
  --value "username=<user>,password=<password>"

# 2. Configure mount:
# - Storage type: Custom
# - UNC path: \\server\share
# - Select Key Vault secret for credentials
```

### Local Temporary Storage

- Limited to 2 GB
- Not persisted after restarts
- Use for temporary processing only

## Registry Key Adapters

Create Windows registry keys with values from Key Vault.

### Setup

```bash
# 1. Store value in Key Vault
az keyvault secret set \
  --vault-name <vault-name> \
  --name my-registry-value \
  --value "secret-configuration-value"

# 2. Configure via Portal:
# Managed Instance → Configuration → Registry Keys → + Add
# - Path: HKLM:\SOFTWARE\MyApp\Config
# - Vault: Select Key Vault
# - Secret: Select secret
# - Type: String or DWORD
```

### Supported Types

- `String` (REG_SZ)
- `DWORD` (32-bit integer)

> **Caution**: Be careful when modifying system-critical registry paths.

## Plan-Level Managed Identity

Required for configuration scripts, storage mounts, and registry adapters.

### Assign User-Assigned Identity

```bash
# Create identity
az identity create \
  --name mi-managed-instance \
  --resource-group <rg>

# Get identity ID
IDENTITY_ID=$(az identity show \
  --name mi-managed-instance \
  --resource-group <rg> \
  --query id -o tsv)

# Assign to plan via Portal:
# Managed Instance → Identity → User assigned → + Add
```

### Grant Permissions

```bash
# Get identity principal ID
PRINCIPAL_ID=$(az identity show \
  --name mi-managed-instance \
  --resource-group <rg> \
  --query principalId -o tsv)

# Grant Storage Blob Data Reader for config scripts
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage Blob Data Reader" \
  --scope <storage-account-or-container-id>

# Grant Key Vault Secrets User for mounts/registry
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Key Vault Secrets User" \
  --scope <keyvault-id>
```

## RDP Access via Bastion

Just-in-time RDP for transient diagnostics.

### Prerequisites

1. Managed Instance must be VNet integrated
2. Azure Bastion deployed in the VNet
3. Bastion Standard tier with Native Client Support enabled
4. Port 3389 allowed in NSG (Bastion subnet → App Service subnet)

### Configure

```bash
# 1. Enable VNet integration (see networking skill)

# 2. Deploy Bastion
az network bastion create \
  --name bastion-host \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --location <location> \
  --sku Standard

# 3. Enable RDP:
# Managed Instance → Configuration → Bastion/RDP → Allow Remote Desktop
```

### RDP Diagnostics

Available via RDP:
- Event Viewer
- IIS Manager
- File system access
- C:\InstallScripts logs

> **Warning**: Manual changes via RDP are LOST on restart or platform maintenance. Use configuration scripts for persistent changes.

## Networking

### VNet Integration (Optional)

```bash
# Add VNet integration
az webapp vnet-integration add \
  --name <app-name> \
  --resource-group <rg> \
  --vnet <vnet-name> \
  --subnet <subnet-name>

# Route all traffic through VNet
az resource update \
  --resource-group <rg> \
  --name <app-name> \
  --resource-type "Microsoft.Web/sites" \
  --set properties.outboundVnetRouting.allTraffic=true
```

### Private Endpoints

```bash
az network private-endpoint create \
  --name <app-name>-pe \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --subnet private-endpoints-subnet \
  --private-connection-resource-id <app-resource-id> \
  --group-id sites \
  --connection-name app-connection
```

## Deployment

### Zip Deploy

```bash
az webapp deploy \
  --resource-group <rg> \
  --name <app-name> \
  --src-path app.zip \
  --type zip
```

### Run From Package

```bash
az webapp config appsettings set \
  --name <app-name> \
  --resource-group <rg> \
  --settings WEBSITE_RUN_FROM_PACKAGE=1

az webapp deploy \
  --resource-group <rg> \
  --name <app-name> \
  --src-path app.zip \
  --type zip
```

## Runtime Support

### Preinstalled

- .NET Framework 3.5
- .NET Framework 4.8
- .NET 8.0

### Custom Runtimes

Install via configuration scripts (you manage updates).

## Comparing Hosting Options

| Feature | Standard App Service | Managed Instance | ASE |
|---------|---------------------|------------------|-----|
| OS Customization | No | Yes (scripts) | Yes |
| RDP Access | No | Yes (Bastion) | Yes |
| COM/Registry/MSI | No | Yes | Yes |
| Linux/Containers | Yes | No | Yes |
| Multi-language | Yes | .NET only | Yes |
| Isolation | Shared | Plan-scoped | Full |
| Cost | Lower | Pv4/Pmv4 | Highest |

## Best Practices

1. **Use configuration scripts** for persistent changes (not RDP)
2. **Centralize secrets** in Azure Key Vault
3. **Test scripts in staging** before production rollout
4. **Monitor with Defender for Cloud** for threat detection
5. **Validate logging setup** for troubleshooting
6. **Align network rules** with dependency inventories

## Troubleshooting

### Configuration Script Failures

```bash
# Check script logs on instance
C:\InstallScripts\<scriptName>\Install.log

# Stream via Log Analytics
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "AppServiceConsoleLogs | where ResultDescription contains 'Install' | take 50"
```

### Storage/Registry Adapter Issues

- Check plan-level managed identity has correct permissions
- Verify Key Vault secrets are accessible
- Review App Service Platform Logs

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| Script timeout | Heavy installation | Stagger installations, optimize script |
| Storage mount failed | Credentials invalid | Verify Key Vault secret format |
| Registry key not created | Wrong path/permissions | Check registry path syntax |
| RDP unavailable | No VNet integration | Enable VNet integration first |

## References

- [Managed Instance Overview](https://learn.microsoft.com/en-us/azure/app-service/overview-managed-instance)
- [Configure Managed Instance](https://learn.microsoft.com/en-us/azure/app-service/configure-managed-instance)
- [Quickstart](https://learn.microsoft.com/en-us/azure/app-service/quickstart-managed-instance)
