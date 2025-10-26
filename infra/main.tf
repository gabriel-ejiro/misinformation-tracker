provider "aws" {
  region = var.region
}

locals {
  name       = var.project_name
  account_id = data.aws_caller_identity.current.account_id
  region     = var.region
}

data "aws_caller_identity" "current" {}

# --- DynamoDB table (with TTL) ---
resource "aws_dynamodb_table" "items" {
  name         = "${local.name}-items"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "N"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

# --- Log groups (short retention) ---
resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${local.name}-ingest"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.name}-api"
  retention_in_days = 7
}

# --- IAM for Lambdas ---
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingest_role" {
  name               = "${local.name}-ingest-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "api_role" {
  name               = "${local.name}-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# ---------- Managed execution policies (replace old inline policies) ----------

# misinfo-api Lambda execution: read/query items; write logs
resource "aws_iam_policy" "api_exec" {
  name        = "${local.name}-api-exec"
  description = "Execution policy for ${local.name}-api Lambda"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "LogsWrite"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.name}-api*"
      },
      {
        Sid      = "DdbReadQuery"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
        Resource = aws_dynamodb_table.items.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_exec_attach" {
  role       = aws_iam_role.api_role.name
  policy_arn = aws_iam_policy.api_exec.arn
}

# misinfo-ingest Lambda execution: write to items (and optional Comprehend); write logs
resource "aws_iam_policy" "ingest_exec" {
  name        = "${local.name}-ingest-exec"
  description = "Execution policy for ${local.name}-ingest Lambda"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "LogsWrite"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.name}-ingest*"
      },
      {
        Sid      = "DdbWrite"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:BatchWriteItem", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.items.arn
      },
      {
        Sid      = "OptionalComprehend"
        Effect   = "Allow"
        Action   = ["comprehend:DetectSentiment"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ingest_exec_attach" {
  role       = aws_iam_role.ingest_role.name
  policy_arn = aws_iam_policy.ingest_exec.arn
}

# --- Package lambdas (expects built zips in ../dist from GitHub Actions) ---
resource "aws_lambda_function" "ingest" {
  function_name    = "${local.name}-ingest"
  role             = aws_iam_role.ingest_role.arn
  handler          = "app.handler"
  runtime          = "python3.11"
  filename         = "${path.module}/../dist/ingest.zip"
  source_code_hash = filebase64sha256("${path.module}/../dist/ingest.zip")

  environment {
    variables = {
      TABLE_NAME     = aws_dynamodb_table.items.name
      SOURCES_JSON   = var.sources_json
      USE_COMPREHEND = var.use_comprehend ? "true" : "false"
    }
  }

  depends_on = [aws_cloudwatch_log_group.ingest]
}

resource "aws_lambda_function" "api" {
  function_name    = "${local.name}-api"
  role             = aws_iam_role.api_role.arn
  handler          = "app.handler"
  runtime          = "python3.11"
  filename         = "${path.module}/../dist/api.zip"
  source_code_hash = filebase64sha256("${path.module}/../dist/api.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.items.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.api]
}

# --- EventBridge schedule -> ingest lambda ---
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${local.name}-schedule"
  schedule_expression = var.schedule_cron
}

resource "aws_cloudwatch_event_target" "tgt" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "ingest"
  arn       = aws_lambda_function.ingest.arn
}

resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

# --- API Gateway (HTTP API) -> api lambda ---
resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "latest" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /latest"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "bysource" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /by-source"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "search" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /search"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "allow_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

output "api_base_url" {
  value = aws_apigatewayv2_api.http.api_endpoint
}

# --- S3 static site for dashboard ---
resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "site" {
  bucket = "${local.name}-site-${random_id.suffix.hex}"
}

# Allow public bucket policy to take effect (keep public ACLs blocked)
resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "PublicRead",
      Effect    = "Allow",
      Principal = "*",
      Action    = ["s3:GetObject"],
      Resource  = ["${aws_s3_bucket.site.arn}/*"]
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.site]
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.site.id
  key          = "index.html"
  content_type = "text/html"
  source       = "${path.module}/../web/index.html"
  etag         = filemd5("${path.module}/../web/index.html")
}

output "site_url" {
  value = aws_s3_bucket_website_configuration.site.website_endpoint
}

