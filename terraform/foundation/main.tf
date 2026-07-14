# One-time trust anchor for application CI. Apply this locally with admin
# credentials; GitHub Actions uses the role only to push app images.

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "ecr_push_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The deploy job runs in a GitHub Environment, so its OIDC subject is
    # repo:<repo>:environment:<name>. Also allow the branch subject for any
    # workflow that assumes the role without an environment.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:environment:${var.github_environment}",
        "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}",
      ]
    }
  }
}

resource "aws_iam_role" "ecr_push" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.ecr_push_assume_role.json
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "GetEcrAuthorizationToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushToProjectRepository"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository_name}"
    ]
  }
}

resource "aws_iam_policy" "ecr_push" {
  name   = "${var.role_name}-policy"
  policy = data.aws_iam_policy_document.ecr_push.json
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.ecr_push.name
  policy_arn = aws_iam_policy.ecr_push.arn
}
