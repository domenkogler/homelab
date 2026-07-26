## **Multi-VLAN DNS Integration Architecture**

By placing your infrastructure servers (Technitium and Pi-hole) on a dedicated **management subnet**, you ensure a highly secure, isolated layout.

The recommended setup leverages **Technitium's native Group policy** mapping. Technitium intercepts queries from different subnets and routes them to distinct upstream filters (including your local Pi-hole) based on the client's source IP address.

## ---

**Network Traffic Flow Matrix**

| Source Subnet | Core Services | Local DNS Processing | Target Upstream Filter | Primary Security Goal |
| :---- | :---- | :---- | :---- | :---- |
| **Management Subnet** | Hosts Technitium & Pi-hole | Direct Core Logic | Local System Loop | Infrastructure Isolation |
| **Main LAN Subnet** | Standard Devices | Technitium Group A | **Local Pi-hole IP** | Aggressive Ad-Blocking |
| **Kids Subnet** | Family Devices | Technitium Group B | **Cloudflare Families** (1.1.1.3) | Adult Content & Porn Filtering |
| **IoT Subnet** | Smart Home Gear | Technitium Group C | **Quad9 Secured** (9.9.9.9) | Malware & Botnet Command Blocking |

## ---

**Step-by-Step Integration Guide**

## **1\. MikroTik RouterOS Configuration**

You must configure the MikroTik firewall to allow cross-VLAN DNS and DHCP traffic from the user subnets exclusively to your Management server IPs, while blocking all other inter-VLAN communication.

* **Step A**: Create an address list containing all user subnets needing DNS access.  
* **Step B**: Add a firewall filter rule in the forward chain allowing UDP ports **53** (DNS) and **67-68** (DHCP) from that address list to your Technitium Management IP.  
* **Step C**: Keep your global inter-VLAN drop rule below this exception to maintain total subnet isolation.

## **2\. Technitium Subnet Group Configuration**

Technitium will act as the traffic cop, routing requests based on network origin.

* **Step A**: Navigate to **Settings** \> **Groups** in Technitium and create three new groups: Main-Group, Kids-Group, and IoT-Group.  
* **Step B**: Go to **Settings** \> **Subnet Groups** and map your structural IP ranges to these groups (e.g., mapping 192.168.20.0/24 to Kids-Group).  
* **Step C**: Edit the specific options for each group and assign their respective upstream forwarders as listed in the matrix above. Disable all internal Technitium blocklists to minimize RAM usage.

## **3\. Pi-hole Upstream Configuration**

Since Pi-hole is dedicated entirely to the Main LAN's ad-blocking needs, its configuration remains lean and efficient.

* **Step A**: In Pi-hole **Settings** \> **DNS**, set the upstream servers to standard public providers (e.g., Cloudflare 1.1.1.1 or Google 8.8.8.8).  
* **Step B**: Under **Conditional Forwarding**, enter your local domain suffix and point it to the **Technitium IP address** so Pi-hole logs can accurately resolve local hostnames instead of showing raw management-hop IPs.

---

If you are ready to implement the configuration, tell me:

* What are your **exact VLAN subnet IP pools** (e.g., 192.168.10.0/24)?  
* What is the **static IP address assigned to Technitium** on your management network?

I can generate the copy-paste **MikroTik CLI firewall rules** tailored precisely to your IP scheme.