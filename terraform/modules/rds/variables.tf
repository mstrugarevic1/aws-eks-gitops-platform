variable "name" {
  type        = string
  description = "Database name prefix."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs."
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security groups allowed to connect to PostgreSQL."
}

variable "instance_class" {
  type        = string
  description = "RDS instance class."
}

variable "allocated_storage" {
  type        = number
  description = "Allocated storage in GB."
}

variable "backup_retention_days" {
  type        = number
  description = "Backup retention in days."
}

variable "db_username" {
  type        = string
  description = "Database admin username."
}

variable "db_password" {
  type        = string
  description = "Database admin password. Ignored when manage_master_user_password is true."
  sensitive   = true
  default     = null
}

variable "manage_master_user_password" {
  type        = bool
  description = "Let RDS generate the master password and store it in Secrets Manager."
  default     = true
}

variable "deletion_protection" {
  type        = bool
  description = "Whether to protect the database from deletion."
  default     = true
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Whether to skip a final snapshot on destroy."
  default     = false
}

variable "multi_az" {
  type        = bool
  description = "Whether to deploy a Multi-AZ standby instance."
  default     = false
}
