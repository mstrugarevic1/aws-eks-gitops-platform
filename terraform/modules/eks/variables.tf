variable "name" {
  type        = string
  description = "Name prefix."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the EKS control plane and nodes."
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version."
  default     = "1.35"
}

variable "endpoint_public_access" {
  type        = bool
  description = "Whether the Kubernetes API server is reachable from outside the VPC."
  default     = false
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public Kubernetes API endpoint when endpoint_public_access is true. No default: a documentation-range placeholder here would silently become the real allow-list."

  validation {
    condition     = !contains([for cidr in var.public_access_cidrs : cidr], "0.0.0.0/0")
    error_message = "Refusing to open the Kubernetes API to the whole internet. Set public_access_cidrs to an operator or VPN address."
  }
}

variable "node_instance_types" {
  type        = list(string)
  description = "Managed node group instance types."
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type        = number
  description = "Desired node count."
}

variable "node_min_size" {
  type        = number
  description = "Minimum node count."
}

variable "node_max_size" {
  type        = number
  description = "Maximum node count."
}

variable "ecr_repository_name" {
  type        = string
  description = "ECR repository name for the application image."
}

variable "ecr_force_delete" {
  type        = bool
  description = "Delete the ECR repository on destroy even if it still contains images."
  default     = false
}

variable "app_secret_name" {
  type        = string
  description = "Secrets Manager path for the application secret. Must match exampleApp.secretManagerPath in the GitOps environment config."
}

variable "app_secret_recovery_days" {
  type        = number
  description = "Secrets Manager recovery window in days. 0 deletes the secret immediately on destroy."
  default     = 7
}
