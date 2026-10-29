variable "aws_region" {
  description = "AWS Region for deploying all resources (e.g. ap-south-1 Mumbai)"
  type        = string
  default     = "ap-south-1"
}

variable "student_name" {
  description = "Student name for resource tagging and identification"
  type        = string
  default     = "Student"
}

variable "project_tag" {
  description = "Project tag value specified in the lab workbook"
  type        = string
  default     = "EWB-VPC-Peering"
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair (default: ewb-lab)"
  type        = string
  default     = "ewb-lab"
}

variable "admin_source_cidr" {
  description = "Public IPv4 CIDR of the administrator workstation (e.g., your_ip/32)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "EC2 Instance type (default: t3.micro)"
  type        = string
  default     = "t3.micro"
}

variable "vpc_a_cidr" {
  description = "CIDR block for VPC A"
  type        = string
  default     = "10.10.0.0/16"
}

variable "subnet_a_public_cidr" {
  description = "CIDR block for VPC A Public Subnet"
  type        = string
  default     = "10.10.1.0/24"
}

variable "subnet_a_private_cidr" {
  description = "CIDR block for VPC A Private Subnet"
  type        = string
  default     = "10.10.2.0/24"
}

variable "vpc_b_cidr" {
  description = "CIDR block for VPC B"
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_b_private_cidr" {
  description = "CIDR block for VPC B Private Subnet"
  type        = string
  default     = "10.20.1.0/24"
}

variable "bastion_private_ip" {
  description = "Static private IP for ewb-bastion"
  type        = string
  default     = "10.10.1.10"
}

variable "app_a_private_ip" {
  description = "Static private IP for ewb-app-a"
  type        = string
  default     = "10.10.2.10"
}

variable "app_b_private_ip" {
  description = "Static private IP for ewb-app-b"
  type        = string
  default     = "10.20.1.10"
}
