#!/usr/bin/env bash
# Stops and removes the local test environment started with start.sh.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/env.sh"

APP_TF_DIR="$ROOT_DIR/test/app.manual"
status=0

if [ -d "$APP_TF_DIR/.terraform" ]; then
  terraform -chdir="$APP_TF_DIR" destroy -auto-approve || status=1
fi
if [ -d "$ROOT_DIR/test/terraform/.terraform" ]; then
  terraform -chdir="$ROOT_DIR/test/terraform" destroy -auto-approve || status=1
fi
if [ "$status" -eq 0 ]; then
  rm -rf -- "$APP_TF_DIR"
  rm -f "$ROOT_DIR"/test/bin/keycloak-*
  rmdir "$ROOT_DIR/test/bin" "$ROOT_DIR/test/tmp" 2>/dev/null || true
fi

exit "$status"
