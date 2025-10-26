# DB table already exists
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
