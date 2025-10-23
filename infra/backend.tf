terraform {
  backend "s3" {
    bucket         = "misinfo-tfstate-${var.region}-${var.project_name}"
    key            = "infra/terraform.tfstate"
    region         = var.region
    dynamodb_table = "misinfo-tf-locks"
    encrypt        = true
  }
}
