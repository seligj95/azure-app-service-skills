# Private Endpoint Configuration

Private endpoints enable inbound connectivity to App Service over private IP.

## Create Private Endpoint for App Service

### Prerequisites

- App Service Plan: Basic or higher
- Dedicated subnet for private endpoints (separate from VNet integration subnet)

### Setup

```bash
# Create subnet for private endpoints
az network vnet subnet create \
  --name private-endpoints-subnet \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --address-prefixes 10.0.2.0/24 \
  --disable-private-endpoint-network-policies true

# Create private endpoint
az network private-endpoint create \
  --name <app-name>-pe \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --subnet private-endpoints-subnet \
  --private-connection-resource-id <app-service-resource-id> \
  --group-id sites \
  --connection-name <app-name>-connection
```

### Get Private Endpoint IP

```bash
# Get the private IP address
az network private-endpoint show \
  --name <app-name>-pe \
  --resource-group <rg> \
  --query "customDnsConfigurations[0].ipAddresses[0]" -o tsv
```

## DNS Configuration

### Azure Private DNS Zone (Recommended)

```bash
# Create private DNS zone
az network private-dns zone create \
  --resource-group <rg> \
  --name "privatelink.azurewebsites.net"

# Link zone to VNet
az network private-dns link vnet create \
  --resource-group <rg> \
  --zone-name "privatelink.azurewebsites.net" \
  --name appservice-dns-link \
  --virtual-network <vnet-name> \
  --registration-enabled false

# Create DNS zone group (auto-registers DNS records)
az network private-endpoint dns-zone-group create \
  --resource-group <rg> \
  --endpoint-name <app-name>-pe \
  --name default \
  --private-dns-zone "privatelink.azurewebsites.net" \
  --zone-name privatelink-azurewebsites-net
```

### Manual DNS Record

```bash
# Get private endpoint IP
PE_IP=$(az network private-endpoint show \
  --name <app-name>-pe \
  --resource-group <rg> \
  --query "customDnsConfigurations[0].ipAddresses[0]" -o tsv)

# Create A record
az network private-dns record-set a add-record \
  --resource-group <rg> \
  --zone-name "privatelink.azurewebsites.net" \
  --record-set-name <app-name> \
  --ipv4-address $PE_IP

# Create A record for SCM site
az network private-dns record-set a add-record \
  --resource-group <rg> \
  --zone-name "privatelink.azurewebsites.net" \
  --record-set-name <app-name>.scm \
  --ipv4-address $PE_IP
```

## Disable Public Access

### Block All Public Traffic

```bash
# Disable public network access entirely
az webapp update \
  --name <app-name> \
  --resource-group <rg> \
  --set publicNetworkAccess=Disabled
```

### Allow Public with Restrictions

```bash
# Keep public enabled but restrict to specific IPs
az webapp config access-restriction add \
  --name <app-name> \
  --resource-group <rg> \
  --priority 100 \
  --rule-name "AllowCorporateVPN" \
  --ip-address 203.0.113.0/24 \
  --action Allow

# Default deny all other public traffic
az webapp config access-restriction set \
  --name <app-name> \
  --resource-group <rg> \
  --default-action Deny
```

## Private Endpoint for Deployment Slots

Each slot requires its own private endpoint.

```bash
# Create private endpoint for staging slot
az network private-endpoint create \
  --name <app-name>-staging-pe \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --subnet private-endpoints-subnet \
  --private-connection-resource-id <app-service-resource-id> \
  --group-id sites-staging \
  --connection-name <app-name>-staging-connection

# Add DNS record for staging slot
az network private-dns record-set a add-record \
  --resource-group <rg> \
  --zone-name "privatelink.azurewebsites.net" \
  --record-set-name <app-name>-staging \
  --ipv4-address <staging-pe-ip>
```

## SCM (Kudu) Site Access

Private endpoint also secures the SCM site.

```bash
# SCM site URL
https://<app-name>.scm.azurewebsites.net

# With private endpoint, resolves to:
<app-name>.scm.privatelink.azurewebsites.net → private IP
```

### Restrict SCM Access Separately

```bash
# Allow public access to main site, restrict SCM
az webapp config access-restriction add \
  --name <app-name> \
  --resource-group <rg> \
  --priority 100 \
  --scm-site true \
  --rule-name "AllowDevOps" \
  --ip-address 203.0.113.0/24 \
  --action Allow

az webapp config access-restriction set \
  --name <app-name> \
  --resource-group <rg> \
  --scm-site true \
  --default-action Deny
```

## Complete Private Architecture

```
                        Internet
                            │
                            │ (blocked if public disabled)
                            ▼
┌───────────────────────────────────────────────────────────┐
│                    Azure Region                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │                    VNet                              │ │
│  │  ┌─────────────────────────────────────────────┐   │ │
│  │  │  Private Endpoints Subnet (10.0.2.0/24)     │   │ │
│  │  │  ┌─────────────────────────────────────┐   │   │ │
│  │  │  │  App Service Private Endpoint       │   │   │ │
│  │  │  │  10.0.2.4                           │   │   │ │
│  │  │  └──────────────────┬──────────────────┘   │   │ │
│  │  └─────────────────────┼──────────────────────┘   │ │
│  │                        │                           │ │
│  │  ┌─────────────────────▼──────────────────────┐   │ │
│  │  │  App Service (only accessible via PE)      │   │ │
│  │  └─────────────────────┬──────────────────────┘   │ │
│  │                        │ VNet Integration          │ │
│  │  ┌─────────────────────▼──────────────────────┐   │ │
│  │  │  Integration Subnet (10.0.1.0/26)          │   │ │
│  │  │  (Outbound to Azure services/on-prem)      │   │ │
│  │  └────────────────────────────────────────────┘   │ │
│  └─────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────┘
```

## Comparison: Private Endpoint vs Service Endpoint vs Access Restrictions

| Feature | Private Endpoint | Service Endpoint | Access Restrictions |
|---------|-----------------|------------------|---------------------|
| Traffic Path | Private IP in VNet | Public IP via MS backbone | Public IP |
| DNS | Private DNS required | Public DNS | Public DNS |
| Cross-region | Yes | No | Yes |
| On-premises Access | Via VPN/ExpressRoute | No | Via public IP |
| Cost | Per-hour + data | Free | Free |
| Setup Complexity | Higher | Lower | Lowest |

## Troubleshooting

### Verify DNS Resolution

```bash
# From within VNet (VM, VPN client, etc.)
nslookup <app-name>.azurewebsites.net

# Should resolve to private IP (e.g., 10.0.2.4)
# NOT public IP (e.g., 20.x.x.x)
```

### Test Connectivity

```bash
# From within VNet
curl -v https://<app-name>.azurewebsites.net/health

# Should connect to private IP
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Resolves to public IP | DNS not configured | Add private DNS zone link |
| Connection refused | App still expects public | Check publicNetworkAccess setting |
| Certificate error | Wrong hostname | Use original hostname, not privatelink |
| SCM not accessible | Missing SCM DNS | Add SCM A record to DNS zone |
| Slot not accessible | Missing slot PE | Create separate private endpoint for slot |
