<#
.SYNOPSIS
  Deploys the complete EWB VPC Peering lab using pure AWS CLI commands in PowerShell.
#>

param(
    [string]$Region = "ap-south-1",
    [string]$KeyName = "ewb-lab",
    [string]$StudentName = "Student",
    [string]$AdminCidr = "0.0.0.0/0",
    [string]$InstanceType = "t3.micro"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  EWB Cloud Labs: AWS CLI Deployment (PowerShell)                        " -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

# 1. Fetch latest Amazon Linux 2023 AMI ID
Write-Host "[*] Fetching latest Amazon Linux 2023 AMI ID..." -ForegroundColor Cyan
$amiId = (aws ssm get-parameter --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" --region $Region --query "Parameter.Value" --output text)
Write-Host "[+] Using AMI: $amiId" -ForegroundColor Green

# 2. Get first Availability Zone
$az = (aws ec2 describe-availability-zones --region $Region --query "AvailabilityZones[0].ZoneName" --output text)
Write-Host "[+] Using AZ: $az" -ForegroundColor Green

# 3. Create VPC A
Write-Host "`n[*] Creating VPC A (10.10.0.0/16)..." -ForegroundColor Cyan
$vpcA = (aws ec2 create-vpc --cidr-block 10.10.0.0/16 --region $Region --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=ewb-vpc-a},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "Vpc.VpcId" --output text)
aws ec2 modify-vpc-attribute --vpc-id $vpcA --enable-dns-hostnames "{\`"Value\`":true}" --region $Region
Write-Host "[+] Created VPC A: $vpcA" -ForegroundColor Green

# 4. Create Subnets in VPC A
Write-Host "[*] Creating Subnets in VPC A..." -ForegroundColor Cyan
$subAPub = (aws ec2 create-subnet --vpc-id $vpcA --cidr-block 10.10.1.0/24 --availability-zone $az --region $Region --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=ewb-a-public},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "Subnet.SubnetId" --output text)
aws ec2 modify-subnet-attribute --subnet-id $subAPub --map-public-ip-on-launch --region $Region

$subAPriv = (aws ec2 create-subnet --vpc-id $vpcA --cidr-block 10.10.2.0/24 --availability-zone $az --region $Region --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=ewb-a-private},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "Subnet.SubnetId" --output text)
Write-Host "[+] Created Subnets: ewb-a-public ($subAPub), ewb-a-private ($subAPriv)" -ForegroundColor Green

# 5. Create & Attach Internet Gateway
Write-Host "[*] Creating & Attaching Internet Gateway to VPC A..." -ForegroundColor Cyan
$igwA = (aws ec2 create-internet-gateway --region $Region --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=ewb-igw-a},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $igwA --vpc-id $vpcA --region $Region
Write-Host "[+] Attached IGW: $igwA" -ForegroundColor Green

# 6. Create Route Tables for VPC A
Write-Host "[*] Creating Route Tables for VPC A..." -ForegroundColor Cyan
$rtAPub = (aws ec2 create-route-table --vpc-id $vpcA --region $Region --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=ewb-rt-a-public},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "RouteTable.RouteTableId" --output text)
aws ec2 associate-route-table --route-table-id $rtAPub --subnet-id $subAPub --region $Region | Out-Null
aws ec2 create-route --route-table-id $rtAPub --destination-cidr-block 0.0.0.0/0 --gateway-id $igwA --region $Region | Out-Null

$rtAPriv = (aws ec2 create-route-table --vpc-id $vpcA --region $Region --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=ewb-rt-a-private},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "RouteTable.RouteTableId" --output text)
aws ec2 associate-route-table --route-table-id $rtAPriv --subnet-id $subAPriv --region $Region | Out-Null
Write-Host "[+] Created Route Tables: ewb-rt-a-public ($rtAPub), ewb-rt-a-private ($rtAPriv)" -ForegroundColor Green

# 7. Create VPC B (10.20.0.0/16)
Write-Host "`n[*] Creating VPC B (10.20.0.0/16)..." -ForegroundColor Cyan
$vpcB = (aws ec2 create-vpc --cidr-block 10.20.0.0/16 --region $Region --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=ewb-vpc-b},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "Vpc.VpcId" --output text)
aws ec2 modify-vpc-attribute --vpc-id $vpcB --enable-dns-hostnames "{\`"Value\`":true}" --region $Region
Write-Host "[+] Created VPC B: $vpcB" -ForegroundColor Green

# 8. Create Subnet in VPC B
Write-Host "[*] Creating Subnet in VPC B..." -ForegroundColor Cyan
$subBPriv = (aws ec2 create-subnet --vpc-id $vpcB --cidr-block 10.20.1.0/24 --availability-zone $az --region $Region --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=ewb-b-private},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "Subnet.SubnetId" --output text)

$rtBPriv = (aws ec2 create-route-table --vpc-id $vpcB --region $Region --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=ewb-rt-b-private},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "RouteTable.RouteTableId" --output text)
aws ec2 associate-route-table --route-table-id $rtBPriv --subnet-id $subBPriv --region $Region | Out-Null
Write-Host "[+] Created Subnet ewb-b-private ($subBPriv) and Route Table ewb-rt-b-private ($rtBPriv)" -ForegroundColor Green

# 9. Create and Accept VPC Peering Connection
Write-Host "`n[*] Creating & Accepting VPC Peering Connection..." -ForegroundColor Cyan
$pcx = (aws ec2 create-vpc-peering-connection --vpc-id $vpcA --peer-vpc-id $vpcB --region $Region --tag-specifications "ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=ewb-a-b-peer},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "VpcPeeringConnection.VpcPeeringConnectionId" --output text)
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $pcx --region $Region | Out-Null
Write-Host "[+] Active Peering Connection: $pcx" -ForegroundColor Green

# 10. Add Peering Routes
Write-Host "[*] Adding Peering Routes..." -ForegroundColor Cyan
aws ec2 create-route --route-table-id $rtAPub --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id $pcx --region $Region | Out-Null
aws ec2 create-route --route-table-id $rtAPriv --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id $pcx --region $Region | Out-Null
aws ec2 create-route --route-table-id $rtBPriv --destination-cidr-block 10.10.0.0/16 --vpc-peering-connection-id $pcx --region $Region | Out-Null
Write-Host "[+] Peering routes added to all three route tables." -ForegroundColor Green

# 11. Create Security Groups
Write-Host "`n[*] Creating Security Groups..." -ForegroundColor Cyan
$sgBastion = (aws ec2 create-security-group --group-name ewb-sg-bastion --description "Security group for public bastion host" --vpc-id $vpcA --region $Region --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=ewb-sg-bastion},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id $sgBastion --protocol tcp --port 22 --cidr $AdminCidr --region $Region | Out-Null

$sgAppA = (aws ec2 create-security-group --group-name ewb-sg-app-a --description "Security group for App-A private host" --vpc-id $vpcA --region $Region --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=ewb-sg-app-a},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id $sgAppA --protocol tcp --port 22 --cidr 10.10.1.10/32 --region $Region | Out-Null
aws ec2 authorize-security-group-ingress --group-id $sgAppA --protocol icmp --port -1 --cidr 10.20.1.10/32 --region $Region | Out-Null

$sgAppB = (aws ec2 create-security-group --group-name ewb-sg-app-b --description "Security group for App-B private host" --vpc-id $vpcB --region $Region --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=ewb-sg-app-b},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id $sgAppB --protocol tcp --port 22 --cidr 10.10.1.10/32 --region $Region | Out-Null
aws ec2 authorize-security-group-ingress --group-id $sgAppB --protocol icmp --port -1 --cidr 10.10.2.10/32 --region $Region | Out-Null
Write-Host "[+] Security Groups created: $sgBastion, $sgAppA, $sgAppB" -ForegroundColor Green

# 12. Launch EC2 Instances
Write-Host "`n[*] Launching EC2 Instances with specified fixed IPs..." -ForegroundColor Cyan
$instBastion = (aws ec2 run-instances --image-id $amiId --instance-type $InstanceType --key-name $KeyName --subnet-id $subAPub --private-ip-address 10.10.1.10 --security-group-ids $sgBastion --associate-public-ip-address --region $Region --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ewb-bastion},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "Instances[0].InstanceId" --output text)

$instAppA = (aws ec2 run-instances --image-id $amiId --instance-type $InstanceType --key-name $KeyName --subnet-id $subAPriv --private-ip-address 10.10.2.10 --security-group-ids $sgAppA --no-associate-public-ip-address --region $Region --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ewb-app-a},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "Instances[0].InstanceId" --output text)

$instAppB = (aws ec2 run-instances --image-id $amiId --instance-type $InstanceType --key-name $KeyName --subnet-id $subBPriv --private-ip-address 10.20.1.10 --security-group-ids $sgAppB --no-associate-public-ip-address --region $Region --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ewb-app-b},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$StudentName}]" --query "Instances[0].InstanceId" --output text)

Write-Host "[+] Launched Instances:" -ForegroundColor Green
Write-Host "    ewb-bastion: $instBastion"
Write-Host "    ewb-app-a:   $instAppA"
Write-Host "    ewb-app-b:   $instAppB"

Write-Host "`n[*] Waiting for Bastion public IP assignment..." -ForegroundColor Cyan
aws ec2 wait instance-running --instance-ids $instBastion --region $Region
$bastionPubIp = (aws ec2 describe-instances --instance-ids $instBastion --region $Region --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
Write-Host "[+] Bastion Public IP: $bastionPubIp" -ForegroundColor Green

Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host "  DEPLOYMENT COMPLETE                                                   " -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "Configure your SSH by running: .\scripts\setup_ssh.ps1 -BastionPublicIp $bastionPubIp" -ForegroundColor Yellow
