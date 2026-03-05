# Threat Model – LightUP Energy Azure Deployment

## Threat: Unauthorized Lateral Movement
Mitigation:
- Scoped RBAC
- Separate Production and NonProduction management groups

## Threat: Brute Force Attacks (RDP/SSH)
Mitigation:
- No public IP addresses
- Azure Bastion for secure administrative access

## Threat: Data Exfiltration
Mitigation:
- Storage firewall rules
- VNet service endpoints

## Threat: Credential Stuffing
Mitigation:
- Log Analytics detection using KQL
- Alerting for failed logins

## Threat: Ransomware
Mitigation:
- Azure Backup
- Soft Delete enabled
