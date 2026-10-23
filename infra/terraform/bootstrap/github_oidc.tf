# GitHub Actions authenticates with short-lived OIDC tokens. There are no long-lived AWS keys
# anywhere in CI, and each role is pinned to specific repository/environment claims.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  repo_sub_prefix = "repo:${var.github_repository}"
}

data "aws_iam_policy_document" "trust_pull_requests" {
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
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.repo_sub_prefix}:pull_request", "${local.repo_sub_prefix}:ref:refs/heads/main"]
    }
  }
}

data "aws_iam_policy_document" "trust_environments" {
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
    # Only jobs bound to a protected GitHub environment (with required reviewers) can assume this.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for env in var.deploy_environments : "${local.repo_sub_prefix}:environment:${env}"]
    }
  }
}

# --- Plan: read-only, usable from any PR so reviewers see the exact diff. ---------------------

resource "aws_iam_role" "terraform_plan" {
  name                 = "gha-terraform-plan"
  assume_role_policy   = data.aws_iam_policy_document.trust_pull_requests.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "state_access" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
  # Plans still take the state lock (an S3 lock object), so they need to write *.tflock only.
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state-lock"
  role   = aws_iam_role.terraform_plan.id
  policy = data.aws_iam_policy_document.state_access.json
}

# --- Apply: only from protected environments after approval. ---------------------------------

resource "aws_iam_role" "terraform_apply" {
  name                 = "gha-terraform-apply"
  assume_role_policy   = data.aws_iam_policy_document.trust_environments.json
  max_session_duration = 3600
}

# Broad by necessity (Terraform manages IAM, VPCs, RDS...), so it is gated by environment
# approval rather than scoped by action. A permissions boundary is the next hardening step.
resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# --- Deploy: ship images and roll ECS services, nothing else. --------------------------------

resource "aws_iam_role" "deploy" {
  name                 = "gha-deploy"
  assume_role_policy   = data.aws_iam_policy_document.trust_environments.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
      "ecr:DescribeImages", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
    ]
    resources = ["arn:aws:ecr:*:${data.aws_caller_identity.current.account_id}:repository/ledgerops/*"]
  }
  statement {
    sid = "EcsDeploy"
    actions = [
      "ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:DescribeTasks", "ecs:ListTaskDefinitions",
      "ecs:RegisterTaskDefinition", "ecs:RunTask", "ecs:UpdateService", "ecs:TagResource",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "PassOnlyLedgerOpsTaskRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ledgerops-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
  statement {
    sid       = "ReadMigrationLogs"
    actions   = ["logs:GetLogEvents", "logs:FilterLogEvents"]
    resources = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/ledgerops/*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "ecs-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
