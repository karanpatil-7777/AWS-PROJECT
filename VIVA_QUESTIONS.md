# AWS VPC Peering: Viva & Technical Evaluation Guide

This guide provides answers and in-depth explanations for the evaluation questions from **Page 12** of the EWB Cloud Labs Student Project Workbook.

---

## 1. Why is the return route needed?

### Concise Answer:
IP communication is strictly **bidirectional**. While a route in VPC A allows an outbound packet (e.g., ICMP Echo Request or TCP SYN) to reach VPC B, VPC B's kernel cannot send the reply (ICMP Echo Reply or TCP SYN-ACK) back unless its own route table has an explicit route pointing to VPC A's CIDR (`10.10.0.0/16`) via the peering connection.

### Deep Dive:
- When host `10.10.2.10` transmits a packet to `10.20.1.10`, the route table `ewb-rt-a-private` evaluates the destination IP against its routing table. It finds a match: `10.20.0.0/16 -> pcx-xxxxxxxxxxxxxxxxx`. The packet traverses the AWS peering infrastructure and arrives at `ewb-app-b`.
- Upon receipt, the Linux networking stack on `ewb-app-b` constructs the response. The packet has:
  - **Source IP**: `10.20.1.10`
  - **Destination IP**: `10.10.2.10`
- Before transmitting, the local AWS VPC route table associated with Subnet B (`ewb-rt-b-private`) must look up the destination `10.10.2.10`.
- If no route for `10.10.0.0/16` exists targeting the peering connection, the packet matches no valid route (or blackholes) and is immediately discarded.
- Therefore, VPC peering requires **symmetric, two-way routing** configured on both ends.

---

## 2. Why is the App-B SSH source the bastion private IP?

### Concise Answer:
When connecting via OpenSSH **`ProxyJump`**, the client establishes an encrypted SSH transport tunnel to the Bastion host, and the Bastion daemon opens a secondary TCP socket from its own private network interface (`10.10.1.10`) directly to App-B (`10.20.1.10:22`). Consequently, from the perspective of App-B's network card and OS kernel, the incoming connection originates from `10.10.1.10`, not the administrator's remote public IP.

### Deep Dive:
- `ProxyJump` (or `ssh -J`) utilizes SSH port forwarding (`-W` / standard I/O forwarding channel).
- The laptop connects to `ewb-bastion` on port 22.
- The Bastion daemon invokes the OS system call `connect()` to initiate a TCP three-way handshake with `10.20.1.10:22`.
- The source IP in the IP header of this TCP SYN packet is set to the primary private IPv4 address assigned to the Bastion's elastic network interface (ENI): `10.10.1.10`.
- Because of this:
  - `ewb-sg-app-b` must permit inbound TCP 22 specifically from `10.10.1.10/32`.
  - App-B does **not** need to allow the administrator's laptop public IP.
  - The Bastion's subnet route table (`ewb-rt-a-public`) must also possess a route to `10.20.0.0/16 -> pcx-xxxx` so that the Bastion itself knows how to reach VPC B.

---

## 3. Why does Active peering not guarantee a successful ping?

### Concise Answer:
An **Active** peering status only indicates that the logical AWS control-plane peering handshake between the two VPCs was requested and accepted. For actual data packets (such as ICMP ping) to succeed, three independent network and security layers must also be satisfied:
1. **Route Tables** (Routing Layer)
2. **Security Groups & Network ACLs** (Filtering Layer)
3. **Operating System Firewalls** (Host OS Layer)

### Deep Dive:
| Layer | Failure Condition even if Peering is Active |
|---|---|
| **Route Tables** | If either `ewb-rt-a-private` or `ewb-rt-b-private` lacks the peer CIDR route targeting the `pcx-id`, packets are dropped by the VPC router. |
| **Security Groups** | Security groups default to deny all inbound traffic. If the target security group lacks an explicit ingress rule for `ICMP Echo Request (Type 8, Code 0)` from the source IP, packets are silently dropped at the ENI. |
| **Network ACLs** | If a custom NACL blocks ephemeral return ports or ICMP, packets are rejected at the subnet boundary. |
| **Host OS Firewall** | If `iptables`, `nftables`, or kernel flags (like `net.ipv4.icmp_echo_ignore_all = 1`) are active on the instance, the OS will ignore or drop the echo requests. |

---

## 4. Can VPC B use VPC A's internet gateway over peering?

### Concise Answer:
**No.** AWS VPC Peering is strictly **non-transitive** and does **not** support edge-to-edge routing. Traffic that enters a VPC via a VPC Peering connection cannot exit that VPC through an Internet Gateway, NAT Gateway, VPN Connection, or Direct Connect gateway.

### Deep Dive:
- In AWS networking:
  - **Edge-to-Edge Routing Restriction**: AWS VPC routers prohibit traffic originating from an outside peering connection from being routed to an attached gateway (IGW or VGW).
  - **Non-Transitivity**: If VPC C peers with VPC A, and VPC A peers with VPC B, VPC C cannot reach VPC B through VPC A (`A <-> B` and `A <-> C` does NOT imply `B <-> C`).
- If workloads in VPC B require internet access:
  - **Option 1**: Attach an Internet Gateway directly to VPC B and deploy public subnets / NAT Gateways inside VPC B.
  - **Option 2**: Replace simple VPC Peering with an **AWS Transit Gateway (TGW)** or centralized inspection VPC architecture where Transit Gateway route tables support transit and egress routing through a central egress VPC.

---

## 5. Additional Key Concepts

### Security Groups vs. Network ACLs
- **Security Groups**:
  - Operate at the **instance ENI layer**.
  - **Stateful**: If inbound ICMP or SSH is allowed, return traffic is automatically tracked in the connection state table and permitted regardless of outbound rules.
- **Network ACLs (NACLs)**:
  - Operate at the **subnet boundary**.
  - **Stateless**: Inbound and outbound rules must be explicitly defined. Outbound rules must include ephemeral ports (`1024-65535`) for return traffic.

### CIDR Planning
- VPC Peering **strictly forbids overlapping or matching IPv4 CIDRs**.
- For example, if VPC A is `10.10.0.0/16` and VPC B is `10.10.0.0/16`, AWS will reject the peering connection request with an error: `Overlapping CIDRs`.
- Even if subnets within the two VPCs do not overlap (e.g. `10.10.1.0/24` and `10.10.2.0/24`), peering cannot be established if the parent VPC CIDRs overlap.
