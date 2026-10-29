# AWS VPC Peering Architecture & Technical Reference

This document provides architectural details, packet flow analyses, and design decisions for the **EWB Cloud Labs VPC Peering Project**.

---

## 1. High-Level Network Topology

```
+-----------------------------------------------------------------------------------------+
|                                      YOUR LAPTOP                                        |
|                          (Local OpenSSH Client + ewb-lab.pem)                           |
+-----------------------------------------------------------------------------------------+
                                           |
                                           | SSH (Port 22)
                                           v
+-----------------------------------------------------------------------------------------+
| AWS REGION: ap-south-1 (Mumbai)                                                         |
|                                                                                         |
|  +----------------------------------------------------+                                 |
|  | VPC A (ewb-vpc-a): 10.10.0.0/16                    |                                 |
|  |                                                    |                                 |
|  |  +---------------------------+                     |                                 |
|  |  | Internet Gateway          |                     |                                 |
|  |  | (ewb-igw-a)               |                     |                                 |
|  |  +-------------+-------------+                     |                                 |
|  |                |                                   |                                 |
|  |  +-------------v-------------+                     |                                 |
|  |  | Public Subnet A           |                     |                                 |
|  |  | (ewb-a-public:10.10.1.0/24|                     |                                 |
|  |  |                           |                     |                                 |
|  |  |  [ ewb-bastion ]          |                     |                                 |
|  |  |  Private: 10.10.1.10      |                     |                                 |
|  |  |  Public:  Elastic IPv4    |                     |                                 |
|  |  |  SG: ewb-sg-bastion       |                     |                                 |
|  |  +-------------+-------------+                     |                                 |
|  |                |                                   |                                 |
|  |  +-------------v-------------+                     |   +--------------------------+  |
|  |  | Private Subnet A          |     VPC Peering     |   | VPC B (ewb-vpc-b)        |  |
|  |  | (ewb-a-private:10.10.2.0) |    ewb-a-b-peer     |   | 10.20.0.0/16             |  |
|  |  |                           |                     |   | (No Internet Gateway)    |  |
|  |  |  [ ewb-app-a ]            | <=================> |   |                          |  |
|  |  |  Private: 10.10.2.10      |   Direct Private    |   |  +--------------------+  |  |
|  |  |  No Public IP             |      Routing        |   |  | Private Subnet B   |  |  |
|  |  |  SG: ewb-sg-app-a         |                     |   |  | (ewb-b-private)    |  |  |
|  |  +---------------------------+                     |   |  | 10.20.1.0/24       |  |  |
|  |                                                    |   |  |                    |  |  |
|  |                                                    |   |  |  [ ewb-app-b ]     |  |  |
|  |                                                    |   |  |  Priv: 10.20.1.10  |  |  |
|  |                                                    |   |  |  No Public IP      |  |  |
|  |                                                    |   |  |  SG: ewb-sg-app-b  |  |  |
|  |                                                    |   |  +--------------------+  |  |
|  +----------------------------------------------------+   +--------------------------+  |
+-----------------------------------------------------------------------------------------+
```

---

## 2. Resource Addressing & Subnet Specifications

| Resource Name | Logical Resource | CIDR Block / IPv4 | Route Table | Security Group |
|---|---|---|---|---|
| `ewb-vpc-a` | Requester VPC | `10.10.0.0/16` | N/A | N/A |
| `ewb-a-public` | VPC A Public Subnet | `10.10.1.0/24` | `ewb-rt-a-public` | N/A |
| `ewb-a-private` | VPC A Private Subnet | `10.10.2.0/24` | `ewb-rt-a-private` | N/A |
| `ewb-vpc-b` | Accepter VPC | `10.20.0.0/16` | N/A | N/A |
| `ewb-b-private` | VPC B Private Subnet | `10.20.1.0/24` | `ewb-rt-b-private` | N/A |
| `ewb-bastion` | Public Jump Host | `10.10.1.10` (+ Elastic IP) | `ewb-rt-a-public` | `ewb-sg-bastion` |
| `ewb-app-a` | VPC A Private Workload | `10.10.2.10` (No Public IP) | `ewb-rt-a-private` | `ewb-sg-app-a` |
| `ewb-app-b` | VPC B Private Workload | `10.20.1.10` (No Public IP) | `ewb-rt-b-private` | `ewb-sg-app-b` |

---

## 3. Packet Flow Scenarios

### Scenario A: Remote SSH Administration via ProxyJump
```
[Laptop] 
    |  (1) TCP SYN -> Bastion Public IP:22
    v
[Internet Gateway (ewb-igw-a)]
    |
    v
[ewb-bastion (10.10.1.10)]
    |  (2) Bastion daemon receives authenticated SSH connection
    |  (3) Bastion opens secondary TCP SYN: 10.10.1.10:random -> 10.20.1.10:22
    v
[ewb-rt-a-public] -> Matches 10.20.0.0/16 -> Targets ewb-a-b-peer
    |
    v
[VPC Peering Connection]
    |
    v
[ewb-app-b (10.20.1.10)]
    |  (4) ewb-sg-app-b inspects packet: Source is 10.10.1.10 (Bastion IP), Port 22 -> ALLOW
    |  (5) TCP SYN-ACK reply generated: 10.20.1.10:22 -> 10.10.1.10:random
    v
[ewb-rt-b-private] -> Matches 10.10.0.0/16 -> Targets ewb-a-b-peer
    |
    v
[Back to Bastion -> End-to-end encrypted session delivered to Laptop terminal]
```

### Scenario B: ICMP Ping from App-A to App-B
1. **App-A (`10.10.2.10`)** emits ICMP Echo Request (Type 8) to `10.20.1.10`.
2. **Subnet Route Table (`ewb-rt-a-private`)**:
   - `10.10.0.0/16` -> `local` (No match for `10.20.1.10`)
   - `10.20.0.0/16` -> `ewb-a-b-peer` (**Match found!**)
3. **AWS Peering Fabric**: Routes the frame directly across the high-speed AWS network backbone.
4. **App-B ENI**:
   - Evaluates `ewb-sg-app-b`: Rule allows ICMP Echo Request from `10.10.2.10/32`. **Packet permitted**.
5. **App-B Kernel**:
   - Formulates ICMP Echo Reply (Type 0) directed to `10.10.2.10`.
6. **Subnet Route Table (`ewb-rt-b-private`)**:
   - `10.20.0.0/16` -> `local` (No match for `10.10.2.10`)
   - `10.10.0.0/16` -> `ewb-a-b-peer` (**Match found!**)
7. **App-A ENI**:
   - Evaluates `ewb-sg-app-a`: Because security groups are stateful, return traffic for an initiated ICMP request is tracked and permitted automatically.
8. **App-A OS**: Receives Echo Reply in ~0.4ms.

---

## 4. Key Design Principles & Security Posture

1. **Non-Overlapping IP Space**:
   - `10.10.0.0/16` and `10.20.0.0/16` are entirely disjoint CIDR blocks.
   - Any attempt to peer two VPCs with overlapping CIDRs is rejected at the API level by AWS.

2. **Least Privilege Ingress**:
   - The private instances `ewb-app-a` and `ewb-app-b` have no public IP addresses assigned.
   - Inbound SSH is limited exclusively to `/32` (the Bastion host's private IP `10.10.1.10/32`).
   - Inbound ICMP is limited strictly to the peer node's `/32` private IP.
   - Even if compromised, neither private host can reach external servers for command-and-control (C2) because neither subnet has an Internet route (`0.0.0.0/0`).

3. **Non-Transitive Peering Guarantee**:
   - VPC B has zero egress to the internet. Traffic from VPC B cannot traverse VPC A to access `ewb-igw-a`.
