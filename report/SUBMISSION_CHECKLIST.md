# EWB Cloud Labs: Submission Checklist & Grading Rubric

Mapped directly to **Page 13** of the Student Project Workbook.

---

## 1. Submission Checklist

- [x] **Cover Page**:
  - Student Name
  - Batch Name
  - Project Title: `AWS VPC Peering`
  - AWS Region: `ap-south-1` (or chosen region)
  - Completion Date
- [x] **Architecture Diagram & Inventory**:
  - Network topology diagram
  - Resource inventory table with resource names, VPC/subnet bindings, and static IPv4 addresses
- [x] **Subnet CIDRs & Route Tables**:
  - `ewb-rt-a-public` associated with `ewb-a-public` (`0.0.0.0/0` -> IGW, `10.20.0.0/16` -> Peering)
  - `ewb-rt-a-private` associated with `ewb-a-private` (`10.20.0.0/16` -> Peering)
  - `ewb-rt-b-private` associated with `ewb-b-private` (`10.10.0.0/16` -> Peering)
- [x] **Active Peering Connection & Security Group Rules**:
  - Peering connection `ewb-a-b-peer` showing `Active` state
  - `ewb-sg-bastion`: Port 22 from Admin IP /32
  - `ewb-sg-app-a`: Port 22 from `10.10.1.10/32`, ICMP Echo from `10.20.1.10/32`
  - `ewb-sg-app-b`: Port 22 from `10.10.1.10/32`, ICMP Echo from `10.10.2.10/32`
- [x] **Verification Test Evidence**:
  - **Test 01 / Baseline Failure**: Ping from App-A to App-B before peering (100% loss)
  - **Test 02 / Forward Ping**: App-A to App-B (0% loss, 4 replies)
  - **Test 03 / Reverse Ping**: App-B to App-A (0% loss, 4 replies)
  - **Test 04 / Private SSH**: OpenSSH session into App-B via `ProxyJump ewb-bastion`
  - **Test 05 / Workload Isolation**: Proof that neither App-A nor App-B has a public IPv4 address
- [x] **Controlled Failure Experiment**:
  - Removed ICMP rule on App-B -> ping fails
  - Restored ICMP rule -> ping resumes
  - Technical explanation included
- [x] **Viva Explanations**:
  - All 4 questions from Page 12 answered in depth
- [x] **Cleanup Evidence**:
  - Proof of instance termination, peering deletion, route table and VPC deletion
- [x] **PDF Deliverable**:
  - Named according to requirement: `YourName_EWB_VPC_Peering.pdf`

---

## 2. Evaluation / 100 Marks Rubric

| Assessment Area | Marks | Criteria |
|---|---|---|
| **Architecture, CIDRs & Resource Inventory** | 15 | Non-overlapping CIDRs (`10.10.0.0/16`, `10.20.0.0/16`), exact resource names matching workbook, static private IP assignment. |
| **Subnets, IGW & Route Associations** | 20 | Explicit route table associations for all 3 subnets. Internet gateway attached only to VPC A. No IGW on VPC B. |
| **Peering plus Forward & Return Routes** | 20 | Active peering connection (`ewb-a-b-peer`). Symmetric peering routes configured in `ewb-rt-a-private`, `ewb-rt-b-private`, and `ewb-rt-a-public`. |
| **Security Rules & Private SSH Access** | 20 | Scoped `/32` rules on all private security groups. Successful OpenSSH `ProxyJump` access without copying private key to bastion. |
| **Positive & Negative Test Evidence** | 15 | Documented baseline failure, forward/reverse ping success, and controlled ICMP removal/recovery test with real terminal outputs. |
| **Report Clarity, Viva & Cleanup Evidence** | 10 | Well-formatted single PDF report, clear explanations of bidirectional routing and non-transitivity, clean account verification. |
| **Total Marks** | **100** | |
