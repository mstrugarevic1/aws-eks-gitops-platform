variable "project" {
  type        = string
  description = "Short project slug used for AWS resource names. Must match PROJECT in the Makefile."
  default     = "my-platform"
}

variable "environment" {
  type        = string
  description = "Environment name."
  default     = "staging"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones for this environment."
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "nat_gateway_strategy" {
  type        = string
  description = "Use single for cost-sensitive environments or per_az for higher availability."
  default     = "single"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "eks_endpoint_public_access" {
  type    = bool
  default = true
}

variable "eks_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public EKS API endpoint. Required: set it to your operator or VPN address, e.g. [\"203.0.113.10/32\"]. There is deliberately no default, so an unreviewed apply cannot open the API to the internet."

  validation {
    condition     = length(var.eks_public_access_cidrs) > 0 && alltrue([for c in var.eks_public_access_cidrs : can(cidrnetmask(c))])
    error_message = "eks_public_access_cidrs must contain at least one valid CIDR block."
  }
}

variable "rds_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  type    = number
  default = 20
}

variable "rds_backup_retention_days" {
  type    = number
  default = 3
}

variable "rds_username" {
  type    = string
  default = "app"
}

variable "rds_multi_az" {
  type    = bool
  default = true
}

variable "rds_deletion_protection" {
  type    = bool
  default = true
}

variable "rds_skip_final_snapshot" {
  type    = bool
  default = false
}

variable "alarm_email" {
  type        = string
  description = "Email address to notify on CloudWatch alarms. Leave empty to skip the email subscription."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Additional AWS tags."
  default     = {}
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes control plane version. Keep the cluster-autoscaler image tag in gitops/base/components.json aligned with this."
  default     = "1.35"
}

variable "node_instance_types" {
  type        = list(string)
  description = "Managed node group instance types."
  default     = ["t3.medium"]
}

variable "rds_db_name" {
  type        = string
  description = "Initial PostgreSQL database created on the instance."
  default     = "app"
}

variable "ecr_force_delete" {
  type        = bool
  description = "Delete the ECR repository on destroy even if it still holds images. Convenient for demo environments, unsafe for production."
  default     = false
}

variable "app_secret_recovery_days" {
  type        = number
  description = "Secrets Manager recovery window for the application secret. 0 deletes immediately (demo, allows instant recreate); 7-30 keeps a recovery window."
  default     = 30
}

variable "alb_controller_version" {
  type        = string
  description = "AWS Load Balancer Controller release used to fetch the official IAM policy. Must match the chart version in gitops/base/components.json."
  default     = "v3.4.2"
}
