locals {
  backup_script_platform = startswith(lower(var.docker_host), "npipe:") ? "windows" : "posix"

  backup_template_vars = {
    TF_ARCHIVE_NAME             = var.backup_archive_name
    TF_DUMP_NAME                = "database.bak"
    TF_S3_BACKUP_BUCKET         = var.backup_s3_bucket
    TF_AWS_CLI_IMAGE            = var.backup_aws_image
    TF_MYSQL_CLIENT_IMAGE       = var.backup_mysql_image
    TF_ZIP_IMAGE                = var.backup_zip_image
    TF_BACKUP_TMP_DIR           = abspath(var.backup_tmp_dir)
    TF_DOCKER_NETWORK           = var.docker_network
    TF_KEYCLOAK_CONTAINER       = docker_container.keycloak.name
    TF_MYSQL_HOST               = var.keycloak_db_host
    TF_MYSQL_PORT               = var.keycloak_db_port
    TF_MYSQL_DATABASE           = mysql_database.keycloak.name
    TF_MYSQL_USERNAME           = coalesce(var.backup_mysql_username, var.keycloak_db_username)
    TF_MYSQL_PASSWORD_B64       = local.backup_mysql_password == null ? "" : base64encode(local.backup_mysql_password)
    TF_MYSQL_PASSWORD_SSM_PARAM = var.backup_mysql_password_ssm_parameter
  }

  backup_mysql_password = var.backup_mysql_password != null ? var.backup_mysql_password : (
    var.backup_mysql_password_ssm_parameter != "" ? null :
    (var.backup_mysql_username == null || var.backup_mysql_username == var.keycloak_db_username ? var.keycloak_db_password : null)
  )
}

resource "local_file" "backup_script" {
  count           = local.backup_script_platform == "posix" ? 1 : 0
  filename        = "${var.backup_install_path}/keycloak-backup.sh"
  file_permission = "0700"
  content         = templatefile("${path.module}/backup/backup.sh.tftpl", local.backup_template_vars)
}

resource "local_file" "restore_script" {
  count           = local.backup_script_platform == "posix" ? 1 : 0
  filename        = "${var.backup_install_path}/keycloak-restore.sh"
  file_permission = "0700"
  content         = templatefile("${path.module}/backup/restore.sh.tftpl", local.backup_template_vars)
}

resource "local_file" "backup_powershell_script" {
  count           = local.backup_script_platform == "windows" ? 1 : 0
  filename        = "${var.backup_install_path}/keycloak-backup.ps1"
  file_permission = "0600"
  content         = templatefile("${path.module}/backup/backup.ps1.tftpl", local.backup_template_vars)
}

resource "local_file" "restore_powershell_script" {
  count           = local.backup_script_platform == "windows" ? 1 : 0
  filename        = "${var.backup_install_path}/keycloak-restore.ps1"
  file_permission = "0600"
  content         = templatefile("${path.module}/backup/restore.ps1.tftpl", local.backup_template_vars)
}
