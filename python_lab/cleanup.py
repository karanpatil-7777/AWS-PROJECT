#!/usr/bin/env python3
"""
EWB Cloud Labs - VPC Peering Clean Up Script (Page 14)
Removes all compute, peering, routes, security groups, subnets, IGW, and VPCs safely.
"""

import sys
import time
import argparse
import boto3
from botocore.exceptions import ClientError

def cleanup_cfn_stack(cf_client, stack_name):
    print(f"[*] Checking CloudFormation stack '{stack_name}'...")
    try:
        cf_client.describe_stacks(StackName=stack_name)
    except ClientError:
        print(f"[-] Stack '{stack_name}' does not exist.")
        return False

    print(f"[*] Deleting CloudFormation stack '{stack_name}'...")
    cf_client.delete_stack(StackName=stack_name)
    waiter = cf_client.get_waiter('stack_delete_complete')
    print("[*] Waiting for stack deletion to complete...")
    waiter.wait(StackName=stack_name, WaiterConfig={'Delay': 10, 'MaxAttempts': 60})
    print(f"[+] Stack '{stack_name}' successfully deleted!")
    return True

def cleanup_tagged_resources(ec2_client):
    print("\n" + "=" * 70)
    print("  STEP 1: Terminating Compute Instances (Page 14, Step 1)")
    print("=" * 70)
    reservations = ec2_client.describe_instances(
        Filters=[
            {'Name': 'tag:Project', 'Values': ['EWB-VPC-Peering']},
            {'Name': 'instance-state-name', 'Values': ['running', 'stopped', 'pending', 'stopping']}
        ]
    )['Reservations']

    instance_ids = []
    for r in reservations:
        for inst in r['Instances']:
            instance_ids.append(inst['InstanceId'])

    if instance_ids:
        print(f"[*] Terminating instances: {instance_ids}")
        ec2_client.terminate_instances(InstanceIds=instance_ids)
        print("[*] Waiting for instances to terminate...")
        waiter = ec2_client.get_waiter('instance_terminated')
        waiter.wait(InstanceIds=instance_ids)
        print("[+] Instances terminated.")
    else:
        print("[-] No active lab instances found.")

    # Release EIPs
    print("\n[*] Checking Elastic IPs...")
    eips = ec2_client.describe_addresses(
        Filters=[{'Name': 'tag:Project', 'Values': ['EWB-VPC-Peering']}]
    )['Addresses']
    for eip in eips:
        alloc_id = eip['AllocationId']
        print(f"[*] Releasing Elastic IP {eip['PublicIp']} ({alloc_id})...")
        try:
            ec2_client.release_address(AllocationId=alloc_id)
        except Exception as e:
            print(f"[!] Warning: {e}")

    print("\n" + "=" * 70)
    print("  STEP 2: Deleting Peering Connections (Page 14, Step 2)")
    print("=" * 70)
    peering_conns = ec2_client.describe_vpc_peering_connections(
        Filters=[
            {'Name': 'tag:Project', 'Values': ['EWB-VPC-Peering']},
            {'Name': 'status-code', 'Values': ['active', 'pending-acceptance']}
        ]
    )['VpcPeeringConnections']

    for peer in peering_conns:
        pid = peer['VpcPeeringConnectionId']
        print(f"[*] Deleting peering connection {pid}...")
        try:
            ec2_client.delete_vpc_peering_connection(VpcPeeringConnectionId=pid)
        except Exception as e:
            print(f"[!] Warning: {e}")

    # Wait briefly for ENIs and Peering deletion to settle
    time.sleep(5)

    print("\n" + "=" * 70)
    print("  STEP 3: Deleting Custom Route Tables & Subnet Associations")
    print("=" * 70)
    rts = ec2_client.describe_route_tables(
        Filters=[{'Name': 'tag:Project', 'Values': ['EWB-VPC-Peering']}]
    )['RouteTables']

    for rt in rts:
        rt_id = rt['RouteTableId']
        # Disassociate subnets first
        for assoc in rt.get('Associations', []):
            if not assoc.get('Main'):
                assoc_id = assoc['RouteTableAssociationId']
                print(f"[*] Disassociating route table association {assoc_id}...")
                try:
                    ec2_client.disassociate_route_table(AssociationId=assoc_id)
                except Exception as e:
                    print(f"[!] Warning: {e}")

        # Delete non-main route table
        is_main = any(a.get('Main') for a in rt.get('Associations', []))
        if not is_main:
            print(f"[*] Deleting custom route table {rt_id}...")
            try:
                ec2_client.delete_route_table(RouteTableId=rt_id)
            except Exception as e:
                print(f"[!] Warning deleting route table: {e}")

    print("\n" + "=" * 70)
    print("  STEP 4: Deleting Security Groups")
    print("=" * 70)
    sgs = ec2_client.describe_security_groups(
        Filters=[{'Name': 'tag:Project', 'Values': ['EWB-VPC-Peering']}]
    )['SecurityGroups']

    for sg in sgs:
        sg_id = sg['GroupId']
        if sg['GroupName'] != 'default':
            print(f"[*] Deleting security group {sg['GroupName']} ({sg_id})...")
            # Retry a few times as network interfaces take a few seconds to detach
            for attempt in range(5):
                try:
                    ec2_client.delete_security_group(GroupId=sg_id)
                    print(f"[+] Security group {sg_id} deleted.")
                    break
                except ClientError as e:
                    if "DependencyViolation" in str(e) and attempt < 4:
                        time.sleep(4)
                    else:
                        print(f"[!] Could not delete SG {sg_id}: {e}")

    print("\n" + "=" * 70)
    print("  STEP 5: Detaching & Deleting Internet Gateways")
    print("=" * 70)
    igws = ec2_client.describe_internet_gateways(
        Filters=[{'Name': 'tag:Project', 'Values': ['EWB-VPC-Peering']}]
    )['InternetGateways']

    for igw in igws:
        igw_id = igw['InternetGatewayId']
        for att in igw.get('Attachments', []):
            vpc_id = att['VpcId']
            print(f"[*] Detaching IGW {igw_id} from VPC {vpc_id}...")
            try:
                ec2_client.detach_internet_gateway(InternetGatewayId=igw_id, VpcId=vpc_id)
            except Exception as e:
                print(f"[!] Warning: {e}")
        print(f"[*] Deleting IGW {igw_id}...")
        try:
            ec2_client.delete_internet_gateway(InternetGatewayId=igw_id)
        except Exception as e:
            print(f"[!] Warning: {e}")

    print("\n" + "=" * 70)
    print("  STEP 6: Deleting Subnets")
    print("=" * 70)
    subnets = ec2_client.describe_subnets(
        Filters=[{'Name': 'tag:Project', 'Values': ['EWB-VPC-Peering']}]
    )['Subnets']

    for sub in subnets:
        sub_id = sub['SubnetId']
        print(f"[*] Deleting subnet {sub_id}...")
        try:
            ec2_client.delete_subnet(SubnetId=sub_id)
        except Exception as e:
            print(f"[!] Warning: {e}")

    print("\n" + "=" * 70)
    print("  STEP 7: Deleting VPCs")
    print("=" * 70)
    vpcs = ec2_client.describe_vpcs(
        Filters=[{'Name': 'tag:Project', 'Values': ['EWB-VPC-Peering']}]
    )['Vpcs']

    for vpc in vpcs:
        vpc_id = vpc['VpcId']
        print(f"[*] Deleting VPC {vpc_id}...")
        try:
            ec2_client.delete_vpc(VpcId=vpc_id)
            print(f"[+] VPC {vpc_id} deleted.")
        except Exception as e:
            print(f"[!] Warning: {e}")

    print("\n" + "=" * 70)
    print("  CLEANUP COMPLETE: Account resources cleared successfully!")
    print("=" * 70)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Clean up EWB VPC Peering Lab Resources")
    parser.add_argument("--region", default="ap-south-1", help="AWS Region (default: ap-south-1)")
    parser.add_argument("--stack-name", default="ewb-vpc-peering-lab", help="CloudFormation stack name (if used)")
    args = parser.parse_args()

    session = boto3.Session(region_name=args.region)
    cf_client = session.client('cloudformation')
    ec2_client = session.client('ec2')

    deleted = cleanup_cfn_stack(cf_client, args.stack_name)
    if not deleted:
        cleanup_tagged_resources(ec2_client)
