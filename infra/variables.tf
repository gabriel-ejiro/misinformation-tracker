variable "project_name" {
  type    = string
  default = "misinfo"
}

variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "use_comprehend" {
  type    = bool
  default = false
}

variable "schedule_cron" {
  type    = string
  default = "rate(60 minutes)"
}

variable "sources_json" {
  type        = string
  description = "JSON array of {name,url}"
}
