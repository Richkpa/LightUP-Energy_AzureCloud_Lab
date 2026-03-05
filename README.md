## LightUP Energy – Azure Cloud Security Lab

---

Scenario: This lab simulation is designed for **LightUP Energy**, a regional power provider migrating its grid management and billing systems to Azure. LightUP Energy needs to host its "GridFlow" monitoring application and "VoltBill" customer portal in Azure. As the Lead Administrator, you must ensure the environment is secure, scalable, and resilient.

## Focus Areas

- Zero Trust network segmentation
- Least Privilege RBAC
- Azure Policy governance enforcement
- Bastion-based secure access
- Private backend infrastructure
- Architecture Diagram
- Azure Monitor threat detection (KQL)

### Security Controls Implemented

- Management Group: LightUP-Root
  - Production
  - NonProduction

![Management Group Structure](screenshots/Picture1.png)

Policy: Deny public IP creation in Production
- Policy Assignment
![Management Group Structure](screenshots/Picture27.png)

- Deny error message
![Management Group Structure](screenshots/Picture28.png)

- Compliance dashboard
![Management Group Structure](screenshots/Picture29.png)

## Lab 1: Manage Azure Identities and Governance

### Task

1. Create a management group called `LightUP-Root`.
2. Implement **RBAC** by assigning the "Virtual Machine Contributor" role to the Engineering team only for the `Grid-Prod-RG` resource group.
3. Apply an **Azure Policy** to restrict resource deployment to the **East US** region only to comply with energy regulations.

### Risk Prevented

**Unauthorized Lateral Movement & Compliance Violations.**  
By using RBAC and Policies, I prevent a junior admin from accidentally spinning up expensive resources in unauthorized overseas regions or deleting critical infrastructure.

---

## Lab 2: Configure and Manage Virtual Networking

### Task

1. Create a VNet `LightUP-VNet` with subnets: `AppSubnet`, `DBSubnet`, and `AzureBastionSubnet`.  
   ![VNet Subnets](screenshots/Picture2.png)

2. Configure a **Network Security Group (NSG)** rule allowing only HTTPS (443) to the `AppSubnet`.  
   ![NSG Rule](screenshots/Picture3.png)  
   **Subnet Association Blade**  
   ![Subnet Association](screenshots/Picture4.png)

3. Second VNet (Billing VNet)  
   - ARM deployment  
     ![ARM Deployment](screenshots/Picture5.png)  
   - Subnets tab showing both subnets  
     ![Subnets](screenshots/Picture6.png)  
   - `BillingSubnet` properties showing NSG association  
     ![NSG Association](screenshots/Picture7.png)

4. Set up **VNet Peering** between the Grid Monitoring VNet and the Billing VNet.  
   ![VNet Peering](screenshots/Picture8.png)  
   **Network Watcher Topology**  
   ![Network Watcher Topology](screenshots/Picture9.png)

5. Deploy an **Azure Load Balancer** to distribute traffic across the VMSS.  
   ![Load Balancer](screenshots/Picture10.png)

6. Configure **Azure DNS zone**: [lightupenergy.com](http://lightupenergy.com)  
   ![DNS Zone](screenshots/Picture11.png)

### Risk Prevented

**Network Intrusion & Traffic Congestion.**  
NSGs act as a firewall, blocking all traffic except what is strictly necessary (Least Privilege). Peering ensures low-latency, private communication without using the public internet.

---

## Lab 3: Implement and Manage Storage

### Task

1. Create a Storage Account `lightupstoragelogs` for grid sensor telemetry.  
   ![Storage Account Overview](screenshots/Picture12.png)

2. Configure **Lifecycle Management** to move data older than 30 days to **Archive Tier**.  
   ![Lifecycle Management Rule](screenshots/Picture13.png)  
   ![Lifecycle Management Settings](screenshots/Picture14.png)

3. Create an **Azure File Share** named `grid-configs` and mount it to a test VM using a drive letter.  
   ![File Share Creation](screenshots/Picture15.png)  
   **FileShare**  
   ![FileShare](screenshots/Picture16.png)  
   **Showing FileShare Mounted on VM**  
   ![Mounted Share](screenshots/Picture17.png)  
   **TestFile**  
   ![Test File](screenshots/Picture18.png)

### Risk Prevented

**Data Leakage & Cost Overruns.**  
Implementing firewall rules on the storage account ensures only the Grid-Prod VNet can access sensor data. Archive tiers prevent massive bills from "cold" log data.


## Lab 4: Deploy and Manage Azure Compute Resources

### Task

1. Deploy a **Virtual Machine Scale Set (VMSS)** for the "VoltBill" portal to handle spikes during billing cycles.  
   ![VMSS Overview](screenshots/Picture19.png)  
   **Networking tab showing no Public IP**  
   ![VMSS Networking](screenshots/Picture20.png)  
   **Instances list**  
   ![VMSS Instances](screenshots/Picture21.png)

2. Use a **Bicep/ARM Template** to automate the deployment of a Windows Server 2022 VM for the database.

3. Configure **Azure Bastion** to manage these VMs without exposing Public IPs.  
   ![Azure Bastion](screenshots/Picture22.png)

### Risk Prevented

**Brute Force Attacks & System Downtime.**  
Azure Bastion eliminates the risk of RDP/SSH port exposure (3389/22) to the public internet. VMSS prevents the website from crashing when thousands of customers log in simultaneously.

---

## Lab 5: Monitor and Back up Azure Resources

### Task

1. Create a **Recovery Services Vault** and enable **Azure Backup** for the database VM.  
   ![Recovery Services Vault](screenshots/Picture23.png)  
   **Overview Page**  
   ![Backup Overview](screenshots/Picture24.png)

2. Set up an **Azure Monitor Alert** to email you if the "GridFlow" VM CPU exceeds 80% for 5 minutes.  
   ![Alert Rule](screenshots/Picture25.png)

3. Create a **Log Analytics Workspace** and run a KQL query to find failed login attempts.  
   ![Log Analytics Query](screenshots/Picture26.png)

### Risk Prevented

**Ransomware & Resource Exhaustion.**  

Azure Backup provides "Soft Delete" protection, preventing a malicious actor from permanently deleting backups. Monitoring allows you to catch performance issues before the power grid monitoring fails.












