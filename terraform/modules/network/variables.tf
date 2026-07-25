variable "name" {
  type        = string
  description = "Name prefix."
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block."
}

variable "azs" {
  type        = list(string)
  description = "Availability zones."

  validation {
    condition     = length(var.azs) > 0
    error_message = "At least one availability zone is required."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs. One per availability zone; enforced by a precondition on the subnet resource."

  validation {
    condition     = length(var.public_subnet_cidrs) > 0
    error_message = "At least one public subnet CIDR is required."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDRs. One per availability zone; enforced by a precondition on the subnet resource."

  validation {
    condition     = length(var.private_subnet_cidrs) > 0
    error_message = "At least one private subnet CIDR is required."
  }
}

variable "database_subnet_cidrs" {
  type        = list(string)
  description = "Database subnet CIDRs. One per availability zone; enforced by a precondition on the subnet resource."

  validation {
    condition     = length(var.database_subnet_cidrs) > 0
    error_message = "At least one database subnet CIDR is required."
  }
}

variable "kubernetes_cluster_name" {
  type        = string
  description = "Optional EKS cluster name used for Kubernetes subnet discovery tags."
  default     = ""
}

variable "nat_gateway_strategy" {
  type        = string
  description = "NAT gateway layout for private subnets. Use single for lower-cost environments or per_az for higher availability."
  default     = "single"

  validation {
    condition     = contains(["single", "per_az"], var.nat_gateway_strategy)
    error_message = "nat_gateway_strategy must be either single or per_az."
  }
}
