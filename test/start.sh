#!/usr/bin/env bash
# Starts the local test environment (MySQL + Keycloak) and leaves it running.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/env.sh"

APP_TF_DIR="$ROOT_DIR/test/app.manual"

for command in docker terraform curl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

docker info >/dev/null

terraform -chdir="$ROOT_DIR/test/terraform" init
terraform -chdir="$ROOT_DIR/test/terraform" apply -auto-approve

mkdir -p "$APP_TF_DIR"
mkdir -p "$TF_VAR_backup_install_path" "$TF_VAR_backup_tmp_dir"
cp -R "$ROOT_DIR"/terraform/*.tf "$ROOT_DIR/terraform/.terraform.lock.hcl" "$ROOT_DIR/terraform/backup" "$APP_TF_DIR/"
terraform -chdir="$APP_TF_DIR" init
terraform -chdir="$APP_TF_DIR" apply -auto-approve

APP_URL="http://localhost:${TF_VAR_keycloak_external_port}/auth"
DISCOVERY_URL="$APP_URL/realms/master/.well-known/openid-configuration"

for attempt in $(seq 1 90); do
  if curl --fail --silent "$DISCOVERY_URL" >/dev/null; then
    break
  fi
  if [ "$attempt" -eq 90 ]; then
    echo "Keycloak did not become ready; check: docker logs $TF_VAR_keycloak_container_name" >&2
    exit 1
  fi
  sleep 2
done

echo ""
echo "Keycloak is running at $APP_URL (admin / $TF_VAR_keycloak_admin_password)"
echo "MySQL is published on localhost:$TF_VAR_mysql_external_port (root / $TF_VAR_mysql_root_password)"
echo "Backup script:  $TF_VAR_backup_install_path/keycloak-backup.sh"
echo "Restore script: $TF_VAR_backup_install_path/keycloak-restore.sh"
echo "Set these before running the scripts:"
echo "  export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 AWS_S3_ENDPOINT_URL=http://localstack:4566"
echo "Stop with: bash test/stop.sh"
