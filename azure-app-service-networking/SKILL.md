---
name: azure-app-service-networking
description: Configure Azure App Service networking including VNet integration, private endpoints, hybrid connections, and traffic management. Use when connecting apps to virtual networks, securing backend access, configuring private endpoints, setting up Front Door or Traffic Manager, or troubleshooting network connectivity.
---

## When to Apply

Reference these guidelines when:

- Connecting App Service to a virtual network
- Accessing private resources (databases, storage, VMs)
- Configuring private endpoints for inbound access
- Setting up global load balancing with Front Door
- Implementing multi-region deployments
- Troubleshooting network connectivity

## Networking Options

| Feature | Direction | Use Case |
|---------|-----------|----------|
| VNet Integration | Outbound | Access private resources from app |
| Private Endpoints | Inbound | Restrict app to private network |
| Hybrid Connections | Outbound | Access on-premises without VPN |
| Access Restrictions | Inbound | IP/VNet-based access control |
| Service Endpoints | Outbound | Secure access to Azure services |

## VNet Integration

### Overview

VNet integration allows your app to make outbound calls through a virtual network. Traffic to private resources flows through the VNet instead of the public internet.

**Requirements:**
- Basic+ App Service plan (Standard recommended)
- Dedicated subnet with `/28` minimum (64 IPs with `/26` recommended)
- Subnet delegated to `Microsoft.Web/serverFarms`

### Enable VNet Integration

```bash
# Create subnet for App Service (if needed)
az network vnet subnet create \
  --name appservice-subnet \
  --vnet-name <vnet> \
  --resource-group <rg> \
  --address-prefixes 10.0.1.0/26 \
  --delegations Microsoft.Web/serverFarms

# Enable VNet integration
az webapp vnet-integration add \
  --name <app> \
  --resource-group <rg> \
  --vnet <vnet> \
  --subnet appservice-subnet

# Verify integration
az webapp vnet-integration list --name <app> --resource-group <rg>
```

### Route All Traffic Through VNet

By default, only RFC1918 private traffic routes through VNet. To route all traffic:

```bash
# Route all outbound traffic through VNet
az webapp config appsettings set \
  --name <app> --resource-group <rg> \
  --settings WEBSITE_VNET_ROUTE_ALL=1

# Or use site property (recommended)
az resource update \
  --resource-group <rg> \
  --name <app> \
  --resource-type "Microsoft.Web/sites" \
  --set properties.vnetRouteAllEnabled=true
```

### Disconnect VNet Integration

```bash
az webapp vnet-integration remove --name <app> --resource-group <rg>
```

## Private Endpoints (Inbound)

Private endpoints make your app accessible only from within a virtual network.

### Create Private Endpoint

```bash
# Disable public access first (optional but recommended)
az webapp update \
  --name <app> --resource-group <rg> \
  --set publicNetworkAccess=Disabled

# Create private endpoint
az network private-endpoint create \
  --name <app>-pe \
  --resource-group <rg> \
  --vnet-name <vnet> \
  --subnet pe-subnet \
  --private-connection-resource-id $(az webapp show -n <app> -g <rg> --query id -o tsv) \
  --group-id sites \
  --connection-name <app>-connection

# Create private DNS zone
az network private-dns zone create \
  --resource-group <rg> \
  --name privatelink.azurewebsites.net

# Link DNS zone to VNet
az network private-dns link vnet create \
  --resource-group <rg> \
  --zone-name privatelink.azurewebsites.net \
  --name <vnet>-link \
  --virtual-network <vnet> \
  --registration-enabled false

# Create DNS record
az network private-endpoint dns-zone-group create \
  --resource-group <rg> \
  --endpoint-name <app>-pe \
  --name default \
  --private-dns-zone privatelink.azurewebsites.net \
  --zone-name privatelink.azurewebsites.net
```

### Private Endpoint + VNet Integration

For full private networking (both inbound and outbound):

```
Internet ──X──> [Private Endpoint] ──> App Service ──> [VNet Integration] ──> Private Resources
                     │                                        │
                     └──── Private DNS ────────────────────────┘
```

## Hybrid Connections

Connect to on-premises resources without VPN or ExpressRoute.

```bash
# Create Hybrid Connection (via Azure Portal or ARM)
# Then configure on-premises Hybrid Connection Manager

# List hybrid connections
az webapp hybrid-connection list --name <app> --resource-group <rg>
```

**Requirements:**
- Standard+ App Service plan
- Hybrid Connection Manager installed on-premises
- Outbound HTTPS (443) from on-premises to Azure

## Service Endpoints

Secure Azure PaaS services (Storage, SQL, etc.) to only accept traffic from your VNet.

```bash
# Add service endpoint to subnet
az network vnet subnet update \
  --name appservice-subnet \
  --vnet-name <vnet> \
  --resource-group <rg> \
  --service-endpoints Microsoft.Storage Microsoft.Sql

# Configure Storage to accept VNet traffic
az storage account network-rule add \
  --account-name <storage> \
  --resource-group <rg> \
  --vnet-name <vnet> \
  --subnet appservice-subnet
```

## NAT Gateway

Get a dedicated outbound IP for your app (avoid SNAT exhaustion).

```bash
# Create public IP
az network public-ip create \
  --name nat-pip \
  --resource-group <rg> \
  --sku Standard \
  --allocation-method Static

# Create NAT Gateway
az network nat gateway create \
  --name app-nat-gw \
  --resource-group <rg> \
  --public-ip-addresses nat-pip \
  --idle-timeout 10

# Associate with subnet
az network vnet subnet update \
  --name appservice-subnet \
  --vnet-name <vnet> \
  --resource-group <rg> \
  --nat-gateway app-nat-gw
```

## Azure Front Door

Global load balancing with WAF, caching, and SSL offloading.

```bash
# Create Front Door profile
az afd profile create \
  --profile-name <fd-profile> \
  --resource-group <rg> \
  --sku Standard_AzureFrontDoor

# Create endpoint
az afd endpoint create \
  --profile-name <fd-profile> \
  --resource-group <rg> \
  --endpoint-name <endpoint-name> \
  --enabled-state Enabled

# Create origin group
az afd origin-group create \
  --profile-name <fd-profile> \
  --resource-group <rg> \
  --origin-group-name default-origin-group \
  --probe-request-type GET \
  --probe-protocol Https \
  --probe-path /health

# Add App Service as origin
az afd origin create \
  --profile-name <fd-profile> \
  --resource-group <rg> \
  --origin-group-name default-origin-group \
  --origin-name <app>-origin \
  --host-name <app>.azurewebsites.net \
  --origin-host-header <app>.azurewebsites.net \
  --http-port 80 \
  --https-port 443 \
  --priority 1 \
  --weight 1000 \
  --enabled-state Enabled

# Create route
az afd route create \
  --profile-name <fd-profile> \
  --resource-group <rg> \
  --endpoint-name <endpoint-name> \
  --route-name default-route \
  --origin-group default-origin-group \
  --supported-protocols Https \
  --https-redirect Enabled \
  --forwarding-protocol HttpsOnly
```

### Restrict App to Front Door Only

```bash
# Add access restriction for Front Door
az webapp config access-restriction add \
  --name <app> --resource-group <rg> \
  --rule-name "FrontDoor" \
  --priority 100 \
  --service-tag AzureFrontDoor.Backend \
  --action Allow \
  --http-header X-Azure-FDID=<front-door-id>

# Deny all other traffic
az webapp config access-restriction set \
  --name <app> --resource-group <rg> \
  --default-action Deny
```

## Traffic Manager

DNS-based global load balancing for multi-region deployments.

```bash
# Create Traffic Manager profile
az network traffic-manager profile create \
  --name <tm-profile> \
  --resource-group <rg> \
  --routing-method Performance \
  --unique-dns-name <tm-dns-name> \
  --ttl 30 \
  --protocol HTTPS \
  --port 443 \
  --path /health

# Add primary endpoint (East US)
az network traffic-manager endpoint create \
  --name eastus-endpoint \
  --profile-name <tm-profile> \
  --resource-group <rg> \
  --type azureEndpoints \
  --target-resource-id $(az webapp show -n <app-eastus> -g <rg> --query id -o tsv) \
  --endpoint-status Enabled

# Add secondary endpoint (West US)
az network traffic-manager endpoint create \
  --name westus-endpoint \
  --profile-name <tm-profile> \
  --resource-group <rg> \
  --type azureEndpoints \
  --target-resource-id $(az webapp show -n <app-westus> -g <rg> --query id -o tsv) \
  --endpoint-status Enabled
```

## Subnet Sizing Guide

| Scenario | Minimum Size | Recommended Size |
|----------|--------------|------------------|
| Single App Service plan | `/28` (11 usable) | `/27` (27 usable) |
| Production with scaling | `/27` | `/26` (59 usable) |
| Multi-plan (MPSJ) | `/26` | `/25` (123 usable) |
| Large scale production | `/26` | `/24` (251 usable) |

**IP Calculation:**
- Azure reserves 5 IPs per subnet
- Each App Service instance uses 1 IP
- Scale operations temporarily double IP usage
- Platform upgrades need spare IPs

## Troubleshooting

### Check VNet Integration

```bash
# List integrations
az webapp vnet-integration list --name <app> --resource-group <rg>

# Check private IP (in Kudu console)
# Environment variable: WEBSITE_PRIVATE_IP

# Test from Kudu console (tcpping)
tcpping <private-ip>:443
```

### DNS Resolution Issues

```bash
# Check DNS from Kudu console
nameresolver <hostname>

# Ensure private DNS zones are linked to VNet
az network private-dns link vnet list \
  --zone-name privatelink.azurewebsites.net \
  --resource-group <rg>
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Can't connect to private resource | Verify subnet delegation, check NSG rules |
| DNS not resolving | Link private DNS zone to VNet |
| Intermittent connectivity | Check subnet size, may be IP exhaustion |
| Can't reach on-premises | Verify VNet peering/VPN, check routing |

## References

- **VNet Integration Guide**: See [references/vnet-integration-guide.md](references/vnet-integration-guide.md) for outbound connectivity
- **Private Endpoint Guide**: See [references/private-endpoint-guide.md](references/private-endpoint-guide.md) for inbound connectivity
