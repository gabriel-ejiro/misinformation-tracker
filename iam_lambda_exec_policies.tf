# API Lambda execution policy (read/query items; write logs)
resource "aws_iam_policy" "api_exec" {
  name        = "misinfo-api-exec"
  description = "Execution policy for misinfo-api Lambda"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "LogsWrite"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/misinfo-api*"
      },
      {
        Sid    = "DdbReadQuery"
        Effect = "Allow"
        Action = ["dynamodb:GetItem","dynamodb:Query","dynamodb:Scan"]
        Resource = local.ddb_items_table_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_exec_attach" {
  role       = "misinfo-api-role"
  policy_arn = aws_iam_policy.api_exec.arn
}

# Ingest Lambda execution policy (write to items; write logs)
resource "aws_iam_policy" "ingest_exec" {
  name        = "misinfo-ingest-exec"
  description = "Execution policy for misinfo-ingest Lambda"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "LogsWrite"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/misinfo-ingest*"
      },
      {
        Sid    = "DdbWrite"
        Effect = "Allow"
        Action = ["dynamodb:PutItem","dynamodb:UpdateItem","dynamodb:BatchWriteItem","dynamodb:GetItem"]
        Resource = local.ddb_items_table_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ingest_exec_attach" {
  role       = "misinfo-ingest-role"
  policy_arn = aws_iam_policy.ingest_exec.arn
}
