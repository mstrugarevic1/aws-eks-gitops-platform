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
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs."
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDRs."
}

variable "kubernetes_cluster_name" {
  type        = string
  description = "Optional EKS cluster name used for Kubernetes subnet discovery tags."
  default     = ""
}
