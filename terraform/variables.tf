variable "timezone" {
  type    = string
  default = "America/Los_Angeles"
}

variable "docker_host" {
  description = "Docker Engine endpoint used by Terraform"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "docker_network" {
  description = "Existing Docker network to attach Keycloak to"
  type        = string
  default     = "organize_me_network"
}

variable "keycloak_image" {
  description = "Keycloak Docker image to run"
  type        = string
  default     = "quay.io/keycloak/keycloak:22.0.5"
}

variable "keycloak_container_name" {
  description = "Docker container name for Keycloak"
  type        = string
  default     = "organize-me-keycloak"
}

variable "keycloak_external_port" {
  description = "Host port published for Keycloak HTTP"
  type        = number
  default     = 8080
}

variable "keycloak_http_relative_path" {
  description = "HTTP context path served by Keycloak"
  type        = string
  default     = "/auth"
}

variable "keycloak_proxy" {
  description = "Keycloak proxy mode"
  type        = string
  default     = "edge"
}

variable "keycloak_db_host" {
  description = "MySQL host reachable from the Keycloak container"
  type        = string
  default     = "mysql"
}

variable "keycloak_db_port" {
  description = "MySQL port reachable from the Keycloak container"
  type        = number
  default     = 3306
}

variable "keycloak_db_name" {
  description = "MySQL database name for Keycloak"
  type        = string
  default     = "keycloak"
}

variable "keycloak_db_username" {
  description = "MySQL username for Keycloak"
  type        = string
  default     = "keycloak"
}

variable "keycloak_db_password" {
  description = "MySQL password for Keycloak"
  type        = string
  sensitive   = true
}

variable "keycloak_db_user_host" {
  description = "MySQL host pattern allowed for the Keycloak database user"
  type        = string
  default     = "%"
}

variable "mysql_host" {
  description = "MySQL host reachable from Terraform"
  type        = string
  default     = "localhost"
}

variable "mysql_port" {
  description = "MySQL port reachable from Terraform"
  type        = number
  default     = 3306
}

variable "mysql_root_username" {
  description = "MySQL administrator username used by Terraform"
  type        = string
}

variable "mysql_root_password" {
  description = "MySQL administrator password used by Terraform"
  type        = string
  sensitive   = true
}

variable "keycloak_admin_username" {
  description = "Initial Keycloak admin username, used only when keycloak_admin_password is set"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Optional initial Keycloak admin password (KEYCLOAK_ADMIN_PASSWORD); leave null to not set it"
  type        = string
  sensitive   = true
  default     = null
}

variable "backup_install_path" {
  description = "The directory where Terraform writes the backup and restore scripts"
  type        = string
  default     = "../bin"
}

variable "backup_tmp_dir" {
  description = "The host temporary directory used during backup and restore"
  type        = string
  default     = "../tmp"
}

variable "backup_s3_bucket" {
  description = "The S3 bucket where Keycloak backup archives are stored"
  type        = string
}

variable "backup_archive_name" {
  description = "The backup archive filename used on the host and in S3"
  type        = string
  default     = "keycloak.zip"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.backup_archive_name))
    error_message = "backup_archive_name must be a simple filename containing only letters, numbers, dots, underscores, and hyphens."
  }
}

variable "backup_aws_image" {
  description = "The AWS CLI Docker image used to transfer backups"
  type        = string
  default     = "amazon/aws-cli:2.18.9"
}

variable "backup_mysql_image" {
  description = "The Docker image providing the mysqldump and mysql clients"
  type        = string
  default     = "mysql:8.0"
}

variable "backup_zip_image" {
  description = "The Docker image used to create and extract ZIP archives (must provide python)"
  type        = string
  default     = "python:3.12-alpine"
}

variable "backup_mysql_username" {
  description = "MySQL user for backup and restore; defaults to keycloak_db_username"
  type        = string
  default     = null
}

variable "backup_mysql_password_ssm_parameter" {
  description = "Optional SSM parameter holding the backup MySQL password, used when MYSQL_PASSWORD is not set"
  type        = string
  default     = ""
}
