# DynamoDB table already exists
import {
  to = aws_dynamodb_table.items
  id = "misinfo-items"
}

# CloudWatch log groups already exist
import {
  to = aws_cloudwatch_log_group.ingest
  id = "/aws/lambda/misinfo-ingest"
}
import {
  to = aws_cloudwatch_log_group.api
  id = "/aws/lambda/misinfo-api"
}

# IAM roles already exist
import {
  to = aws_iam_role.ingest_role
  id = "misinfo-ingest-role"
}
import {
  to = aws_iam_role.api_role
  id = "misinfo-api-role"
}

# Inline role policies (if you define them in Terraform)
import {
  to = aws_iam_role_policy.ingest_policy
  id = "misinfo-ingest-role:misinfo-ingest-policy"
}
import {
  to = aws_iam_role_policy.api_policy
  id = "misinfo-api-role:misinfo-api-policy"
}
