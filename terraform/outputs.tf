output "vpc_a_id" {
  description = "VPC A ID"
  value       = aws_vpc.vpc_a.id
}

output "vpc_b_id" {
  description = "VPC B ID"
  value       = aws_vpc.vpc_b.id
}

output "peering_connection_id" {
  description = "VPC Peering Connection ID"
  value       = aws_vpc_peering_connection.peer_a_b.id
}

output "bastion_public_ip" {
  description = "Public IP address of the Bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IP address of the Bastion host"
  value       = aws_instance.bastion.private_ip
}

output "app_a_private_ip" {
  description = "Private IP address of App-A"
  value       = aws_instance.app_a.private_ip
}

output "app_b_private_ip" {
  description = "Private IP address of App-B"
  value       = aws_instance.app_b.private_ip
}

output "ssh_config_template" {
  description = "Generated SSH configuration for ~/.ssh/config"
  value       = <<-EOT
    Host ewb-bastion
      HostName ${aws_instance.bastion.public_ip}
      User ec2-user
      IdentityFile ~/.ssh/${var.key_pair_name}.pem
      IdentitiesOnly yes

    Host ewb-app-a
      HostName ${aws_instance.app_a.private_ip}
      User ec2-user
      IdentityFile ~/.ssh/${var.key_pair_name}.pem
      IdentitiesOnly yes
      ProxyJump ewb-bastion

    Host ewb-app-b
      HostName ${aws_instance.app_b.private_ip}
      User ec2-user
      IdentityFile ~/.ssh/${var.key_pair_name}.pem
      IdentitiesOnly yes
      ProxyJump ewb-bastion
  EOT
}
