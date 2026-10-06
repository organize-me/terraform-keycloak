#!/bin/sh

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    export TF_VAR_docker_host="${TF_VAR_docker_host:-npipe:////./pipe/docker_engine}"
    ;;
  *)
    export TF_VAR_docker_host="${TF_VAR_docker_host:-unix:///var/run/docker.sock}"
    ;;
esac
export TF_VAR_docker_network="keycloak-test"
export TF_VAR_timezone="America/Los_Angeles"

export TF_VAR_mysql_image="mysql:8.0"
export TF_VAR_mysql_external_port="53306"
export TF_VAR_mysql_host="127.0.0.1"
export TF_VAR_mysql_port="53306"
export TF_VAR_mysql_root_username="root"
export TF_VAR_mysql_root_password="local-test-only"
export TF_VAR_s3_compatible_image="localstack/localstack:3.8.1"
export TF_VAR_s3_compatible_external_port="4566"
export TF_VAR_aws_cli_image="amazon/aws-cli:2.18.9"

export TF_VAR_keycloak_container_name="keycloak-test"
export TF_VAR_keycloak_external_port="18080"
export TF_VAR_keycloak_db_host="mysql"
export TF_VAR_keycloak_db_port="3306"
export TF_VAR_keycloak_db_name="keycloak"
export TF_VAR_keycloak_db_username="keycloak"
export TF_VAR_keycloak_db_password="local-test-only"
export TF_VAR_keycloak_admin_username="admin"
export TF_VAR_keycloak_admin_password="local-test-only"

export TF_VAR_backup_s3_bucket="keycloak-test-backups"
export TF_VAR_backup_archive_name="keycloak-test-backup.zip"
export TF_VAR_backup_aws_image="amazon/aws-cli:2.18.9"
export TF_VAR_backup_mysql_image="mysql:8.0"
export TF_VAR_backup_zip_image="python:3.12-alpine"
export TF_VAR_backup_install_path="$ROOT_DIR/test/bin"
export TF_VAR_backup_tmp_dir="$ROOT_DIR/test/tmp"

export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_S3_ENDPOINT_URL="http://localstack:4566"
