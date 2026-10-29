#!/usr/bin/env bash
# EWB Cloud Labs - AWS VPC Peering Deployment (Bash / AWS CLI)
set -euo pipefail

REGION="${1:-ap-south-1}"
KEY_NAME="${2:-ewb-lab}"
STUDENT_NAME="${3:-Student}"
ADMIN_CIDR="${4:-0.0.0.0/0}"
INSTANCE_TYPE="${5:-t3.micro}"

echo "========================================================================"
echo "  EWB Cloud Labs: AWS CLI Deployment (Bash)                             "
echo "========================================================================"

echo "[*] Fetching latest Amazon Linux 2023 AMI ID..."
AMI_ID=$(aws ssm get-parameter --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" --region "$REGION" --query "Parameter.Value" --output text)
AZ=$(aws ec2 describe-availability-zones --region "$REGION" --query "AvailabilityZones[0].ZoneName" --output text)

echo "[+] Using AMI: $AMI_ID in AZ: $AZ"

# 1. VPC A
echo "[*] Creating VPC A (10.10.0.0/16)..."
VPC_A=$(aws ec2 create-vpc --cidr-block 10.10.0.0/16 --region "$REGION" --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=ewb-vpc-a},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "Vpc.VpcId" --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_A" --enable-dns-hostnames '{"Value":true}' --region "$REGION"

# Subnets
SUB_A_PUB=$(aws ec2 create-subnet --vpc-id "$VPC_A" --cidr-block 10.10.1.0/24 --availability-zone "$AZ" --region "$REGION" --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=ewb-a-public},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "Subnet.SubnetId" --output text)
aws ec2 modify-subnet-attribute --subnet-id "$SUB_A_PUB" --map-public-ip-on-launch --region "$REGION"

SUB_A_PRIV=$(aws ec2 create-subnet --vpc-id "$VPC_A" --cidr-block 10.10.2.0/24 --availability-zone "$AZ" --region "$REGION" --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=ewb-a-private},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "Subnet.SubnetId" --output text)

# IGW
IGW_A=$(aws ec2 create-internet-gateway --region "$REGION" --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=ewb-igw-a},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_A" --vpc-id "$VPC_A" --region "$REGION"

# Route tables VPC A
RT_A_PUB=$(aws ec2 create-route-table --vpc-id "$VPC_A" --region "$REGION" --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=ewb-rt-a-public},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "RouteTable.RouteTableId" --output text)
aws ec2 associate-route-table --route-table-id "$RT_A_PUB" --subnet-id "$SUB_A_PUB" --region "$REGION" >/dev/null
aws ec2 create-route --route-table-id "$RT_A_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_A" --region "$REGION" >/dev/null

RT_A_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC_A" --region "$REGION" --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=ewb-rt-a-private},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "RouteTable.RouteTableId" --output text)
aws ec2 associate-route-table --route-table-id "$RT_A_PRIV" --subnet-id "$SUB_A_PRIV" --region "$REGION" >/dev/null

# 2. VPC B
echo "[*] Creating VPC B (10.20.0.0/16)..."
VPC_B=$(aws ec2 create-vpc --cidr-block 10.20.0.0/16 --region "$REGION" --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=ewb-vpc-b},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "Vpc.VpcId" --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_B" --enable-dns-hostnames '{"Value":true}' --region "$REGION"

SUB_B_PRIV=$(aws ec2 create-subnet --vpc-id "$VPC_B" --cidr-block 10.20.1.0/24 --availability-zone "$AZ" --region "$REGION" --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=ewb-b-private},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "Subnet.SubnetId" --output text)

RT_B_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC_B" --region "$REGION" --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=ewb-rt-b-private},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "RouteTable.RouteTableId" --output text)
aws ec2 associate-route-table --route-table-id "$RT_B_PRIV" --subnet-id "$SUB_B_PRIV" --region "$REGION" >/dev/null

# 3. Peering
echo "[*] Creating & Accepting VPC Peering Connection..."
PCX=$(aws ec2 create-vpc-peering-connection --vpc-id "$VPC_A" --peer-vpc-id "$VPC_B" --region "$REGION" --tag-specifications "ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=ewb-a-b-peer},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "VpcPeeringConnection.VpcPeeringConnectionId" --output text)
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id "$PCX" --region "$REGION" >/dev/null

# Peering routes
aws ec2 create-route --route-table-id "$RT_A_PUB" --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id "$PCX" --region "$REGION" >/dev/null
aws ec2 create-route --route-table-id "$RT_A_PRIV" --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id "$PCX" --region "$REGION" >/dev/null
aws ec2 create-route --route-table-id "$RT_B_PRIV" --destination-cidr-block 10.10.0.0/16 --vpc-peering-connection-id "$PCX" --region "$REGION" >/dev/null

# 4. Security Groups
echo "[*] Creating Security Groups..."
SG_BASTION=$(aws ec2 create-security-group --group-name ewb-sg-bastion --description "Security group for bastion host" --vpc-id "$VPC_A" --region "$REGION" --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=ewb-sg-bastion},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_BASTION" --protocol tcp --port 22 --cidr "$ADMIN_CIDR" --region "$REGION" >/dev/null

SG_APP_A=$(aws ec2 create-security-group --group-name ewb-sg-app-a --description "Security group for App-A" --vpc-id "$VPC_A" --region "$REGION" --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=ewb-sg-app-a},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_APP_A" --protocol tcp --port 22 --cidr 10.10.1.10/32 --region "$REGION" >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_APP_A" --protocol icmp --port -1 --cidr 10.20.1.10/32 --region "$REGION" >/dev/null

SG_APP_B=$(aws ec2 create-security-group --group-name ewb-sg-app-b --description "Security group for App-B" --vpc-id "$VPC_B" --region "$REGION" --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=ewb-sg-app-b},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_APP_B" --protocol tcp --port 22 --cidr 10.10.1.10/32 --region "$REGION" >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_APP_B" --protocol icmp --port -1 --cidr 10.10.2.10/32 --region "$REGION" >/dev/null

# 5. EC2 Instances
echo "[*] Launching EC2 instances with static IPs..."
INST_BASTION=$(aws ec2 run-instances --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" --subnet-id "$SUB_A_PUB" --private-ip-address 10.10.1.10 --security-group-ids "$SG_BASTION" --associate-public-ip-address --region "$REGION" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ewb-bastion},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "Instances[0].InstanceId" --output text)
INST_APP_A=$(aws ec2 run-instances --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" --subnet-id "$SUB_A_PRIV" --private-ip-address 10.10.2.10 --security-group-ids "$SG_APP_A" --no-associate-public-ip-address --region "$REGION" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ewb-app-a},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "Instances[0].InstanceId" --output text)
INST_APP_B=$(aws ec2 run-instances --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" --subnet-id "$SUB_B_PRIV" --private-ip-address 10.20.1.10 --security-group-ids "$SG_APP_B" --no-associate-public-ip-address --region "$REGION" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ewb-app-b},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT_NAME}]" --query "Instances[0].InstanceId" --output text)

echo "[*] Waiting for Bastion public IP..."
aws ec2 wait instance-running --instance-ids "$INST_BASTION" --region "$REGION"
BASTION_PUB_IP=$(aws ec2 describe-instances --instance-ids "$INST_BASTION" --region "$REGION" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

echo "========================================================================"
echo "  DEPLOYMENT COMPLETE"
echo "  Bastion Public IP: $BASTION_PUB_IP"
echo "  App-A Private IP:  10.10.2.10"
echo "  App-B Private IP:  10.20.1.10"
echo "========================================================================"
