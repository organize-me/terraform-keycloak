#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/env.sh"

APP_TF_DIR=""
APP_TF_INITIALIZED=0
TEST_TF_INITIALIZED=0
APP_URL="http://localhost:${TF_VAR_keycloak_external_port}/auth"
TEST_REALM="backup-restore-test"

cleanup() {
  status=$?
  trap - EXIT

  if [ "$status" -ne 0 ] && docker container inspect "$TF_VAR_keycloak_container_name" >/dev/null 2>&1; then
    docker logs --tail 100 "$TF_VAR_keycloak_container_name" || true
  fi
  if [ "$APP_TF_INITIALIZED" -eq 1 ]; then
    terraform -chdir="$APP_TF_DIR" destroy -auto-approve || status=1
  fi
  if [ "$TEST_TF_INITIALIZED" -eq 1 ]; then
    terraform -chdir="$ROOT_DIR/test/terraform" destroy -auto-approve || status=1
  fi
  if [ -n "$APP_TF_DIR" ]; then
    rm -rf -- "$APP_TF_DIR"
  fi
  rm -f "$ROOT_DIR"/test/bin/keycloak-*
  rmdir "$ROOT_DIR/test/bin" "$ROOT_DIR/test/tmp" 2>/dev/null || true

  exit "$status"
}
trap cleanup EXIT

wait_keycloak() {
  for attempt in $(seq 1 90); do
    if curl --fail --silent "$APP_URL/realms/master/.well-known/openid-configuration" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  echo "Keycloak did not become ready" >&2
  return 1
}

realm_status() {
  curl --silent --output /dev/null --write-out "%{http_code}" \
    "$APP_URL/realms/$1/.well-known/openid-configuration"
}

admin_token() {
  curl --fail --silent --show-error \
    --data "grant_type=password" \
    --data "client_id=admin-cli" \
    --data-urlencode "username=$TF_VAR_keycloak_admin_username" \
    --data-urlencode "password=$TF_VAR_keycloak_admin_password" \
    "$APP_URL/realms/master/protocol/openid-connect/token" |
    sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

run_generated_script() {
  "$ROOT_DIR/test/bin/$1"
  for file in "$TF_VAR_backup_archive_name" database.bak; do
    if [ -e "$TF_VAR_backup_tmp_dir/$file" ]; then
      echo "$1 left temporary host file $file behind" >&2
      exit 1
    fi
  done
  if [ "$(docker container inspect --format '{{.State.Running}}' "$TF_VAR_keycloak_container_name")" != "true" ]; then
    echo "$1 did not leave Keycloak running" >&2
    exit 1
  fi
}

for command in docker terraform curl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

docker info >/dev/null

mkdir -p "$TF_VAR_backup_install_path" "$TF_VAR_backup_tmp_dir"

terraform -chdir="$ROOT_DIR/test/terraform" init
TEST_TF_INITIALIZED=1
terraform -chdir="$ROOT_DIR/test/terraform" apply -auto-approve

APP_TF_DIR="$(mktemp -d "$ROOT_DIR/test/app.XXXXXX")"
cp -R "$ROOT_DIR"/terraform/*.tf "$ROOT_DIR/terraform/.terraform.lock.hcl" "$ROOT_DIR/terraform/backup" "$APP_TF_DIR/"
terraform -chdir="$APP_TF_DIR" init
APP_TF_INITIALIZED=1
terraform -chdir="$APP_TF_DIR" apply -auto-approve

wait_keycloak

if ! curl --fail --silent --show-error "$APP_URL/realms/master/.well-known/openid-configuration" |
  grep -Fq "\"issuer\":\"$APP_URL/realms/master\""; then
  echo "Keycloak did not report the expected issuer under /auth" >&2
  exit 1
fi

echo "Creating test realm '$TEST_REALM'"
curl --fail --silent --show-error \
  --header "Authorization: Bearer $(admin_token)" \
  --header "Content-Type: application/json" \
  --data "{\"realm\":\"$TEST_REALM\",\"enabled\":true}" \
  "$APP_URL/admin/realms" >/dev/null
if [ "$(realm_status "$TEST_REALM")" != "200" ]; then
  echo "Could not create the backup test realm" >&2
  exit 1
fi

run_generated_script keycloak-backup.sh

docker run --rm \
  --network "$TF_VAR_docker_network" \
  --env AWS_ACCESS_KEY_ID --env AWS_SECRET_ACCESS_KEY --env AWS_DEFAULT_REGION \
  "$TF_VAR_aws_cli_image" \
  s3api head-object \
  --endpoint-url "$AWS_S3_ENDPOINT_URL" \
  --bucket "$TF_VAR_backup_s3_bucket" \
  --key "$TF_VAR_backup_archive_name" >/dev/null
wait_keycloak

echo "Deleting test realm '$TEST_REALM'"
curl --fail --silent --show-error --request DELETE \
  --header "Authorization: Bearer $(admin_token)" \
  "$APP_URL/admin/realms/$TEST_REALM" >/dev/null
if [ "$(realm_status "$TEST_REALM")" != "404" ]; then
  echo "Could not remove the backup test realm before restore" >&2
  exit 1
fi

run_generated_script keycloak-restore.sh
wait_keycloak
if [ "$(realm_status "$TEST_REALM")" != "200" ]; then
  echo "Restore did not recover the backed-up test realm" >&2
  exit 1
fi

echo "Local Keycloak backup/restore test passed"
