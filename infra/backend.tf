terraform {
  backend "s3" {
    bucket         = "misinfo-tfstate-eu-north-1-misinfo"
    key            = "infra/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "misinfo-tf-locks"
    encrypt        = true
  }
}
