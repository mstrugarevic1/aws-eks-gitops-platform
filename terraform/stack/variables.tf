variable "project" {
  type        = string
  description = "Short project slug used for AWS resource names. Must match PROJECT in the Makefile."
}

variable "environment" {
  type        = string
  description = "Environment name."
}

variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  description = "Expected AWS account ID for this environment."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "deployment_role_arn" {
  description = "IAM role Terraform assumes in the target AWS account."
  type        = string
}

variable "azs" {
  type        = list(string)
  description = "Availability zones for this environment."
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "database_subnet_cidrs" {
  type        = list(string)
  description = "Isolated database subnet CIDRs. One per availability zone."
}

variable "nat_gateway_strategy" {
  type        = string
  description = "Use single for cost-sensitive environments or per_az for higher availability."
}

variable "node_desired_size" {
  type = number
}

variable "node_min_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "eks_endpoint_public_access" {
  type = bool
}

variable "eks_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public EKS API endpoint when public access is enabled."

  validation {
    condition     = alltrue([for c in var.eks_public_access_cidrs : can(cidrnetmask(c))])
    error_message = "eks_public_access_cidrs must contain only valid CIDR blocks."
  }
}

variable "client_vpn" {
  type = object({
    enabled                    = bool
    client_cidr_block          = string
    server_certificate_arn     = string
    root_certificate_chain_arn = string
    split_tunnel               = bool
    dns_servers                = list(string)
  })
  description = "Optional AWS Client VPN endpoint. Certificate ARNs must already exist in ACM."
  default = {
    enabled                    = false
    client_cidr_block          = "10.255.0.0/22"
    server_certificate_arn     = ""
    root_certificate_chain_arn = ""
    split_tunnel               = true
    dns_servers                = []
  }

  validation {
    condition     = !var.client_vpn.enabled || can(cidrnetmask(var.client_vpn.client_cidr_block))
    error_message = "client_vpn.client_cidr_block must be a valid CIDR when Client VPN is enabled."
  }

  validation {
    condition     = !var.client_vpn.enabled || (var.client_vpn.server_certificate_arn != "" && var.client_vpn.root_certificate_chain_arn != "")
    error_message = "client_vpn certificate ARNs are required when Client VPN is enabled."
  }
}

variable "rds_instance_class" {
  type = string
}

variable "rds_allocated_storage" {
  type = number
}

variable "rds_backup_retention_days" {
  type = number
}

variable "rds_username" {
  type = string
}

variable "rds_multi_az" {
  type = bool
}

variable "rds_deletion_protection" {
  type = bool
}

variable "rds_skip_final_snapshot" {
  type = bool
}

variable "alarm_email" {
  type        = string
  description = "Email address to notify on CloudWatch alarms. Leave empty to skip the email subscription."
}

variable "tags" {
  type        = map(string)
  description = "Additional AWS tags."
  default     = {}
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes control plane version. Keep the cluster-autoscaler image tag in gitops/base/components.json aligned with this."
}

variable "node_instance_types" {
  type        = list(string)
  description = "Managed node group instance types."
}

variable "rds_db_name" {
  type        = string
  description = "Initial PostgreSQL database created on the instance."
}

variable "ecr_force_delete" {
  type        = bool
  description = "Delete the ECR repository on destroy even if it still holds images. Convenient for demo environments, unsafe for production."
}

variable "app_secret_recovery_days" {
  type        = number
  description = "Secrets Manager recovery window for the application secret. 0 deletes immediately (demo, allows instant recreate); 7-30 keeps a recovery window."
}

variable "alb_controller_version" {
  type        = string
  description = "AWS Load Balancer Controller release used to fetch the official IAM policy. Must match the chart version in gitops/base/components.json."
}
