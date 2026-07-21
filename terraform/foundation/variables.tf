variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository allowed to assume the app CI role, as owner/name."
  default     = "mstrugarevic1/eks-argocd-platform-boilerplate"
}

variable "github_branch" {
  type        = string
  description = "Branch allowed to assume the app CI role."
  default     = "main"
}

variable "github_environment" {
  type        = string
  description = "GitHub Environment allowed to assume the app CI role. The deploy job runs in this environment, so its OIDC subject is repo:<repo>:environment:<name>."
  default     = "dev"
}

variable "ecr_repository_name" {
  type        = string
  description = "ECR repository GitHub Actions may push to. Must match the ecr_repository_name output of the target environment, which is \"<project>-<environment>/example-app\"."
  default     = "my-platform-dev/example-app"
}

variable "role_name" {
  type        = string
  description = "Name of the IAM role GitHub Actions assumes through OIDC."
  default     = "my-platform-ecr-push"
}
