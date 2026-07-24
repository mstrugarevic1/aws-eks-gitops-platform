output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "rds_endpoint" {
  value     = module.rds.endpoint
  sensitive = true
}

output "ecr_repository_url" {
  value = module.eks.ecr_repository_url
}

output "app_secret_arn" {
  value = module.eks.app_secret_arn
}

output "rds_master_secret_arn" {
  description = "RDS-managed master password secret in Secrets Manager."
  value       = module.rds.master_user_secret_arn
}

output "eso_role_arn" {
  description = "Annotate the external-secrets ServiceAccount with this role ARN."
  value       = aws_iam_role.eso.arn
}

output "alb_controller_role_arn" {
  description = "Annotate the aws-load-balancer-controller ServiceAccount with this role ARN."
  value       = aws_iam_role.alb_controller.arn
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "cluster_autoscaler_role_arn" {
  description = "Annotate the cluster-autoscaler ServiceAccount with this role ARN."
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "grafana_cloudwatch_role_arn" {
  description = "Annotate the Grafana ServiceAccount with this role ARN for CloudWatch."
  value       = aws_iam_role.grafana.arn
}

output "aws_region" {
  description = "Region this environment is deployed in. Consumed by make kubeconfig and make configure-app-secret."
  value       = var.aws_region
}

output "kubernetes_version" {
  description = "EKS control plane version actually running."
  value       = module.eks.kubernetes_version
}

output "app_secret_name" {
  description = "Secrets Manager path of the application secret. Must match exampleApp.secretManagerPath in the GitOps environment config."
  value       = module.eks.app_secret_name
}

output "ecr_repository_name" {
  description = "ECR repository name for the application image."
  value       = module.eks.ecr_repository_name
}

output "rds_port" {
  value = module.rds.port
}

output "rds_db_name" {
  value = module.rds.db_name
}

output "rds_username" {
  value = module.rds.username
}
