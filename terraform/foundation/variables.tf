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
  description = "ECR repository name GitHub Actions can push to."
  default     = "example-app-dev"
}

variable "role_name" {
  type    = string
  default = "example-ecr-push"
}
