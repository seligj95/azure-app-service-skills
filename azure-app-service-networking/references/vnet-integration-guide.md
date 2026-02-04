# VNet Integration Configuration

## Regional VNet Integration (Recommended)

Enables outbound connectivity from App Service to Azure VNet resources.

### Prerequisites

- App Service Plan: Basic or higher (Standard+ recommended)
- Dedicated subnet (not shared with other resources)
- Subnet must be delegated to `Microsoft.Web/serverFarms`

### Setup

```bash
# Create VNet and subnet
az network vnet create \
  --name <vnet-name> \
  --resource-group <rg> \
  --address-prefix 10.0.0.0/16

# Create subnet for VNet Integration (minimum /28, recommended /26)
az network vnet subnet create \
  --name integration-subnet \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --address-prefixes 10.0.1.0/26 \
  --delegations Microsoft.Web/serverFarms

# Add VNet integration to App Service
az webapp vnet-integration add \
  --name <app-name> \
  --resource-group <rg> \
  --vnet <vnet-name> \
  --subnet integration-subnet
```

### Route Traffic Through VNet

By default, only RFC1918 traffic (private IPs) routes through VNet. Use the new `outboundVnetRouting` properties:

```bash
# Route ALL outbound traffic (application + configuration) - RECOMMENDED
az resource update \
  --resource-group <rg> \
  --name <app-name> \
  --resource-type "Microsoft.Web/sites" \
  --set properties.outboundVnetRouting.allTraffic=true

# Route only application traffic (configuration uses public route)
az resource update \
  --resource-group <rg> \
  --name <app-name> \
  --resource-type "Microsoft.Web/sites" \
  --set properties.outboundVnetRouting.applicationTraffic=true

# Disable VNet routing
az resource update \
  --resource-group <rg> \
  --name <app-name> \
  --resource-type "Microsoft.Web/sites" \
  --set properties.outboundVnetRouting.allTraffic=false
```

### Granular Configuration Routing

When using `applicationTraffic=true`, you can selectively route configuration traffic:

```bash
# Route container image pull through VNet
az resource update \
  --resource-group <rg> \
  --name <app-name> \
  --resource-type "Microsoft.Web/sites" \
  --set properties.outboundVnetRouting.imagePullTraffic=true

# Route content share (Azure Files) through VNet
# Note: Ensure NSG allows ports 443 and 445
az resource update \
  --resource-group <rg> \
  --name <app-name> \
  --resource-type "Microsoft.Web/sites" \
  --set properties.outboundVnetRouting.contentShareTraffic=true

# Route backup/restore through VNet
# Note: Database backup not supported over VNet
az resource update \
  --resource-group <rg> \
  --name <app-name> \
  --resource-type "Microsoft.Web/sites" \
  --set properties.outboundVnetRouting.backupRestoreTraffic=true
```

### Legacy Settings (Still Supported)

These legacy settings work but the new `outboundVnetRouting` properties are recommended:

```bash
# Legacy app setting (deprecated)
az webapp config appsettings set \
  --name <app-name> \
  --resource-group <rg> \
  --settings WEBSITE_VNET_ROUTE_ALL=1

# Legacy site property (deprecated)
az resource update \
  --resource-group <rg> \
  --name <app-name> \
  --resource-type "Microsoft.Web/sites" \
  --set properties.vnetRouteAllEnabled=true
```

### Verify Integration

```bash
# Check VNet integration status
az webapp vnet-integration list \
  --name <app-name> \
  --resource-group <rg>
```

### Remove Integration

```bash
az webapp vnet-integration remove \
  --name <app-name> \
  --resource-group <rg>
```

## Subnet Sizing Guidelines

| App Service Plan Instances | Minimum Subnet | Recommended Subnet |
|----------------------------|----------------|-------------------|
| 1-2 | /28 (16 IPs) | /27 (32 IPs) |
| 3-8 | /27 (32 IPs) | /26 (64 IPs) |
| 9-16 | /26 (64 IPs) | /25 (128 IPs) |
| 17+ | /25 (128 IPs) | /24 (256 IPs) |

Note: Each instance requires 1 IP. Plan allows +5 automatic IPs for scaling.

## NSG Configuration for VNet Integration

```bash
# Create NSG
az network nsg create \
  --name integration-nsg \
  --resource-group <rg>

# Allow outbound to Azure services
az network nsg rule create \
  --nsg-name integration-nsg \
  --resource-group <rg> \
  --name AllowAzureServices \
  --priority 100 \
  --direction Outbound \
  --access Allow \
  --protocol Tcp \
  --destination-address-prefixes AzureCloud \
  --destination-port-ranges 443 1433

# Allow outbound to on-prem (via VPN/ExpressRoute)
az network nsg rule create \
  --nsg-name integration-nsg \
  --resource-group <rg> \
  --name AllowOnPrem \
  --priority 200 \
  --direction Outbound \
  --access Allow \
  --protocol Tcp \
  --destination-address-prefixes 192.168.0.0/16 \
  --destination-port-ranges '*'

# Associate NSG with integration subnet
az network vnet subnet update \
  --name integration-subnet \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --network-security-group integration-nsg
```

## DNS Configuration

### Azure Private DNS Zones

```bash
# Create private DNS zone for Azure SQL
az network private-dns zone create \
  --resource-group <rg> \
  --name "privatelink.database.windows.net"

# Link to VNet
az network private-dns link vnet create \
  --resource-group <rg> \
  --zone-name "privatelink.database.windows.net" \
  --name sql-dns-link \
  --virtual-network <vnet-name> \
  --registration-enabled false
```

### Custom DNS Servers

```bash
# Configure custom DNS for App Service
az webapp config appsettings set \
  --name <app-name> \
  --resource-group <rg> \
  --settings WEBSITE_DNS_SERVER=10.0.0.4 \
             WEBSITE_DNS_ALT_SERVER=10.0.0.5
```

## Access Azure PaaS Services via Private Endpoint

### SQL Database Private Endpoint

```bash
# Create private endpoint
az network private-endpoint create \
  --name sql-private-endpoint \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --subnet endpoints-subnet \
  --private-connection-resource-id <sql-server-resource-id> \
  --group-id sqlServer \
  --connection-name sql-connection

# Add DNS record
az network private-dns record-set a add-record \
  --resource-group <rg> \
  --zone-name "privatelink.database.windows.net" \
  --record-set-name <sql-server-name> \
  --ipv4-address <private-endpoint-ip>
```

### Storage Account Private Endpoint

```bash
az network private-endpoint create \
  --name storage-private-endpoint \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --subnet endpoints-subnet \
  --private-connection-resource-id <storage-resource-id> \
  --group-id blob \
  --connection-name storage-connection
```

## NAT Gateway for Outbound

Provides static outbound IP for VNet-integrated apps.

```bash
# Create public IP for NAT Gateway
az network public-ip create \
  --name nat-gateway-ip \
  --resource-group <rg> \
  --sku Standard \
  --allocation-method Static

# Create NAT Gateway
az network nat gateway create \
  --name nat-gateway \
  --resource-group <rg> \
  --public-ip-addresses nat-gateway-ip \
  --idle-timeout 10

# Associate with integration subnet
az network vnet subnet update \
  --name integration-subnet \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --nat-gateway nat-gateway

# Get static outbound IP
az network public-ip show \
  --name nat-gateway-ip \
  --resource-group <rg> \
  --query ipAddress -o tsv
```

## Architecture Patterns

### Hub-Spoke with VNet Integration

```
                     ┌─────────────────┐
                     │   App Service   │
                     │ (VNet Integrated)│
                     └────────┬────────┘
                              │
                     ┌────────▼────────┐
                     │  Spoke VNet     │
                     │ (Integration)   │
                     └────────┬────────┘
                              │ Peering
                     ┌────────▼────────┐
                     │   Hub VNet      │
                     │ (Shared Svcs)   │
                     └───┬────────┬────┘
                         │        │
              ┌──────────▼┐  ┌────▼─────────┐
              │ Firewall  │  │ VPN/ExpressRoute│
              └───────────┘  └──────────────┘
```

### Direct Access to PaaS

```
┌─────────────────┐     VNet         ┌────────────────┐
│   App Service   │────Integration───│  Private       │
│                 │                  │  Endpoints     │
└─────────────────┘                  ├────────────────┤
                                     │ - SQL Database │
                                     │ - Key Vault    │
                                     │ - Storage      │
                                     │ - Service Bus  │
                                     └────────────────┘
```

## Troubleshooting

### Test Connectivity from App Service

```bash
# From Kudu console (https://<app>.scm.azurewebsites.net/DebugConsole)

# Test DNS resolution
nameserver
nslookup <sql-server>.database.windows.net

# Test TCP connectivity
tcpping <sql-server>.database.windows.net:1433
tcpping <storage>.blob.core.windows.net:443

# Check effective routes
curl https://<app>.scm.azurewebsites.net/api/vnetcheck
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Cannot resolve private DNS | DNS not configured | Add private DNS zone link |
| Connection timeout | NSG blocking | Check NSG outbound rules |
| Subnet full | Out of IPs | Use larger subnet |
| Integration fails | Subnet not delegated | Add delegation to subnet |
