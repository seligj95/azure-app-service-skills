---
name: azure-app-service-environment
description: Deploy and manage Azure App Service Environments (ASE v3) for isolated, high-scale workloads. Use when requiring complete network isolation, dedicated compute, high scale (200+ instances), compliance requirements, or single-tenant hosting. ASE is a separate product from standard App Service with different pricing and capabilities.
---

## When to Apply

Reference these guidelines when:

- Deploying applications requiring complete network isolation
- Hosting workloads with strict compliance requirements
- Scaling beyond 30 App Service plan instances
- Requiring dedicated single-tenant infrastructure
- Implementing internal-only applications
- Planning zone-redundant mission-critical deployments

## ASE vs Multitenant App Service

| Feature | Multitenant App Service | App Service Environment v3 |
|---------|------------------------|---------------------------|
| Network Model | Shared with VNet integration | Deployed directly in VNet |
| Isolation | Shared infrastructure | Single-tenant, dedicated |
| Max Scale | 30 instances per plan | 200 instances total |
| Pricing | Per instance | Per instance + base fee |
| Setup Complexity | Simple | Requires VNet planning |
| Cold Start | Possible | Minimal (dedicated) |
| Private by Default | No (requires PE) | Yes (internal VIP) |

**Choose ASE When:**
- Need complete network isolation without private endpoints
- Require >30 instances per App Service plan
- Compliance requires dedicated infrastructure
- Need zone redundancy for mission-critical apps
- Want simplified private networking

**Choose Multitenant When:**
- Standard isolation requirements (use private endpoints)
- Cost-sensitive workloads
- Simpler management preferred
- Scale requirements under 30 instances

## ASE v3 Architecture

```
Virtual Network
└── Subnet (/24 recommended, /27 minimum)
    └── App Service Environment v3
        ├── Internal Load Balancer (internal VIP)
        │   └── Private IP for all apps
        └── App Service Plans (Isolated v2 SKUs)
            ├── Windows Apps
            ├── Linux Apps
            └── Containers
```

## Create ASE v3

### Prerequisites

```bash
# Register resource provider (if needed)
az provider register --namespace Microsoft.Web

# Create VNet with ASE subnet
az network vnet create \
  --name <vnet-name> \
  --resource-group <rg> \
  --address-prefix 10.0.0.0/16 \
  --subnet-name ase-subnet \
  --subnet-prefix 10.0.0.0/24
```

### Create Internal ASE v3 (Recommended)

```bash
# Create internal ASE (private VIP)
az appservice ase create \
  --name <ase-name> \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --subnet ase-subnet \
  --kind asev3 \
  --virtual-ip-type Internal

# Wait for deployment (30-60 minutes)
az appservice ase show --name <ase-name> --resource-group <rg>
```

### Create External ASE v3

```bash
# Create external ASE (public VIP)
az appservice ase create \
  --name <ase-name> \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --subnet ase-subnet \
  --kind asev3 \
  --virtual-ip-type External
```

### Create Zone-Redundant ASE

```bash
# Zone redundancy available in supported regions
az appservice ase create \
  --name <ase-name> \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --subnet ase-subnet \
  --kind asev3 \
  --virtual-ip-type Internal \
  --zone-redundant
```

## App Service Plans in ASE

### Isolated v2 SKUs

| SKU | vCPU | Memory | Use Case |
|-----|------|--------|----------|
| I1v2 | 2 | 8 GB | Small workloads |
| I2v2 | 4 | 16 GB | Standard workloads |
| I3v2 | 8 | 32 GB | Heavy workloads |
| I4v2 | 16 | 64 GB | High-compute workloads |
| I5v2 | 32 | 128 GB | Extreme workloads |
| I6v2 | 64 | 256 GB | Maximum performance |
| I1mv2 | 2 | 16 GB | Memory-optimized small |
| I2mv2 | 4 | 32 GB | Memory-optimized medium |
| I3mv2 | 8 | 64 GB | Memory-optimized large |
| I4mv2 | 16 | 128 GB | Memory-optimized xlarge |
| I5mv2 | 32 | 256 GB | Memory-optimized max |

### Create App Service Plan

```bash
# Create Isolated v2 plan
az appservice plan create \
  --name <plan-name> \
  --resource-group <rg> \
  --app-service-environment <ase-name> \
  --sku I1v2 \
  --is-linux

# Scale plan
az appservice plan update \
  --name <plan-name> \
  --resource-group <rg> \
  --number-of-workers 5
```

### Create Web App

```bash
# Create app in ASE
az webapp create \
  --name <app-name> \
  --resource-group <rg> \
  --plan <plan-name> \
  --runtime "NODE:20-lts"
```

## DNS Configuration (Internal ASE)

Internal ASE requires private DNS configuration.

### Get ASE IP Addresses

```bash
# Get internal IP address
az appservice ase show \
  --name <ase-name> \
  --resource-group <rg> \
  --query internalInboundIpAddresses

# Apps will be at: <app-name>.<ase-name>.appserviceenvironment.net
```

### Create Private DNS Zone

```bash
# Create private DNS zone
az network private-dns zone create \
  --resource-group <rg> \
  --name <ase-name>.appserviceenvironment.net

# Link to VNet
az network private-dns link vnet create \
  --resource-group <rg> \
  --zone-name <ase-name>.appserviceenvironment.net \
  --name <vnet-name>-link \
  --virtual-network <vnet-name> \
  --registration-enabled false

# Create A record for apps (wildcard)
az network private-dns record-set a create \
  --resource-group <rg> \
  --zone-name <ase-name>.appserviceenvironment.net \
  --name "*"

az network private-dns record-set a add-record \
  --resource-group <rg> \
  --zone-name <ase-name>.appserviceenvironment.net \
  --record-set-name "*" \
  --ipv4-address <ase-internal-ip>

# Create A record for ASE management
az network private-dns record-set a create \
  --resource-group <rg> \
  --zone-name <ase-name>.appserviceenvironment.net \
  --name "@"

az network private-dns record-set a add-record \
  --resource-group <rg> \
  --zone-name <ase-name>.appserviceenvironment.net \
  --record-set-name "@" \
  --ipv4-address <ase-internal-ip>
```

## Network Security

### NSG Rules (Required for ASE v3)

ASE v3 has no management dependencies in customer VNet. Basic NSG rules:

```bash
# Create NSG
az network nsg create --name ase-nsg --resource-group <rg>

# Allow inbound HTTP/HTTPS
az network nsg rule create \
  --nsg-name ase-nsg --resource-group <rg> \
  --name AllowHTTP --priority 100 \
  --source-address-prefixes '*' \
  --destination-port-ranges 80 443 \
  --access Allow --direction Inbound

# Allow health probes (UDP 30000)
az network nsg rule create \
  --nsg-name ase-nsg --resource-group <rg> \
  --name AllowHealthProbe --priority 110 \
  --source-address-prefixes '*' \
  --destination-port-ranges 30000 \
  --protocol Udp \
  --access Allow --direction Inbound

# Associate NSG with subnet
az network vnet subnet update \
  --name ase-subnet \
  --vnet-name <vnet-name> \
  --resource-group <rg> \
  --network-security-group ase-nsg
```

### Route Tables

For forced tunneling (route all traffic through firewall):

```bash
# Create route table
az network route-table create \
  --name ase-routes \
  --resource-group <rg>

# Add route to firewall
az network route-table route create \
  --route-table-name ase-routes \
  --resource-group <rg> \
  --name to-firewall \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address <firewall-ip>

# Associate with subnet
az network vnet subnet update \
  --name ase-subnet \
  --vnet-name <vnet-name> \
  --resource-group <rg> \
  --route-table ase-routes
```

## Scaling

### Manual Scaling

```bash
# Scale out instances
az appservice plan update \
  --name <plan-name> \
  --resource-group <rg> \
  --number-of-workers 10

# Scale up SKU
az appservice plan update \
  --name <plan-name> \
  --resource-group <rg> \
  --sku I2v2
```

### ASE Limits

- **Total instances per ASE:** 200
- **Instances per plan:** 100
- **App Service plans per ASE:** Unlimited (within instance limit)

## Pricing

| Component | Cost Basis |
|-----------|------------|
| Base fee | Charged even if empty (equivalent to 1 I1v2 instance) |
| Instances | Per vCore hour (Isolated v2 rates) |
| Zone redundancy | No additional charge |
| Dedicated hosts | Additional per-host fee |

**Cost Optimization:**
- Use reserved instances (1-3 year) for predictable workloads
- Right-size SKUs based on actual usage
- Share ASE across multiple App Service plans

## Monitoring

```bash
# Get ASE status
az appservice ase show --name <ase-name> --resource-group <rg>

# List plans in ASE
az appservice plan list --resource-group <rg> \
  --query "[?hostingEnvironmentProfile.name=='<ase-name>']"

# Get instance count
az appservice ase list-addresses --name <ase-name> --resource-group <rg>
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Deployment stuck | ASE creation takes 1-2 hours; check activity log |
| Apps not accessible | Verify DNS records, check NSG rules |
| Scale fails | Check instance limits (200 total) |
| Slow performance | Consider larger SKU, check app health |

```bash
# Check ASE health
az appservice ase show --name <ase-name> --resource-group <rg> --query provisioningState

# View networking info
az appservice ase list-addresses --name <ase-name> --resource-group <rg>
```

## Migration from ASE v2

ASE v3 requires migration from v2. Key differences:
- No front-end scaling required (automatic)
- No networking dependencies in customer VNet
- Zone redundancy support
- Faster scaling
- New Isolated v2 SKUs

See [Azure documentation](https://learn.microsoft.com/en-us/azure/app-service/environment/migrate) for migration guide.

## References

- **Networking Patterns**: See [references/ase-networking.md](references/ase-networking.md)
- **Sizing Guide**: See [references/ase-sizing.md](references/ase-sizing.md)
