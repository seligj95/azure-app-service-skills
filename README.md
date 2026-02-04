# Azure App Service Skills

A collection of AI agent skills for Azure App Service development, deployment, and operations. These skills enhance your AI coding assistant with deep knowledge of Azure App Service best practices.

## Installation

```bash
npx skills add seligj95/azure-app-service-skills
```

## Available Skills

| Skill | Description |
|-------|-------------|
| **azure-app-service-best-practices** | Core best practices for App Service configuration, security, reliability, and performance |
| **azure-app-service-deployment** | CI/CD with GitHub Actions, deployment slots, Run From Package, zero-downtime deployments |
| **azure-app-service-monitoring** | Application Insights setup, KQL queries, alerts, availability tests, health checks |
| **azure-app-service-security** | Managed Identity, Key Vault integration, Easy Auth, access restrictions, TLS |
| **azure-app-service-networking** | VNet integration, private endpoints, Front Door, Traffic Manager, hybrid connections |
| **azure-app-service-environment** | App Service Environment v3 for isolated, dedicated deployments |
| **azure-app-service-troubleshooting** | HTTP error diagnosis, startup failures, Kudu tools, auto-heal configuration |

## When to Use

These skills are automatically triggered when you're working on:

- Deploying web apps to Azure App Service
- Setting up CI/CD pipelines for Azure
- Configuring security (Managed Identity, Key Vault, authentication)
- Troubleshooting App Service issues
- Optimizing performance and scaling
- Implementing networking (VNet, private endpoints)
- Working with App Service Environment (ASE)

## Skill Details

### Best Practices
The entry point skill covering security, reliability, performance, deployment, configuration, cost optimization, and monitoring rules. Start here for general App Service guidance.

### Deployment
Comprehensive CI/CD patterns including:
- GitHub Actions workflows with OIDC authentication
- Deployment slots and swap strategies
- Run From Package deployments
- Azure Pipelines integration

### Monitoring
Observability and alerting:
- Application Insights configuration
- KQL queries for common scenarios
- Alert rules for HTTP errors, response time, CPU
- Availability tests and health checks

### Security
Security hardening:
- Managed Identity setup
- Key Vault secret references
- Easy Auth (built-in authentication)
- Network access restrictions
- TLS and transport security

### Networking
Network architecture patterns:
- Regional VNet integration
- Private endpoints for inbound traffic
- Front Door and Traffic Manager for global distribution
- Hybrid connections for on-premises access
- NAT gateway for outbound IP control

### App Service Environment
Isolated environment for sensitive workloads:
- ASE v3 creation and configuration
- Isolated v2 SKU selection
- Internal vs external load balancer
- Zone redundancy
- DNS and certificate configuration

### Troubleshooting
Diagnostics and problem resolution:
- HTTP 5xx, 4xx error diagnosis
- Application startup failures
- Performance issues and slow responses
- Kudu console and diagnostic tools
- Auto-heal rule configuration

## Compatible Agents

These skills work with any agent that supports the [Agent Skills](https://agentskills.io/) standard:

- Claude Code
- GitHub Copilot
- Cursor
- Windsurf
- And more...

## Contributing

Issues and pull requests welcome!
