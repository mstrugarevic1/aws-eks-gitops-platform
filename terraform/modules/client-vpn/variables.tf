variable "name" {
  type        = string
  description = "Name prefix."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID."
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR clients can access."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets associated with the Client VPN endpoint."
}

variable "client_cidr_block" {
  type        = string
  description = "CIDR block assigned to VPN clients. Must not overlap the VPC."
}

variable "server_certificate_arn" {
  type        = string
  description = "ACM ARN for the Client VPN server certificate."
}

variable "root_certificate_chain_arn" {
  type        = string
  description = "ACM ARN for the client root certificate chain."
}

variable "split_tunnel" {
  type        = bool
  description = "Route only VPC traffic through the VPN when true."
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS servers pushed to VPN clients."
}

variable "connection_logging" {
  type = object({
    enabled               = bool
    cloudwatch_log_group  = string
    cloudwatch_log_stream = string
  })
  description = "Client VPN connection logging settings."
}
