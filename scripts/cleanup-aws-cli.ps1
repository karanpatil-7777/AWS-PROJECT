<#
.SYNOPSIS
  Tears down all resources created for the EWB VPC Peering project (Page 14).
#>

param(
    [string]$Region = "ap-south-1"
)

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  EWB Cloud Labs: AWS CLI Cleanup (Page 14)                             " -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

# 1. Terminate EC2 instances
Write-Host "[*] Finding and terminating lab EC2 instances..." -ForegroundColor Cyan
$instanceIds = (aws ec2 describe-instances --filters "Name=tag:Project,Values=EWB-VPC-Peering" "Name=instance-state-name,Values=running,stopped,pending,stopping" --region $Region --query "Reservations[].Instances[].InstanceId" --output text)
if ($instanceIds) {
    Write-Host "[*] Terminating: $instanceIds"
    aws ec2 terminate-instances --instance-ids ($instanceIds -split "\s+") --region $Region | Out-Null
    Write-Host "[*] Waiting for instances to terminate..."
    aws ec2 wait instance-terminated --instance-ids ($instanceIds -split "\s+") --region $Region
    Write-Host "[+] Instances terminated." -ForegroundColor Green
}

# 2. Release Elastic IPs if any
$allocIds = (aws ec2 describe-addresses --filters "Name=tag:Project,Values=EWB-VPC-Peering" --region $Region --query "Addresses[].AllocationId" --output text)
if ($allocIds) {
    foreach ($a in ($allocIds -split "\s+")) {
        Write-Host "[*] Releasing Elastic IP $a..."
        aws ec2 release-address --allocation-id $a --region $Region | Out-Null
    }
}

# 3. Delete VPC Peering Connection
Write-Host "[*] Deleting VPC Peering Connection..." -ForegroundColor Cyan
$pcxIds = (aws ec2 describe-vpc-peering-connections --filters "Name=tag:Project,Values=EWB-VPC-Peering" "Name=status-code,Values=active,pending-acceptance" --region $Region --query "VpcPeeringConnections[].VpcPeeringConnectionId" --output text)
if ($pcxIds) {
    foreach ($p in ($pcxIds -split "\s+")) {
        Write-Host "[*] Deleting peering $p..."
        aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $p --region $Region | Out-Null
    }
}

Start-Sleep -Seconds 5

# 4. Delete Custom Route Tables
Write-Host "[*] Deleting custom Route Tables..." -ForegroundColor Cyan
$rtIds = (aws ec2 describe-route-tables --filters "Name=tag:Project,Values=EWB-VPC-Peering" --region $Region --query "RouteTables[].RouteTableId" --output text)
if ($rtIds) {
    foreach ($rt in ($rtIds -split "\s+")) {
        # Check associations
        $assocs = (aws ec2 describe-route-tables --route-table-ids $rt --region $Region --query "RouteTables[0].Associations[?!Main].RouteTableAssociationId" --output text)
        if ($assocs) {
            foreach ($assoc in ($assocs -split "\s+")) {
                aws ec2 disassociate-route-table --association-id $assoc --region $Region 2>$null | Out-Null
            }
        }
        aws ec2 delete-route-table --route-table-id $rt --region $Region 2>$null | Out-Null
    }
}

# 5. Delete Security Groups
Write-Host "[*] Deleting Security Groups..." -ForegroundColor Cyan
$sgIds = (aws ec2 describe-security-groups --filters "Name=tag:Project,Values=EWB-VPC-Peering" --region $Region --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
if ($sgIds) {
    foreach ($sg in ($sgIds -split "\s+")) {
        for ($i=0; $i -lt 5; $i++) {
            try {
                aws ec2 delete-security-group --group-id $sg --region $Region | Out-Null
                break
            } catch {
                Start-Sleep -Seconds 3
            }
        }
    }
}

# 6. Detach & Delete Internet Gateway
Write-Host "[*] Detaching & deleting Internet Gateway..." -ForegroundColor Cyan
$igws = (aws ec2 describe-internet-gateways --filters "Name=tag:Project,Values=EWB-VPC-Peering" --region $Region --query "InternetGateways[].InternetGatewayId" --output text)
if ($igws) {
    foreach ($igw in ($igws -split "\s+")) {
        $vpcId = (aws ec2 describe-internet-gateways --internet-gateway-ids $igw --region $Region --query "InternetGateways[0].Attachments[0].VpcId" --output text)
        if ($vpcId -and $vpcId -ne "None") {
            aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpcId --region $Region | Out-Null
        }
        aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $Region | Out-Null
    }
}

# 7. Delete Subnets
Write-Host "[*] Deleting subnets..." -ForegroundColor Cyan
$subIds = (aws ec2 describe-subnets --filters "Name=tag:Project,Values=EWB-VPC-Peering" --region $Region --query "Subnets[].SubnetId" --output text)
if ($subIds) {
    foreach ($s in ($subIds -split "\s+")) {
        aws ec2 delete-subnet --subnet-id $s --region $Region 2>$null | Out-Null
    }
}

# 8. Delete VPCs
Write-Host "[*] Deleting VPCs..." -ForegroundColor Cyan
$vpcIds = (aws ec2 describe-vpcs --filters "Name=tag:Project,Values=EWB-VPC-Peering" --region $Region --query "Vpcs[].VpcId" --output text)
if ($vpcIds) {
    foreach ($v in ($vpcIds -split "\s+")) {
        aws ec2 delete-vpc --vpc-id $v --region $Region 2>$null | Out-Null
        Write-Host "[+] Deleted VPC $v" -ForegroundColor Green
    }
}

Write-Host "`n[+] Cleanup finished! Account is clean." -ForegroundColor Green
