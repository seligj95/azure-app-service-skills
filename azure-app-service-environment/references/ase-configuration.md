# App Service Environment v3 Configuration

## ASE v3 Creation

### Prerequisites

- Dedicated subnet (/24 recommended, minimum /25)
- Subnet must be empty and delegated to `Microsoft.Web/hostingEnvironments`

### Create ASE v3

```bash
# Create subnet for ASE
az network vnet subnet create \
  --name ase-subnet \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --address-prefixes 10.0.10.0/24 \
  --delegations Microsoft.Web/hostingEnvironments

# Create ASE v3 (External - public VIP)
az appservice ase create \
  --name <ase-name> \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --subnet ase-subnet \
  --kind ASEv3

# Create ASE v3 (Internal - ILB, private only)
az appservice ase create \
  --name <ase-name> \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --subnet ase-subnet \
  --virtual-ip-type Internal \
  --kind ASEv3
```

### Zone Redundant ASE

```bash
az appservice ase create \
  --name <ase-name> \
  --resource-group <rg> \
  --vnet-name <vnet-name> \
  --subnet ase-subnet \
  --zone-redundant \
  --kind ASEv3
```

**Requirements for Zone Redundancy:**
- Regions with 3+ availability zones
- Minimum 9 instances (3 per zone)
- Cannot be changed after creation

## Create App Service Plan in ASE

```bash
# Create Isolated v2 plan
az appservice plan create \
  --name <plan-name> \
  --resource-group <rg> \
  --app-service-environment <ase-name> \
  --sku I1V2 \
  --is-linux  # or omit for Windows
```

### Isolated v2 SKU Options

| SKU | vCPU | Memory | Storage |
|-----|------|--------|---------|
| I1V2 | 2 | 8 GB | 250 GB |
| I2V2 | 4 | 16 GB | 250 GB |
| I3V2 | 8 | 32 GB | 250 GB |
| I4V2 | 16 | 64 GB | 250 GB |
| I5V2 | 32 | 128 GB | 250 GB |
| I6V2 | 64 | 256 GB | 250 GB |

### Memory-Optimized Isolated SKUs

| SKU | vCPU | Memory | Use Case |
|-----|------|--------|----------|
| I1MV2 | 2 | 16 GB | Memory-intensive apps |
| I2MV2 | 4 | 32 GB | In-memory caching |
| I3MV2 | 8 | 64 GB | Large data processing |
| I4MV2 | 16 | 128 GB | Enterprise workloads |
| I5MV2 | 32 | 256 GB | Heavy memory apps |

## DNS Configuration for Internal ASE (ILB)

### Get ILB IP Address

```bash
# Get ASE internal IP
az appservice ase show \
  --name <ase-name> \
  --resource-group <rg> \
  --query "internalInboundIpAddresses[0]" -o tsv
```

### Configure Private DNS Zone

```bash
# Create private DNS zone for ASE
az network private-dns zone create \
  --resource-group <rg> \
  --name "<ase-name>.appserviceenvironment.net"

# Link to VNet
az network private-dns link vnet create \
  --resource-group <rg> \
  --zone-name "<ase-name>.appserviceenvironment.net" \
  --name ase-dns-link \
  --virtual-network <vnet-name> \
  --registration-enabled false

# Create wildcard A record for all apps
ILB_IP=$(az appservice ase show --name <ase-name> --resource-group <rg> --query "internalInboundIpAddresses[0]" -o tsv)

az network private-dns record-set a add-record \
  --resource-group <rg> \
  --zone-name "<ase-name>.appserviceenvironment.net" \
  --record-set-name "*" \
  --ipv4-address $ILB_IP

# Create @ record for ASE itself
az network private-dns record-set a add-record \
  --resource-group <rg> \
  --zone-name "<ase-name>.appserviceenvironment.net" \
  --record-set-name "@" \
  --ipv4-address $ILB_IP

# Create SCM wildcard record
az network private-dns record-set a add-record \
  --resource-group <rg> \
  --zone-name "<ase-name>.appserviceenvironment.net" \
  --record-set-name "*.scm" \
  --ipv4-address $ILB_IP
```

### App URLs in ILB ASE

```
App URL:        https://<app-name>.<ase-name>.appserviceenvironment.net
SCM/Kudu URL:   https://<app-name>.scm.<ase-name>.appserviceenvironment.net
```

## Custom Domain with ILB ASE

### Create Custom Domain

```bash
# Add custom domain to app
az webapp config hostname add \
  --webapp-name <app-name> \
  --resource-group <rg> \
  --hostname www.contoso.com
```

### Configure Certificate

```bash
# Upload certificate
az webapp config ssl upload \
  --name <app-name> \
  --resource-group <rg> \
  --certificate-file ./certificate.pfx \
  --certificate-password <password>

# Bind SSL
az webapp config ssl bind \
  --name <app-name> \
  --resource-group <rg> \
  --certificate-thumbprint <thumbprint> \
  --ssl-type SNI
```

### Update DNS for Custom Domain

```bash
# In your DNS provider or private DNS zone
# Create CNAME or A record pointing to ASE ILB IP
az network private-dns record-set a add-record \
  --resource-group <rg> \
  --zone-name "contoso.com" \
  --record-set-name "www" \
  --ipv4-address $ILB_IP
```

## NSG Configuration for ASE

### Required Inbound Rules

```bash
az network nsg create --name ase-nsg --resource-group <rg>

# Allow App Service management (required)
az network nsg rule create \
  --nsg-name ase-nsg \
  --resource-group <rg> \
  --name AllowAppServiceManagement \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol '*' \
  --source-address-prefixes AppServiceManagement \
  --destination-port-ranges 454-455

# Allow HTTP/HTTPS (for external ASE or ILB with inbound traffic)
az network nsg rule create \
  --nsg-name ase-nsg \
  --resource-group <rg> \
  --name AllowHTTPS \
  --priority 200 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes '*' \
  --destination-port-ranges 443

# Allow Azure Load Balancer
az network nsg rule create \
  --nsg-name ase-nsg \
  --resource-group <rg> \
  --name AllowLoadBalancer \
  --priority 300 \
  --direction Inbound \
  --access Allow \
  --protocol '*' \
  --source-address-prefixes AzureLoadBalancer \
  --destination-port-ranges '*'
```

### Required Outbound Rules

```bash
# Allow outbound to Azure services
az network nsg rule create \
  --nsg-name ase-nsg \
  --resource-group <rg> \
  --name AllowAzureOut \
  --priority 100 \
  --direction Outbound \
  --access Allow \
  --protocol '*' \
  --destination-address-prefixes AzureCloud \
  --destination-port-ranges '*'

# Allow DNS
az network nsg rule create \
  --nsg-name ase-nsg \
  --resource-group <rg> \
  --name AllowDNS \
  --priority 200 \
  --direction Outbound \
  --access Allow \
  --protocol '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 53

# Allow NTP
az network nsg rule create \
  --nsg-name ase-nsg \
  --resource-group <rg> \
  --name AllowNTP \
  --priority 300 \
  --direction Outbound \
  --access Allow \
  --protocol Udp \
  --destination-address-prefixes '*' \
  --destination-port-ranges 123
```

## Scaling ASE

### Scale App Service Plan

```bash
# Scale up (change SKU)
az appservice plan update \
  --name <plan-name> \
  --resource-group <rg> \
  --sku I2V2

# Scale out (add instances)
az appservice plan update \
  --name <plan-name> \
  --resource-group <rg> \
  --number-of-workers 5
```

### Autoscale in ASE

```bash
az monitor autoscale create \
  --resource-group <rg> \
  --resource <plan-name> \
  --resource-type Microsoft.Web/serverfarms \
  --min-count 2 \
  --max-count 10 \
  --count 2

az monitor autoscale rule create \
  --resource-group <rg> \
  --autoscale-name <rule-name> \
  --condition "CpuPercentage > 70 avg 5m" \
  --scale out 1
```

## ASE Upgrade Preference

```bash
# Set upgrade preference (Early, Late, Manual, None)
az appservice ase update \
  --name <ase-name> \
  --resource-group <rg> \
  --upgrade-preference Manual
```

## Monitoring ASE

### Check ASE Health

```bash
az appservice ase show \
  --name <ase-name> \
  --resource-group <rg> \
  --query "provisioningState"
```

### View Front-End Metrics

```bash
# ASE front-end CPU
az monitor metrics list \
  --resource <ase-resource-id> \
  --metric "FrontEndCpuPercentage" \
  --interval PT5M
```

## Cost Considerations

| Component | Billing |
|-----------|---------|
| Isolated SKU | Per instance-hour |
| Zone Redundancy | 3x minimum instances |
| Reserved Instances | 1-3 year savings |

**Note**: ASE v3 eliminated the stamp fee for single-tenant. Costs are now primarily instance-based.
