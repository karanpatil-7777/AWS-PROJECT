#!/usr/bin/env python3
"""
EWB Cloud Labs - AWS VPC Peering Deployment Script
Automated deployment using AWS CloudFormation and Boto3.
"""

import sys
import os
import time
import argparse
import boto3
from botocore.exceptions import ClientError, NoCredentialsError

TEMPLATE_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "cloudformation", "vpc-peering-lab.yaml")

def get_my_ip():
    """Attempt to detect local public IPv4 address."""
    import urllib.request
    try:
        with urllib.request.urlopen("https://checkip.amazonaws.com", timeout=5) as response:
            ip = response.read().decode('utf-8').strip()
            return f"{ip}/32"
    except Exception:
        return "0.0.0.0/0"

def ensure_key_pair(ec2_client, key_name, save_dir):
    """Ensure key pair exists or create it and save locally."""
    try:
        ec2_client.describe_key_pairs(KeyNames=[key_name])
        print(f"[+] Key pair '{key_name}' already exists in AWS.")
    except ClientError as e:
        if "InvalidKeyPair.NotFound" in str(e):
            print(f"[*] Creating RSA key pair '{key_name}'...")
            key_response = ec2_client.create_key_pair(
                KeyName=key_name,
                KeyType='rsa',
                KeyFormat='pem'
            )
            key_material = key_response['KeyMaterial']
            os.makedirs(save_dir, exist_ok=True)
            key_file = os.path.join(save_dir, f"{key_name}.pem")
            with open(key_file, "w") as f:
                f.write(key_material)
            # Set permissions (best-effort on Windows/POSIX)
            try:
                os.chmod(key_file, 0o400)
            except Exception:
                pass
            print(f"[+] Key saved to {key_file}")
        else:
            raise

def deploy_stack(region, stack_name, student_name, key_name, admin_cidr, instance_type):
    print("=" * 70)
    print("  EWB Cloud Labs: Automated AWS VPC Peering Deployment")
    print("=" * 70)
    print(f"Region:        {region}")
    print(f"Stack Name:    {stack_name}")
    print(f"Student Name:  {student_name}")
    print(f"Key Pair:      {key_name}")
    print(f"Admin CIDR:    {admin_cidr}")
    print(f"Instance Type: {instance_type}")
    print("-" * 70)

    try:
        session = boto3.Session(region_name=region)
        cf_client = session.client('cloudformation')
        ec2_client = session.client('ec2')
    except NoCredentialsError:
        print("[!] ERROR: No AWS credentials found.")
        print("    Configure your credentials using 'aws configure' or set environment variables:")
        print("    AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION")
        sys.exit(1)

    # 1. Ensure Key Pair
    ssh_dir = os.path.expanduser("~/.ssh")
    ensure_key_pair(ec2_client, key_name, ssh_dir)

    # 2. Read CloudFormation template
    if not os.path.exists(TEMPLATE_PATH):
        print(f"[!] Error: Template file not found at {TEMPLATE_PATH}")
        sys.exit(1)

    with open(TEMPLATE_PATH, "r", encoding="utf-8") as f:
        template_body = f.read()

    parameters = [
        {'ParameterKey': 'StudentName', 'ParameterValue': student_name},
        {'ParameterKey': 'KeyPairName', 'ParameterValue': key_name},
        {'ParameterKey': 'AdminCidr', 'ParameterValue': admin_cidr},
        {'ParameterKey': 'InstanceType', 'ParameterValue': instance_type}
    ]

    # 3. Create or Update Stack
    print(f"[*] Submitting CloudFormation stack creation '{stack_name}'...")
    try:
        cf_client.create_stack(
            StackName=stack_name,
            TemplateBody=template_body,
            Parameters=parameters,
            Capabilities=['CAPABILITY_NAMED_IAM'],
            Tags=[
                {'Key': 'Project', 'Value': 'EWB-VPC-Peering'},
                {'Key': 'Student', 'Value': student_name}
            ]
        )
    except ClientError as e:
        if "AlreadyExistsException" in str(e):
            print(f"[!] Stack '{stack_name}' already exists. Polling status...")
        else:
            print(f"[!] Stack creation failed: {e}")
            sys.exit(1)

    # 4. Wait for completion
    print("[*] Waiting for stack resources to be provisioned (this takes ~2-3 minutes)...")
    waiter = cf_client.get_waiter('stack_create_complete')
    try:
        waiter.wait(StackName=stack_name, WaiterConfig={'Delay': 10, 'MaxAttempts': 60})
        print("[+] Stack created successfully!")
    except Exception as e:
        print(f"[!] Waiter failed: {e}")
        # Fetch events
        events = cf_client.describe_stack_events(StackName=stack_name)['StackEvents']
        print("\nRecent Stack Events:")
        for ev in reversed(events[:10]):
            print(f" - {ev.get('LogicalResourceId')}: {ev.get('ResourceStatus')} ({ev.get('ResourceStatusReason', '')})")
        sys.exit(1)

    # 5. Retrieve Outputs
    stack = cf_client.describe_stacks(StackName=stack_name)['Stacks'][0]
    outputs = {o['OutputKey']: o['OutputValue'] for o in stack.get('Outputs', [])}

    print("\n" + "=" * 70)
    print("  DEPLOYMENT COMPLETED SUCCESSFULLY")
    print("=" * 70)
    for k, v in outputs.items():
        if k != "SSHConfigInstructions":
            print(f" {k:<25}: {v}")

    # 6. Generate SSH config file
    bastion_ip = outputs.get('BastionPublicIp', 'BASTION_PUBLIC_IP')
    ssh_config_content = f"""
# --- EWB VPC Peering Lab Hosts ---
Host ewb-bastion
  HostName {bastion_ip}
  User ec2-user
  IdentityFile ~/.ssh/{key_name}.pem
  IdentitiesOnly yes

Host ewb-app-a
  HostName 10.10.2.10
  User ec2-user
  IdentityFile ~/.ssh/{key_name}.pem
  IdentitiesOnly yes
  ProxyJump ewb-bastion

Host ewb-app-b
  HostName 10.20.1.10
  User ec2-user
  IdentityFile ~/.ssh/{key_name}.pem
  IdentitiesOnly yes
  ProxyJump ewb-bastion
"""
    config_path = os.path.expanduser("~/.ssh/config")
    print("\n[*] Appending host entries to ~/.ssh/config...")
    try:
        with open(config_path, "a", encoding="utf-8") as f:
            f.write(ssh_config_content)
        print(f"[+] Updated {config_path}")
    except Exception as e:
        print(f"[!] Could not update ~/.ssh/config automatically: {e}")
        print("Please manually copy these lines to your ~/.ssh/config:")
        print(ssh_config_content)

    print("\n[+] Done! You can now run 'python python_lab/test_lab.py' to run all verification checks.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Deploy EWB VPC Peering Lab")
    parser.add_argument("--region", default="ap-south-1", help="AWS Region (default: ap-south-1)")
    parser.add_argument("--stack-name", default="ewb-vpc-peering-lab", help="CloudFormation stack name")
    parser.add_argument("--student-name", default="Student", help="Your name for resource tagging")
    parser.add_argument("--key-name", default="ewb-lab", help="EC2 Key pair name (default: ewb-lab)")
    parser.add_argument("--admin-cidr", default=None, help="Your public IP CIDR (default: auto-detected)")
    parser.add_argument("--instance-type", default="t3.micro", help="Instance type (default: t3.micro)")

    args = parser.parse_args()
    cidr = args.admin_cidr if args.admin_cidr else get_my_ip()
    deploy_stack(args.region, args.stack_name, args.student_name, args.key_name, cidr, args.instance_type)
