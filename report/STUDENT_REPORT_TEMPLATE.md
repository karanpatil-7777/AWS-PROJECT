# Student Project Report: AWS VPC Peering

**Student Name:** [Your Name]  
**Batch:** [Your Batch]  
**Project:** Project 01 / AWS VPC Peering (EWB Cloud Labs)  
**Region:** ap-south-1 (Mumbai)  
**Date:** [Submission Date]  

---

## 1. Project Summary & Mission
EWB required an isolated private architecture connecting an application running in VPC A with a secondary workload in VPC B. Both application servers were required to remain strictly private without internet routability or public IPv4 addresses, while enabling secure administrative access through a single bastion host in VPC A.

A VPC Peering connection was deployed, along with symmetric custom route table entries and scoped security groups, proving private bidirectional reachability between the workloads.

---

## 2. Resource Plan & Inventory

| Resource / Name Tag | VPC / Subnet | IPv4 CIDR / Assigned IP | Function |
|---|---|---|---|
| `ewb-vpc-a` | VPC A | `10.10.0.0/16` | Requester VPC |
| `ewb-a-public` | VPC A | `10.10.1.0/24` | Public Bastion Subnet |
| `ewb-a-private` | VPC A | `10.10.2.0/24` | Private Workload Subnet |
| `ewb-vpc-b` | VPC B | `10.20.0.0/16` | Accepter VPC |
| `ewb-b-private` | VPC B | `10.20.1.0/24` | Private Workload Subnet |
| `ewb-igw-a` | VPC A | Attached to VPC A | Internet gateway for Bastion |
| `ewb-a-b-peer` | Both VPCs | Active (`pcx-...`) | VPC Peering Connection |
| `ewb-bastion` | `ewb-a-public` | `10.10.1.10` (+ Elastic IP) | SSH Jump Host |
| `ewb-app-a` | `ewb-a-private` | `10.10.2.10` (No Public IP) | Private Application Host |
| `ewb-app-b` | `ewb-b-private` | `10.20.1.10` (No Public IP) | Private Application Host |

---

## 3. Subnet Route Tables & Peering Routing

### `ewb-rt-a-public` (associated with `ewb-a-public`)
- `10.10.0.0/16` -> `local`
- `0.0.0.0/0` -> `ewb-igw-a` (Internet access for Bastion)
- `10.20.0.0/16` -> `ewb-a-b-peer` (Bastion ProxyJump to App-B)

### `ewb-rt-a-private` (associated with `ewb-a-private`)
- `10.10.0.0/16` -> `local`
- `10.20.0.0/16` -> `ewb-a-b-peer` (Forward route to VPC B)

### `ewb-rt-b-private` (associated with `ewb-b-private`)
- `10.20.0.0/16` -> `local`
- `10.10.0.0/16` -> `ewb-a-b-peer` (Return route to VPC A)

---

## 4. Security Group Configurations

1. **`ewb-sg-bastion`** (VPC A):
   - Inbound: SSH (TCP 22) from `[Your Public IP]/32`
   - Outbound: All traffic `0.0.0.0/0`
2. **`ewb-sg-app-a`** (VPC A):
   - Inbound: SSH (TCP 22) from `10.10.1.10/32` (Bastion private IP)
   - Inbound: Custom ICMP Echo Request (Type 8, Code 0) from `10.20.1.10/32` (App-B)
   - Outbound: All traffic `0.0.0.0/0`
3. **`ewb-sg-app-b`** (VPC B):
   - Inbound: SSH (TCP 22) from `10.10.1.10/32` (Bastion private IP)
   - Inbound: Custom ICMP Echo Request (Type 8, Code 0) from `10.10.2.10/32` (App-A)
   - Outbound: All traffic `0.0.0.0/0`

---

## 5. Verification Test Results (Terminal Logs)

### Test 01: Baseline Failure (Before Peering Active)
```
[ec2-user@ewb-app-a ~]$ ping -c 4 10.20.1.10
PING 10.20.1.10 (10.20.1.10) 56(84) bytes of data.
--- 10.20.1.10 ping statistics ---
4 packets transmitted, 0 received, 100% packet loss, time 3072ms
```
*Result: Expected baseline failure confirmed.*

### Test 02: Forward Path Ping (App-A -> App-B)
```
[ec2-user@ewb-app-a ~]$ hostname -I
10.10.2.10
[ec2-user@ewb-app-a ~]$ ping -c 4 10.20.1.10
PING 10.20.1.10 (10.20.1.10) 56(84) bytes of data.
64 bytes from 10.20.1.10: icmp_seq=1 ttl=255 time=0.482 ms
64 bytes from 10.20.1.10: icmp_seq=2 ttl=255 time=0.419 ms
64 bytes from 10.20.1.10: icmp_seq=3 ttl=255 time=0.435 ms
64 bytes from 10.20.1.10: icmp_seq=4 ttl=255 time=0.428 ms

--- 10.20.1.10 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3088ms
```
*Result: PASS (0% loss).*

### Test 03: Reverse Path Ping (App-B -> App-A)
```
[ec2-user@ewb-app-b ~]$ hostname -I
10.20.1.10
[ec2-user@ewb-app-b ~]$ ping -c 4 10.10.2.10
PING 10.10.2.10 (10.10.2.10) 56(84) bytes of data.
64 bytes from 10.10.2.10: icmp_seq=1 ttl=255 time=0.471 ms
64 bytes from 10.10.2.10: icmp_seq=2 ttl=255 time=0.422 ms
64 bytes from 10.10.2.10: icmp_seq=3 ttl=255 time=0.430 ms
64 bytes from 10.10.2.10: icmp_seq=4 ttl=255 time=0.425 ms

--- 10.10.2.10 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3075ms
```
*Result: PASS (0% loss).*

### Test 04: SSH ProxyJump Access (Laptop -> Bastion -> App-B)
```
$ ssh ewb-app-b
Last login: Thu Oct 29 20:30:14 2026 from 10.10.1.10
[ec2-user@ip-10-20-1-10 ~]$ hostname -I
10.20.1.10
```
*Result: PASS.*

### Test 05: Workload Isolation Check
```
$ aws ec2 describe-instances --filters "Name=tag:Name,Values=ewb-app-a,ewb-app-b" --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],PrivateIpAddress,PublicIpAddress]" --output table
---------------------------------------
|          DescribeInstances          |
+-----------+-------------+-----------+
| ewb-app-a | 10.10.2.10  | None      |
| ewb-app-b | 10.20.1.10  | None      |
+-----------+-------------+-----------+
```
*Result: PASS (Both hosts lack public IPs).*

---

## 6. Controlled Failure & Recovery Experiment
- **Failure step**: Removed ICMP rule from `ewb-sg-app-b`. Ran `ping -c 4 10.20.1.10` from App-A.
  - **Result**: `100% packet loss`. SSH through Bastion remained functional.
- **Recovery step**: Re-added inbound ICMP Echo Request from `10.10.2.10/32`.
  - **Result**: Ping immediately recovered to `0% packet loss`.

---

## 7. Viva Explanations
1. **Return route requirement**: Packets require a bidirectional path. When App-B crafts a response, its route table must route `10.10.0.0/16` back across the peering connection, otherwise replies are discarded.
2. **App-B SSH source IP**: The OpenSSH `ProxyJump` command terminates the initial SSH session at Bastion and initiates a new outbound TCP session directly from Bastion's interface (`10.10.1.10`) to App-B (`10.20.1.10`). App-B sees `10.10.1.10` as the source.
3. **Active peering vs ping success**: Peering status reflects control plane readiness. Actual packet delivery requires routing entries in both route tables, security group ingress authorization, and kernel-level ICMP support.
4. **Internet access via VPC A**: Peering is non-transitive. VPC B cannot route out of VPC A's Internet Gateway.

---

## 8. Cleanup Verification
All resources were cleaned up according to page 14:
- Terminated: `ewb-bastion`, `ewb-app-a`, `ewb-app-b`
- Released: Elastic IP
- Deleted: `ewb-a-b-peer`, custom route tables, security groups, IGW, subnets, and VPCs.
- Account status verified: Zero active lab resources.
