# terraform-keycloak

Terraform configuration for running Keycloak on the existing `organize_me_network`
Docker network and connecting it to an existing MySQL server.

## Requirements

- Terraform
- Docker Engine and an existing Docker network
- An existing MySQL server reachable from Terraform and from containers on that network

Terraform creates the `keycloak` database and database user. It does not provision the
MySQL server itself.

## Configure and apply

Run Terraform from the `terraform` directory. Supply values as `TF_VAR_` environment
variables, for example:

```sh
export TF_VAR_docker_network=organize_me_network
export TF_VAR_mysql_host=localhost
export TF_VAR_mysql_root_username=root
export TF_VAR_mysql_root_password=replace-me
export TF_VAR_keycloak_db_host=mysql
export TF_VAR_keycloak_db_password=replace-me
export TF_VAR_backup_install_path=../bin
export TF_VAR_backup_tmp_dir=../tmp
export TF_VAR_backup_s3_bucket=organize-me.example.com.backups
# Optional: match the previous scripts (root user, password from SSM)
export TF_VAR_backup_mysql_username=root
export TF_VAR_backup_mysql_password_ssm_parameter=organize-me.mysql_password

terraform init
terraform plan
terraform apply
```

`mysql_host` is the address Terraform uses to connect to MySQL; `keycloak_db_host` is
the address Keycloak uses on the Docker network. On Windows, set
`TF_VAR_docker_host=npipe:////./pipe/docker_engine`.

The container uses the inspected Keycloak 26.5.7 image, publishes port 8080, and serves
under `/auth` on the `keycloak` network alias. The default URL is
`http://localhost:8080/auth`.

The inspected instance runs with `start-dev`; this configuration preserves that behavior.
Development mode is not appropriate for an internet-facing production deployment. Terraform
state contains database credentials and Docker environment values, so keep state files
private and do not commit `.tfvars` files.

For numeric Keycloak image tags at version 24 and newer, Terraform uses
`KC_PROXY_HEADERS=xforwarded` and `KC_HTTP_ENABLED=true`; older tags continue using the legacy
`KC_PROXY` setting. The proxy must overwrite the `X-Forwarded-*` headers, including
`X-Forwarded-Proto`, and the Keycloak HTTP port should only be reachable from trusted networks.

## Backup and restore

Terraform writes backup and restore scripts for the configured host platform only:
PowerShell (`.ps1`) when `docker_host` uses the Windows named pipe (`npipe:`), otherwise
POSIX shell (`.sh`). Set `backup_s3_bucket` to the S3 bucket that stores the archive
(`backup_archive_name`, default `keycloak.zip`). The archive contains a single
`database.bak` MySQL dump, the same format as the previous hand-written scripts, so
existing backups can be restored.

The scripts only need the Docker CLI on the host: `mysqldump`/`mysql` run in
`backup_mysql_image`, zipping runs in `backup_zip_image`, and S3 transfers run in
`backup_aws_image`, all on the Keycloak Docker network. AWS credentials come from `~/.aws`
or the standard `AWS_*` environment variables; set `AWS_S3_ENDPOINT_URL` to use an
S3-compatible endpoint.

The MySQL user defaults to `keycloak_db_username`; override it with
`backup_mysql_username`. For the default backup user, the generated scripts embed
`keycloak_db_password`; set `backup_mysql_password` to embed a different backup user's
password. The password is base64-encoded in the script and decoded at runtime. If no
password is embedded, the scripts read `MYSQL_PASSWORD` or, if that is unset and
`backup_mysql_password_ssm_parameter` is configured, retrieve it from that SSM parameter.
On POSIX hosts, generated scripts use owner-only permissions because they may contain
credentials; apply restrictive ACLs to generated PowerShell scripts on Windows. Terraform
state also contains the rendered scripts and sensitive values, so protect it accordingly.
After Terraform renders the scripts, they do not depend on `TF_VAR_*` variables at
runtime. AWS credentials are still supplied through the standard AWS profile or `AWS_*`
environment variables for S3 access.

The backup script stops Keycloak, dumps the database, restarts Keycloak, zips the dump, and
uploads it to S3. The restore script downloads and extracts the archive, stops Keycloak,
loads the dump into the database, and restarts Keycloak. Restore replaces the tables in the
backup. Both scripts restart Keycloak and remove their temporary host files even if a step
fails.

## Run the local integration test

The test runs MySQL, LocalStack's S3-compatible service, and Keycloak in an isolated
`keycloak-test` Docker network. It applies a temporary copy of the Terraform configuration
(so the main deployment's state is untouched), waits for Keycloak's OpenID discovery
document under `/auth`, checks the reported issuer, and confirms Keycloak stored the
`master` realm in MySQL. It then creates a test realm, runs the generated backup script,
confirms the archive is in S3, deletes the realm, runs the generated restore script, and
confirms the realm is back. It also verifies the scripts leave Keycloak running and remove
temporary host files. It uses local-only test credentials and destroys the test containers
when it exits.

On Windows, Terraform and Docker Desktop are required; run the PowerShell test runner:

```powershell
.\test\run.ps1
```

Use `.\test\start.ps1` to start the test environment (MySQL + Keycloak) without running the
test checks and leave it running for manual testing, and `.\test\stop.ps1` to tear it down.
These wrap `.\test\run.ps1 -Up` and `.\test\run.ps1 -Down`.

On Linux or macOS, run:

```sh
bash test/run.sh
```

To start and stop the environment for manual testing on Linux or macOS, use
`bash test/start.sh` and `bash test/stop.sh`.

The test publishes MySQL on port `53306`, LocalStack on `4566`, and Keycloak on `18080`;
choose different values in `test/env.sh`, `test/run.ps1`, or `test/terraform/variables.tf`
if those ports are already in use. The test sets `keycloak_admin_password` so it can use
the admin API; leave it unset in production, where the admin user already exists.
