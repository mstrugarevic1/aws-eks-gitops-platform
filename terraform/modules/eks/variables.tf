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
  description = "CIDRs allowed to reach the public Kubernetes API endpoint when endpoint_public_access is true."
  default     = ["203.0.113.10/32"]
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
