output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_security_group_id" {
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  value = replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "app_secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}

output "app_secret_name" {
  value = aws_secretsmanager_secret.app.name
}

output "ecr_repository_name" {
  value = aws_ecr_repository.app.name
}

output "kubernetes_version" {
  value = aws_eks_cluster.this.version
}
