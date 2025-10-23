variable "project_name" { type = string  default = "misinfo" }
variable "region"       { type = string  default = "eu-north-1" }
variable "github_owner" { type = string } # e.g. "gabriel-ejiro"
variable "github_repo"  { type = string } # e.g. "misinfo-tracker"
variable "use_comprehend" { type = bool  default = false }
variable "schedule_cron"  { type = string default = "rate(60 minutes)" }

variable "sources_json" {
  type        = string
  description = "JSON array of {name,url}"
}
