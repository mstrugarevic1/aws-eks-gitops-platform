variable "name" {
  type        = string
  description = "Name prefix."
}

variable "eks_cluster_name" {
  type        = string
  description = "EKS cluster name."
}

variable "rds_identifier" {
  type        = string
  description = "RDS identifier."
}

variable "alarm_email" {
  type        = string
  description = "Email address to notify on CloudWatch alarms. Leave empty to skip the email subscription."
  default     = ""
}
