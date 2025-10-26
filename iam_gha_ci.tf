locals {
  account_id          = "872926860633"
  region              = "eu-north-1"
  gha_deploy_role     = "MISINFOTRACKER"        # your GitHub Actions role name
  site_bucket         = "misinfo-site-39506c13"
  tfstate_bucket      = "misinfo-tfstate-eu-north-1-misinfo"
  ddb_items_table_arn = "arn:aws:dynamodb:eu-north-1:872926860633:table/misinfo-items"
  ddb_lock_table_arn  = "arn:aws:dynamodb:eu-north-1:872926860633:table/misinfo-tf-locks"
  lambda_api_arn      = "arn:aws:lambda:eu-north-1:872926860633:function:misinfo-api"
  lambda_ingest_arn   = "arn:aws:lambda:eu-north-1:872926860633:function:misinfo-ingest"
  events_rule_arn     = "arn:aws:events:eu-north-1:872926860633:rule/misinfo-schedule"
}

resource "aws_iam_policy" "gha_ci" {
  name        = "misinfo-gha-deploy"
  description = "Permissions for GitHub Actions to deploy misinfo stack"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ---- S3 READ (refresh)
      {
        Sid    = "S3ReadAll"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketAcl",
          "s3:GetBucketTagging",
          "s3:GetBucketCors",
          "s3:GetBucketVersioning",
          "s3:GetEncryptionConfiguration",
          "s3:GetBucketPolicy",
          "s3:GetBucketWebsite",
          "s3:GetBucketOwnershipControls",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetObject",
          "s3:GetObjectTagging"
        ]
        Resource = "*"
      },

      # ---- S3 MANAGE (site + tfstate)
      {
        Sid    = "S3ManageTfstateAndSite"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket","s3:DeleteBucket",
          "s3:PutBucketPolicy","s3:PutBucketWebsite","s3:DeleteBucketWebsite",
          "s3:PutBucketOwnershipControls","s3:PutBucketPublicAccessBlock","s3:PutEncryptionConfiguration",
          "s3:PutBucketTagging","s3:PutBucketCors","s3:PutBucketLogging","s3:PutLifecycleConfiguration",
          "s3:PutBucketAcl","s3:PutBucketNotification","s3:PutBucketVersioning",
          "s3:PutReplicationConfiguration","s3:PutBucketRequestPayment",
          "s3:ListBucket","s3:ListBucketMultipartUploads",
          "s3:PutObject","s3:PutObjectTagging","s3:DeleteObject","s3:DeleteObjectVersion","s3:AbortMultipartUpload"
        ]
        Resource = [
          "arn:aws:s3:::${local.tfstate_bucket}",
          "arn:aws:s3:::${local.tfstate_bucket}/*",
          "arn:aws:s3:::${local.site_bucket}",
          "arn:aws:s3:::${local.site_bucket}/*"
        ]
      },

      # ---- DynamoDB (lock + items)
      {
        Sid    = "DynamoDBDescribeAndData"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:DescribeTimeToLive","dynamodb:UpdateTimeToLive",
          "dynamodb:ListTagsOfResource","dynamodb:TagResource","dynamodb:UntagResource",
          "dynamodb:GetItem","dynamodb:PutItem","dynamodb:UpdateItem","dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem","dynamodb:Scan","dynamodb:Query"
        ]
        Resource = [
          local.ddb_lock_table_arn,
          local.ddb_items_table_arn
        ]
      },

      # ---- Lambda (both functions)
      {
        Sid    = "LambdaManageMisinfo"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction","lambda:UpdateFunctionCode","lambda:UpdateFunctionConfiguration","lambda:DeleteFunction",
          "lambda:AddPermission","lambda:RemovePermission",
          "lambda:GetFunction","lambda:GetFunctionConfiguration","lambda:GetPolicy",
          "lambda:ListTags","lambda:TagResource","lambda:UntagResource",
          "lambda:CreateAlias","lambda:UpdateAlias","lambda:DeleteAlias"
        ]
        Resource = [
          local.lambda_api_arn,
          "${local.lambda_api_arn}:*",
          local.lambda_ingest_arn,
          "${local.lambda_ingest_arn}:*"
        ]
      },

      # ---- CloudWatch Logs
      {
        Sid    = "LogsDescribe"
        Effect = "Allow"
        Action = ["logs:DescribeLogGroups","logs:DescribeLogStreams","logs:GetLogEvents","logs:ListTagsForResource"]
        Resource = "*"
      },
      {
        Sid    = "LogsManageRetention"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup","logs:DeleteLogGroup","logs:PutRetentionPolicy"]
        Resource = [
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/misinfo-ingest",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/misinfo-ingest:*",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/misinfo-api",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/misinfo-api:*"
        ]
      },

      # ---- API Gateway v2 + global tagging
      {
        Sid    = "ApiGatewayV2Full"
        Effect = "Allow"
        Action = ["apigateway:GET","apigateway:POST","apigateway:PUT","apigateway:PATCH","apigateway:DELETE"]
        Resource = "arn:aws:apigateway:${local.region}::/*"
      },
      {
        Sid    = "GlobalTagging"
        Effect = "Allow"
        Action = ["tag:GetResources","tag:TagResources","tag:UntagResources"]
        Resource = "*"
      },

      # ---- EventBridge rule
      {
        Sid    = "EventBridgeManage"
        Effect = "Allow"
        Action = ["events:DescribeRule","events:PutRule","events:DeleteRule","events:PutTargets","events:RemoveTargets",
                  "events:ListTagsForResource","events:TagResource","events:UntagResource"]
        Resource = local.events_rule_arn
      },

      # ---- IAM (read + pass Lambda roles)
      {
        Sid    = "IAMRead"
        Effect = "Allow"
        Action = ["iam:GetRole","iam:GetRolePolicy","iam:ListRolePolicies"]
        Resource = [
          "arn:aws:iam::${local.account_id}:role/misinfo-ingest-role",
          "arn:aws:iam::${local.account_id}:role/misinfo-api-role"
        ]
      },
      {
        Sid    = "IAMPass"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          "arn:aws:iam::${local.account_id}:role/misinfo-ingest-role",
          "arn:aws:iam::${local.account_id}:role/misinfo-api-role"
        ]
        Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_gha_ci" {
  role       = local.gha_deploy_role
  policy_arn = aws_iam_policy.gha_ci.arn
}
