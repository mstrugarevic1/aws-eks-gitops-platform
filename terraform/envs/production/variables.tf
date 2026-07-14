variable "project" {
  type        = string
  description = "Short project slug used for AWS resource names."
  default     = "platform"
}

variable "environment" {
  type        = string
  description = "Environment name."
  default     = "production"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones for this environment."
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.11.0/24", "10.30.12.0/24", "10.30.13.0/24"]
}

variable "nat_gateway_strategy" {
  type        = string
  description = "Use single for cost-sensitive environments or per_az for higher availability."
  default     = "per_az"
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "eks_endpoint_public_access" {
  type    = bool
  default = true
}

variable "eks_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public EKS API endpoint. Set to your public IP, e.g. [\"A.B.C.D/32\"]."
  default     = ["A.B.C.D/32"]
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
