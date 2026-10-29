#!/usr/bin/env bash
# EWB Cloud Labs - AWS VPC Peering Cleanup (Bash)
set -uo pipefail

REGION="${1:-ap-south-1}"

echo "========================================================================"
echo "  EWB Cloud Labs: AWS CLI Cleanup (Page 14)                             "
echo "========================================================================"

# 1. Terminate Instances
echo "[*] Terminating EC2 instances..."
INST_IDS=$(aws ec2 describe-instances --filters "Name=tag:Project,Values=EWB-VPC-Peering" "Name=instance-state-name,Values=running,stopped,pending,stopping" --region "$REGION" --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$INST_IDS" ]; then
  aws ec2 terminate-instances --instance-ids $INST_IDS --region "$REGION" >/dev/null
  echo "[*] Waiting for instances to terminate..."
  aws ec2 wait instance-terminated --instance-ids $INST_IDS --region "$REGION"
fi

# 2. Release EIPs
EIPS=$(aws ec2 describe-addresses --filters "Name=tag:Project,Values=EWB-VPC-Peering" --region "$REGION" --query "Addresses[].AllocationId" --output text)
if [ -n "$EIPS" ]; then
  for e in $EIPS; do
    aws ec2 release-address --allocation-id "$e" --region "$REGION" 2>/dev/null || true
  done
fi

# 3. Delete Peering
PCX_IDS=$(aws ec2 describe-vpc-peering-connections --filters "Name=tag:Project,Values=EWB-VPC-Peering" "Name=status-code,Values=active,pending-acceptance" --region "$REGION" --query "VpcPeeringConnections[].VpcPeeringConnectionId" --output text)
if [ -n "$PCX_IDS" ]; then
  for p in $PCX_IDS; do
    aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id "$p" --region "$REGION" 2>/dev/null || true
  done
fi

sleep 5

# 4. Delete Route Tables
RTS=$(aws ec2 describe-route-tables --filters "Name=tag:Project,Values=EWB-VPC-Peering" --region "$REGION" --query "RouteTables[].RouteTableId" --output text)
if [ -n "$RTS" ]; then
  for rt in $RTS; do
    ASSOCS=$(aws ec2 describe-route-tables --route-table-ids "$rt" --region "$REGION" --query "RouteTables[0].Associations[?!Main].RouteTableAssociationId" --output text)
    for a in $ASSOCS; do
      aws ec2 disassociate-route-table --association-id "$a" --region "$REGION" 2>/dev/null || true
    done
    aws ec2 delete-route-table --route-table-id "$rt" --region "$REGION" 2>/dev/null || true
  done
fi

# 5. Delete Security Groups
SGS=$(aws ec2 describe-security-groups --filters "Name=tag:Project,Values=EWB-VPC-Peering" --region "$REGION" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
if [ -n "$SGS" ]; then
  for sg in $SGS; do
    for attempt in {1..5}; do
      aws ec2 delete-security-group --group-id "$sg" --region "$REGION" 2>/dev/null && break || sleep 3
    done
  done
fi

# 6. Detach & Delete IGW
IGWS=$(aws ec2 describe-internet-gateways --filters "Name=tag:Project,Values=EWB-VPC-Peering" --region "$REGION" --query "InternetGateways[].InternetGatewayId" --output text)
if [ -n "$IGWS" ]; then
  for igw in $IGWS; do
    VPC_ID=$(aws ec2 describe-internet-gateways --internet-gateway-ids "$igw" --region "$REGION" --query "InternetGateways[0].Attachments[0].VpcId" --output text)
    if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
      aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID" --region "$REGION" 2>/dev/null || true
    fi
    aws ec2 delete-internet-gateway --internet-gateway-id "$igw" --region "$REGION" 2>/dev/null || true
  done
fi

# 7. Delete Subnets
SUBS=$(aws ec2 describe-subnets --filters "Name=tag:Project,Values=EWB-VPC-Peering" --region "$REGION" --query "Subnets[].SubnetId" --output text)
if [ -n "$SUBS" ]; then
  for s in $SUBS; do
    aws ec2 delete-subnet --subnet-id "$s" --region "$REGION" 2>/dev/null || true
  done
fi

# 8. Delete VPCs
VPCS=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=EWB-VPC-Peering" --region "$REGION" --query "Vpcs[].VpcId" --output text)
if [ -n "$VPCS" ]; then
  for v in $VPCS; do
    aws ec2 delete-vpc --vpc-id "$v" --region "$REGION" 2>/dev/null || true
  done
fi

echo "[+] Cleanup finished! All lab resources deleted."
