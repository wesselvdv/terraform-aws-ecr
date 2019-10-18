locals {
  principals_pull_access_non_empty     = length(var.principals_pull_access) > 0 ? true : false
  principals_push_access_non_empty     = length(var.principals_push_access) > 0 ? true : false
  ecr_need_policy                      = length(var.principals_pull_access) + length(var.principals_push_access) > 0 ? true : false
}

module "label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.14.1"
  enabled    = var.enabled
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  delimiter  = var.delimiter
  attributes = var.attributes
  tags       = var.tags
}

resource "aws_ecr_repository" "default" {
  count = var.enabled ? 1 : 0
  name  = var.use_pushname ? module.label.id : module.label.name
  tags  = module.label.tags
}

resource "aws_ecr_lifecycle_policy" "default" {
  count      = var.enabled ? 1 : 0
  repository = join("", aws_ecr_repository.default.*.name)

  policy = <<EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Remove untagged images",
      "selection": {
        "tagStatus": "untagged",
        "countType": "imageCountMoreThan",
        "countNumber": 1
      },
      "action": {
        "type": "expire"
      }
    },
    {
      "rulePriority": 2,
      "description": "Rotate images when reach ${var.max_image_count} images stored",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": ${var.max_image_count}
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF

}

data "aws_iam_policy_document" "empty" {
  count = var.enabled ? 1 : 0
}

data "aws_iam_policy_document" "resource_push_access" {
  count = var.enabled ? 1 : 0

  statement {
    sid    = "PushAccess"
    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = var.principals_push_access
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ]
  }
}

data "aws_iam_policy_document" "resource_pull_access" {
  count = var.enabled ? 1 : 0

  statement {
    sid    = "PullAccess"
    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = var.principals_pull_access
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability"
    ]
  }
}

data "aws_iam_policy_document" "resource" {
  count         = var.enabled ? 1 : 0
  source_json   = local.principals_pull_access_non_empty ? join("", data.aws_iam_policy_document.resource_pull_access.*.json) : join("", data.aws_iam_policy_document.empty.*.json)
  override_json = local.principals_push_access_non_empty ? join("", data.aws_iam_policy_document.resource_push_access.*.json) : join("", data.aws_iam_policy_document.empty.*.json)
}

resource "aws_ecr_repository_policy" "default" {
  count      = local.ecr_need_policy && var.enabled ? 1 : 0
  repository = join("", aws_ecr_repository.default.*.name)
  policy     = join("", data.aws_iam_policy_document.resource.*.json)
}

