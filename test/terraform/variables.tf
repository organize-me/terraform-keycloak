variable "docker_host" {
  type    = string
  default = "unix:///var/run/docker.sock"
}

variable "docker_network" {
  type    = string
  default = "keycloak-test"
}

variable "timezone" {
  type    = string
  default = "America/Los_Angeles"
}

variable "mysql_image" {
  type    = string
  default = "mysql:8.0"
}

variable "mysql_root_password" {
  type      = string
  sensitive = true
  default   = "local-test-only"
}

variable "mysql_external_port" {
  type    = number
  default = 53306
}

variable "s3_compatible_image" {
  type    = string
  default = "localstack/localstack:3.8.1"
}

variable "s3_compatible_external_port" {
  type    = number
  default = 4566
}

variable "aws_cli_image" {
  type    = string
  default = "amazon/aws-cli:2.18.9"
}

variable "backup_s3_bucket" {
  type    = string
  default = "keycloak-test-backups"
}