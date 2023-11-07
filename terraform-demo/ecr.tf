resource "aws_ecr_repository" "myrepo" {
  name = var.repo_name
}

variable "repo_name" {
  type = string
  default = "seno005-repo"
}