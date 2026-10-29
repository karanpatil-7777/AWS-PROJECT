# AWS Management Console Step-by-Step Walkthrough

This document walks you through the manual execution of the **EWB Cloud Labs VPC Peering Project** using the AWS Management Console, following pages 5 through 14 of the student workbook.

---

## Page 5: Create VPC A

### Step 1: Create the first VPC
1. Open the **AWS Management Console** and navigate to **VPC**.
2. Click **Create VPC**.
3. Under **Resources to create**, select **VPC only**.
4. **Name tag**: `ewb-vpc-a`
5. **IPv4 CIDR block**: `10.10.0.0/16`
6. **IPv6 CIDR block**: No IPv6 CIDR block
7. **Tenancy**: Default
8. Add tags:
   - `Project` = `EWB-VPC-Peering`
   - `Student` = `<Your Name>`
9. Click **Create VPC**.
10. Click **Actions** > **Edit VPC settings** > check **Enable DNS hostnames** > click **Save changes**.

### Step 2: Create Subnets in VPC A
1. Navigate to **Subnets** > click **Create subnet**.
2. **VPC ID**: Select `ewb-vpc-a`.
3. **Subnet 1 (Public)**:
   - Subnet name: `ewb-a-public`
   - Availability Zone: Choose your preferred AZ (e.g., `ap-south-1a`).
   - IPv4 CIDR: `10.10.1.0/24`
4. Click **Add new subnet**:
   - Subnet name: `ewb-a-private`
   - Availability Zone: Select the **same AZ** (e.g., `ap-south-1a`).
   - IPv4 CIDR: `10.10.2.0/24`
5. Click **Create subnet**.
6. Select `ewb-a-public` > **Actions** > **Edit subnet settings** > check **Enable auto-assign public IPv4 address** > **Save**.

### Step 3: Attach the Internet Gateway
1. Navigate to **Internet gateways** > click **Create internet gateway**.
2. Name tag: `ewb-igw-a`
3. Click **Create internet gateway**.
4. With `ewb-igw-a` selected, click **Actions** > **Attach to VPC**.
5. Select `ewb-vpc-a` and click **Attach internet gateway**.

### Step 4: Create the Public Route Table
1. Navigate to **Route tables** > click **Create route table**.
2. Name: `ewb-rt-a-public`
3. VPC: `ewb-vpc-a`
4. Click **Create route table**.
5. Go to the **Subnet associations** tab > click **Edit subnet associations**.
6. Select `ewb-a-public` and click **Save associations**.
7. Go to the **Routes** tab > click **Edit routes** > click **Add route**:
   - **Destination**: `0.0.0.0/0`
   - **Target**: Select **Internet Gateway** > choose `ewb-igw-a`.
8. Click **Save changes**.

### Step 5: Create the Private Route Table
1. Click **Create route table**.
2. Name: `ewb-rt-a-private`
3. VPC: `ewb-vpc-a`
4. Click **Create route table**.
5. Under **Subnet associations**, click **Edit subnet associations**.
6. Select `ewb-a-private` and click **Save associations**.
7. Leave only the default local route (`10.10.0.0/16` -> `local`). **Do not add an internet default route.**

> **Checkpoint 01**: Confirm `ewb-a-public` routes to `0.0.0.0/0` via `ewb-igw-a`, and `ewb-a-private` contains only the local route.

---

## Page 6: Build VPC B & Security Groups

### Step 1: Create VPC B & Subnet
1. Navigate to **VPCs** > **Create VPC** > **VPC only**.
2. Name tag: `ewb-vpc-b`
3. IPv4 CIDR: `10.20.0.0/16`
4. Tenancy: Default > Click **Create VPC**.
5. Navigate to **Subnets** > **Create subnet**.
6. VPC ID: `ewb-vpc-b`
7. Subnet name: `ewb-b-private`
8. Availability Zone: Select the same AZ (e.g. `ap-south-1a`).
9. IPv4 CIDR: `10.20.1.0/24`
10. Click **Create subnet** (keep auto-assign public IPv4 disabled).
11. Navigate to **Route tables** > **Create route table**:
    - Name: `ewb-rt-b-private`
    - VPC: `ewb-vpc-b`
12. Edit Subnet associations: explicitly associate `ewb-b-private`.
13. Retain only the local route (`10.20.0.0/16` -> `local`). **No Internet Gateway is created or attached.**

### Step 2: Create Security Groups

#### 1. `ewb-sg-bastion` (VPC A)
- Go to **Security Groups** > **Create security group**.
- Security group name: `ewb-sg-bastion`
- Description: `Security group for public bastion host`
- VPC: `ewb-vpc-a`
- Inbound rules:
  - Type: **SSH** | Port: `22` | Source: **My IP** (or `your_public_ip/32`)
- Outbound rules: Leave default allow-all (`0.0.0.0/0`).
- Click **Create security group**.

#### 2. `ewb-sg-app-a` (VPC A)
- Click **Create security group**.
- Security group name: `ewb-sg-app-a`
- Description: `Security group for App-A private host`
- VPC: `ewb-vpc-a`
- Inbound rules:
  - **Rule 1**: Type: **SSH** | Port: `22` | Source: `Custom` > `10.10.1.10/32` (Bastion private IP)
  - **Rule 2**: Type: **Custom ICMP - IPv4** | Protocol: `ICMP` | Port range: `Echo Request` (Type 8, Code 0) | Source: `Custom` > `10.20.1.10/32` (App-B)
- Outbound rules: Leave default allow-all.
- Click **Create security group**.

#### 3. `ewb-sg-app-b` (VPC B)
- Click **Create security group**.
- Security group name: `ewb-sg-app-b`
- Description: `Security group for App-B private host`
- VPC: `ewb-vpc-b`
- Inbound rules:
  - **Rule 1**: Type: **SSH** | Port: `22` | Source: `Custom` > `10.10.1.10/32` (Bastion private IP)
  - **Rule 2**: Type: **Custom ICMP - IPv4** | Protocol: `ICMP` | Port range: `Echo Request` (Type 8, Code 0) | Source: `Custom` > `10.10.2.10/32` (App-A)
- Outbound rules: Leave default allow-all.
- Click **Create security group**.

---

## Page 7: Launch the Three EC2 Instances

### 1. Key Pair
1. Navigate to **EC2** > **Key pairs** > **Create key pair**.
2. Name: `ewb-lab`
3. Key pair type: **RSA**
4. Private key file format: `.pem`
5. Click **Create key pair** and save `ewb-lab.pem` to your local machine (e.g. `~/.ssh/ewb-lab.pem`).

### 2. Launch Instances

| Instance | VPC / Subnet | Private IP | Public IP | Security Group |
|---|---|---|---|---|
| `ewb-bastion` | `ewb-vpc-a` / `ewb-a-public` | `10.10.1.10` | **Enable** | `ewb-sg-bastion` |
| `ewb-app-a` | `ewb-vpc-a` / `ewb-a-private` | `10.10.2.10` | **Disable** | `ewb-sg-app-a` |
| `ewb-app-b` | `ewb-vpc-b` / `ewb-b-private` | `10.20.1.10` | **Disable** | `ewb-sg-app-b` |

#### How to specify static private IPs:
1. In the EC2 Launch wizard:
   - AMI: **Amazon Linux 2023 AMI**
   - Instance type: `t3.micro` (or `t2.micro`)
   - Key pair: `ewb-lab`
2. Under **Network settings**, click **Edit**:
   - Select VPC and Subnet.
   - Auto-assign public IP: Set Enable for Bastion, Disable for App-A and App-B.
   - Select existing security group.
   - Expand **Advanced network configuration** > under Network Interface 1, enter the **Primary IP**:
     - Bastion: `10.10.1.10`
     - App-A: `10.10.2.10`
     - App-B: `10.20.1.10`
3. Launch each instance and wait for **2/2 status checks**.

> **Checkpoint 02**: Note down instance IDs, private IPs, and the Bastion's public IP. Confirm App-A and App-B have no public IPv4 addresses.

---

## Page 8: SSH Configuration & Baseline Test

### Step 1: Configure Local OpenSSH
In PowerShell or Terminal, set permissions:
```powershell
# In PowerShell:
.\scripts\setup_ssh.ps1 -BastionPublicIp <YOUR_BASTION_PUBLIC_IP>
```
Or edit `~/.ssh/config`:
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

### Step 2: Test Baseline (Before Peering)
1. SSH into App-A:
   ```bash
   ssh ewb-app-a
   ```
2. Run baseline ping to App-B:
   ```bash
   ping -c 4 10.20.1.10
   ```
3. **Expected result**: `100% packet loss` (no route exists to VPC B yet).
4. Take a screenshot or record this output.
5. Exit back to your laptop:
   ```bash
   exit
   ```

---

## Page 9: Request, Accept & Activate Peering

1. Navigate to **VPC** > **Peering connections** > click **Create peering connection**.
2. **Name**: `ewb-a-b-peer`
3. **VPC ID (Requester)**: Select `ewb-vpc-a`
4. **VPC ID (Accepter)**:
   - Account: **My account**
   - Region: **This Region**
   - VPC ID: Select `ewb-vpc-b`
5. Click **Create peering connection**.
6. Select `ewb-a-b-peer` > click **Actions** > **Accept request** > click **Accept request**.
7. Confirm status changes to **Active**. Note the peering ID (e.g., `pcx-xxxxxxxxxxxxxxxxx`).

> **Checkpoint 03**: Take a screenshot showing Peering Name `ewb-a-b-peer`, Status `Active`, Requester `ewb-vpc-a`, and Accepter `ewb-vpc-b`.

---

## Page 10: Add Routes on Both Sides

Open each route table, click **Routes** > **Edit routes** > **Add route**:

1. **`ewb-rt-a-private`** (associated to `ewb-a-private`):
   - Destination: `10.20.0.0/16`
   - Target: **Peering Connection** > select `ewb-a-b-peer` (pcx-...)
2. **`ewb-rt-b-private`** (associated to `ewb-b-private`):
   - Destination: `10.10.0.0/16`
   - Target: **Peering Connection** > select `ewb-a-b-peer` (pcx-...)
3. **`ewb-rt-a-public`** (associated to `ewb-a-public`):
   - Destination: `10.20.0.0/16`
   - Target: **Peering Connection** > select `ewb-a-b-peer` (pcx-...)
   *(Required so the Bastion host can reach App-B for ProxyJump administration!)*

> **Checkpoint 04**: Save route tables screenshots showing the peering route targets.

---

## Page 11: Verification & Controlled Failure

### Test Suite:
1. **Forward Path**:
   ```bash
   ssh ewb-app-a
   hostname -I
   ping -c 4 10.20.1.10
   ```
   **Expected**: 4 replies, 0% packet loss.

2. **Reverse Path**:
   ```bash
   ssh ewb-app-b
   hostname -I
   ping -c 4 10.10.2.10
   ```
   **Expected**: 4 replies, 0% packet loss.

3. **Controlled Failure**:
   - Go to **Security Groups** > select `ewb-sg-app-b` > **Edit inbound rules**.
   - Temporarily delete the ICMP Echo Request rule from `10.10.2.10/32`.
   - From App-A, re-run `ping -c 4 10.20.1.10`.
   - **Result**: Replies stop (100% loss). Notice SSH still works!
   - Restore the ICMP Echo Request rule on `ewb-sg-app-b`.
   - Re-run ping from App-A: replies immediately resume (0% loss).

---

## Page 14: Finish Responsibly & Clean Up

When you have collected all screenshots and evidence for your report:
1. Terminate instances `ewb-bastion`, `ewb-app-a`, and `ewb-app-b`.
2. Release the Bastion Elastic IP (if allocated).
3. Delete VPC peering connection `ewb-a-b-peer`.
4. Delete custom route tables `ewb-rt-a-public`, `ewb-rt-a-private`, `ewb-rt-b-private`.
5. Delete security groups `ewb-sg-bastion`, `ewb-sg-app-a`, `ewb-sg-app-b`.
6. Detach and delete `ewb-igw-a`.
7. Delete subnets `ewb-a-public`, `ewb-a-private`, `ewb-b-private`.
8. Delete `ewb-vpc-a` and `ewb-vpc-b`.
