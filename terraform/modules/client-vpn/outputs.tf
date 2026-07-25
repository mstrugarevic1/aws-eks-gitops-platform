output "endpoint_id" {
  value = aws_ec2_client_vpn_endpoint.this.id
}

output "security_group_id" {
  value = aws_security_group.this.id
}
