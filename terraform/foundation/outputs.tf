output "ecr_push_role_arn" {
  description = "Set this as the AWS_ECR_PUSH_ROLE_ARN GitHub repository variable."
  value       = aws_iam_role.ecr_push.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
