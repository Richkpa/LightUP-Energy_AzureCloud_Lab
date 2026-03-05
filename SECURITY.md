# Security Controls Implemented

## Identity & Access
- Role-Based Access Control (RBAC)
- Scoped permissions at Resource Group level
- No subscription-wide admin delegation

## Network Security
- NSG enforcing HTTPS-only inbound
- No Public IPs on backend resources
- Azure Bastion for secure management
- VNet Peering using private connectivity

## Data Protection
- Storage firewall (Selected Networks only)
- Lifecycle management to prevent data sprawl
- Azure Backup with Soft Delete enabled

## Monitoring & Threat Detection
- CPU threshold alerting
- Log Analytics Workspace integration
- KQL detection for failed login attempts (EventID 4625)

## Ransomware Protection
- Recovery Services Vault
- Soft Delete protection enabled
