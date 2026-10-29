# EWB Cloud Labs: AWS VPC Peering Project

> **Connect two VPCs. Prove private connectivity.**  
> A complete, production-ready implementation of the AWS VPC Peering student project workbook (AWS Solutions Architect Associate).

---

## 📋 Table of Contents
1. [Architecture Overview](#-architecture-overview)
2. [Resource & IP Plan](#-resource--ip-plan)
3. [Deployment Options](#-deployment-options)
   - [Option A: 1-Click AWS CloudFormation](#option-a-aws-cloudformation-recommended-if-no-cli-installed)
   - [Option B: Terraform](#option-b-terraform)
   - [Option C: Automated Python / Boto3](#option-c-automated-python--boto3)
   - [Option D: AWS CLI (PowerShell / Bash)](#option-d-aws-cli-powershell--bash)
   - [Option E: AWS Management Console (Manual)](#option-e-aws-management-console-manual)
4. [SSH ProxyJump Configuration](#-ssh-proxyjump-configuration)
5. [Verification & Acceptance Tests](#-verification--acceptance-tests)
6. [Controlled Failure Experiment](#-controlled-failure-experiment)
7. [Student Deliverables & Report Generator](#-student-deliverables--report-generator)
8. [Viva & Technical Questions](#-viva--technical-questions)
9. [Cleanup Instructions](#-cleanup-instructions)

---

## 🏛️ Architecture Overview

The project creates two isolated VPCs with non-overlapping IPv4 CIDRs:
- **VPC A (`ewb-vpc-a`, `10.10.0.0/16`)**:
  - `ewb-a-public` (`10.10.1.0/24`): Houses `ewb-bastion` (`10.10.1.10`), attached to an Internet Gateway (`ewb-igw-a`).
  - `ewb-a-private` (`10.10.2.0/24`): Houses `ewb-app-a` (`10.10.2.10`), purely private.
- **VPC B (`ewb-vpc-b`, `10.20.0.0/16`)**:
  - `ewb-b-private` (`10.20.1.0/24`): Houses `ewb-app-b` (`10.20.1.10`), purely private.
  - **No Internet Gateway** is attached to VPC B.
- **VPC Peering Connection (`ewb-a-b-peer`)**:
  - Connects VPC A and VPC B directly over the AWS private network backbone.
- **Administration**:
  - OpenSSH `ProxyJump` routes SSH sessions through `ewb-bastion` to reach `ewb-app-a` and `ewb-app-b` without exposing private instances or copying private keys to the cloud.

---

## 📌 Resource & IP Plan

| Resource / Name Tag | VPC / Subnet | Assigned IPv4 | Public IPv4 | Security Group |
|---|---|---|---|---|
| `ewb-vpc-a` | VPC A | `10.10.0.0/16` | N/A | N/A |
| `ewb-a-public` | VPC A | `10.10.1.0/24` | N/A | N/A |
| `ewb-a-private` | VPC A | `10.10.2.0/24` | N/A | N/A |
| `ewb-vpc-b` | VPC B | `10.20.0.0/16` | N/A | N/A |
| `ewb-b-private` | VPC B | `10.20.1.0/24` | N/A | N/A |
| `ewb-bastion` | `ewb-a-public` | `10.10.1.10` | Elastic IP | `ewb-sg-bastion` (Port 22 from Admin /32) |
| `ewb-app-a` | `ewb-a-private` | `10.10.2.10` | **None** | `ewb-sg-app-a` (Port 22 from Bastion, ICMP from App-B) |
| `ewb-app-b` | `ewb-b-private` | `10.20.1.10` | **None** | `ewb-sg-app-b` (Port 22 from Bastion, ICMP from App-A) |
| `ewb-igw-a` | VPC A | Attached | N/A | N/A |
| `ewb-a-b-peer` | Peering | N/A | N/A | Status: `Active` |

---

## 🚀 Deployment Options

Choose any of the following methods to deploy the lab infrastructure:

### Option A: AWS CloudFormation (Recommended if no CLI installed)
1. Open the [AWS CloudFormation Console](https://console.aws.amazon.com/cloudformation).
2. Click **Create stack** > **With new resources (standard)**.
3. Select **Upload a template file** and choose:
   ```
   cloudformation/vpc-peering-lab.yaml
   ```
4. Enter your parameters:
   - **Stack name**: `ewb-vpc-peering-lab`
   - **StudentName**: Your name
   - **KeyPairName**: `ewb-lab` (make sure you created this key pair in EC2 first)
   - **AdminCidr**: Your workstation's public IP `/32` (or leave default `0.0.0.0/0`)
5. Click **Next** > **Create stack**.
6. When complete (~2 minutes), inspect the **Outputs** tab for your Bastion Public IP.

---

### Option B: Terraform
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your region and student name
terraform init
terraform apply
```

---

### Option C: Automated Python / Boto3
```bash
python python_lab/deploy.py --student-name "YourName" --region "ap-south-1"
```
*Automatically validates credentials, creates/checks the key pair, provisions the CloudFormation stack, and updates `~/.ssh/config`.*

---

### Option D: AWS CLI (PowerShell / Bash)
**PowerShell:**
```powershell
.\scripts\deploy-aws-cli.ps1 -StudentName "YourName" -Region "ap-south-1"
```

**Bash / WSL:**
```bash
chmod +x scripts/deploy-aws-cli.sh
./scripts/deploy-aws-cli.sh ap-south-1 ewb-lab "YourName"
```

---

### Option E: AWS Management Console (Manual)
Follow the comprehensive step-by-step console guide:
📄 [CONSOLE_WALKTHROUGH.md](file:///e:/AWS/CONSOLE_WALKTHROUGH.md)

---

## 🔑 SSH ProxyJump Configuration

Once your Bastion is running with its public IP:

### On Windows PowerShell:
Run the automatic configuration script (which also sets correct NTFS key permissions):
```powershell
.\scripts\setup_ssh.ps1 -BastionPublicIp <BASTION_PUBLIC_IP>
```

### Manual `~/.ssh/config` Entry:
```ssh-config
Host ewb-bastion
  HostName <BASTION_PUBLIC_IP>
  User ec2-user
  IdentityFile ~/.ssh/ewb-lab.pem
  IdentitiesOnly yes

Host ewb-app-a
  HostName 10.10.2.10
  User ec2-user
  IdentityFile ~/.ssh/ewb-lab.pem
  IdentitiesOnly yes
  ProxyJump ewb-bastion

Host ewb-app-b
  HostName 10.20.1.10
  User ec2-user
  IdentityFile ~/.ssh/ewb-lab.pem
  IdentitiesOnly yes
  ProxyJump ewb-bastion
```

---

## 🧪 Verification & Acceptance Tests

Execute the acceptance tests specified on Page 11 of the workbook:

| Test ID | Command / Test | Expected Result |
|---|---|---|
| **01 / Baseline** | From `ewb-app-a`: `ping -c 4 10.20.1.10` (before routes) | **100% packet loss** |
| **02 / Forward Path** | From `ewb-app-a`: `ping -c 4 10.20.1.10` (after routes) | **4 replies, 0% packet loss** |
| **03 / Reverse Path** | From `ewb-app-b`: `ping -c 4 10.10.2.10` (after routes) | **4 replies, 0% packet loss** |
| **04 / Private SSH** | From Laptop: `ssh ewb-app-b` | **Shell on App-B via ProxyJump** |
| **05 / Isolation** | EC2 details check on App-A & App-B | **No Public IPv4 on either host** |

To run these automatically from Python or PowerShell:
```bash
python python_lab/test_lab.py
```
or in PowerShell:
```powershell
.\scripts\verify_connectivity.ps1
```

---

## ⚠️ Controlled Failure Experiment

Demonstrates stateful security group packet filtering (Page 11):
1. **Remove Inbound ICMP Rule** on `ewb-sg-app-b` (for `10.10.2.10/32`).
2. **Execute Ping** from `ewb-app-a` to `10.20.1.10`:
   - *Result*: **100% packet loss**. SSH sessions via Bastion continue working normally.
3. **Restore Rule**: Re-add ICMP Echo Request from `10.10.2.10/32`.
4. **Re-test Ping**:
   - *Result*: **Replies resume immediately** (0% packet loss).

---

## 📑 Student Deliverables & Report Generator

The workbook (Page 13) requires submitting a single report PDF named:
`YourName_EWB_VPC_Peering.pdf`

Generate this report with all required sections, tables, logs, and viva answers using:
```bash
python python_lab/generate_report.py --student-name "YourName" --batch "AWS-SAA-Batch-01" --region "ap-south-1"
```
The generated PDF meets all 100-mark rubric criteria.

---

## 💡 Viva & Technical Questions

Detailed architectural explanations for Page 12's viva questions are documented in:
📄 [VIVA_QUESTIONS.md](file:///e:/AWS/VIVA_QUESTIONS.md)

1. *Why is the return route needed?*
2. *Why is the App-B SSH source the bastion private IP?*
3. *Why does Active peering not guarantee a successful ping?*
4. *Can VPC B use VPC A's internet gateway over peering?*

---

## 🧹 Cleanup Instructions

When your lab is finished and evidence is captured, clean up all resources (Page 14):

- **If deployed with CloudFormation**:
  ```bash
  python python_lab/cleanup.py
  ```
- **If deployed with AWS CLI (PowerShell)**:
  ```powershell
  .\scripts\cleanup-aws-cli.ps1
  ```
- **If deployed with AWS CLI (Bash)**:
  ```bash
  ./scripts/cleanup-aws-cli.sh
  ```
- **If deployed with Terraform**:
  ```bash
  cd terraform && terraform destroy
  ```
