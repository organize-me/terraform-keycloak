param(
    # Start the test environment and leave it running for manual testing.
    [switch] $Up,
    # Tear down an environment started with -Up.
    [switch] $Down
)

$ErrorActionPreference = "Stop"

$RootDirectory = Split-Path -Parent $PSScriptRoot
$TestTerraformDirectory = Join-Path $PSScriptRoot "terraform"
$TerraformExecutable = (Get-Command terraform -ErrorAction Stop).Source
$RunId = if ($Up -or $Down) { "manual" } else { [Guid]::NewGuid().ToString("N") }
$KeepResources = $false
$AppTerraformDirectory = Join-Path $env:TEMP "keycloak-app-$RunId"
$TestArtifactsDirectory = Join-Path $PSScriptRoot "artifacts\$RunId"
$TestBinaryDirectory = Join-Path $PSScriptRoot "bin"
$TestTemporaryDirectory = Join-Path $TestArtifactsDirectory "tmp"
$TestTerraformInitialized = $false
$AppTerraformInitialized = $false

$env:TF_VAR_docker_host = "npipe:////./pipe/docker_engine"
$env:TF_VAR_docker_network = "keycloak-test"
$env:TF_VAR_timezone = "America/Los_Angeles"
$env:TF_VAR_mysql_image = "mysql:8.0"
$env:TF_VAR_mysql_external_port = "53306"
$env:TF_VAR_mysql_host = "127.0.0.1"
$env:TF_VAR_mysql_port = "53306"
$env:TF_VAR_mysql_root_username = "root"
$env:TF_VAR_mysql_root_password = "local-test-only"
$env:TF_VAR_s3_compatible_image = "localstack/localstack:3.8.1"
$env:TF_VAR_s3_compatible_external_port = "4566"
$env:TF_VAR_aws_cli_image = "amazon/aws-cli:2.18.9"
$env:TF_VAR_keycloak_container_name = "keycloak-test"
$env:TF_VAR_keycloak_external_port = "18080"
$env:TF_VAR_keycloak_db_host = "mysql"
$env:TF_VAR_keycloak_db_port = "3306"
$env:TF_VAR_keycloak_db_name = "keycloak"
$env:TF_VAR_keycloak_db_username = "keycloak"
$env:TF_VAR_keycloak_db_password = "local-test-only"
$env:TF_VAR_keycloak_admin_username = "admin"
$env:TF_VAR_keycloak_admin_password = "local-test-only"
$env:TF_VAR_backup_s3_bucket = "keycloak-test-backups"
$env:TF_VAR_backup_archive_name = "keycloak-test-backup.zip"
$env:TF_VAR_backup_aws_image = "amazon/aws-cli:2.18.9"
$env:TF_VAR_backup_mysql_image = "mysql:8.0"
$env:TF_VAR_backup_zip_image = "python:3.12-alpine"
$env:TF_VAR_backup_install_path = $TestBinaryDirectory
$env:TF_VAR_backup_tmp_dir = $TestTemporaryDirectory
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:AWS_S3_ENDPOINT_URL = "http://localstack:4566"

$AppUrl = "http://localhost:$env:TF_VAR_keycloak_external_port/auth"
$TestRealm = "backup-restore-test"

function Invoke-Terraform {
    param(
        [string[]] $Arguments,
        [switch] $AllowFailure
    )

    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $TerraformExecutable @Arguments 2>&1
        $TerraformExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    if ($TerraformExitCode -ne 0) {
        if ($AllowFailure) {
            Write-Warning "Terraform exited with code $TerraformExitCode"
            return
        }
        throw "Terraform exited with code $TerraformExitCode"
    }
}

function Invoke-Docker {
    param([string[]] $Arguments)

    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & docker @Arguments 2>&1
        $DockerExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    if ($DockerExitCode -ne 0) {
        throw "Docker exited with code $DockerExitCode"
    }
}

function Invoke-TestAwsCli {
    param([string[]] $Arguments)

    Invoke-Docker (@(
        "run", "--rm", "--network", $env:TF_VAR_docker_network,
        "--env", "AWS_ACCESS_KEY_ID=$env:AWS_ACCESS_KEY_ID",
        "--env", "AWS_SECRET_ACCESS_KEY=$env:AWS_SECRET_ACCESS_KEY",
        "--env", "AWS_DEFAULT_REGION=$env:AWS_DEFAULT_REGION",
        $env:TF_VAR_aws_cli_image
    ) + $Arguments)
}

function Wait-Keycloak {
    for ($Attempt = 0; $Attempt -lt 90; $Attempt++) {
        try {
            return Invoke-RestMethod -Uri "$AppUrl/realms/master/.well-known/openid-configuration" -TimeoutSec 5
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }
    throw "Keycloak did not become ready"
}

function Test-RealmExists {
    param([string] $Realm)

    try {
        Invoke-RestMethod -Uri "$AppUrl/realms/$Realm/.well-known/openid-configuration" -TimeoutSec 10 | Out-Null
        return $true
    }
    catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
            return $false
        }
        throw
    }
}

function Get-AdminHeaders {
    $Token = Invoke-RestMethod -Method Post -Uri "$AppUrl/realms/master/protocol/openid-connect/token" -Body @{
        grant_type = "password"
        client_id  = "admin-cli"
        username   = $env:TF_VAR_keycloak_admin_username
        password   = $env:TF_VAR_keycloak_admin_password
    }
    return @{ Authorization = "Bearer $($Token.access_token)" }
}

function Invoke-GeneratedScript {
    param([string] $Name)

    & (Join-Path $TestBinaryDirectory $Name)
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
    foreach ($FileName in @($env:TF_VAR_backup_archive_name, "database.bak")) {
        if (Test-Path -LiteralPath (Join-Path $TestTemporaryDirectory $FileName)) {
            throw "$Name left temporary host file $FileName behind"
        }
    }
    if ((Invoke-Docker @("container", "inspect", "--format", "{{.State.Running}}", $env:TF_VAR_keycloak_container_name)) -ne "true") {
        throw "$Name did not leave Keycloak running"
    }
}

try {
    if ($Down) {
        $AppTerraformInitialized = Test-Path -LiteralPath (Join-Path $AppTerraformDirectory ".terraform")
        $TestTerraformInitialized = $true
        return
    }

    Invoke-Docker @("info") | Out-Null

    New-Item -ItemType Directory -Force -Path $TestBinaryDirectory, $TestTemporaryDirectory | Out-Null

    Invoke-Terraform @("-chdir=$TestTerraformDirectory", "init")
    $TestTerraformInitialized = $true
    Invoke-Terraform @("-chdir=$TestTerraformDirectory", "apply", "-auto-approve")

    New-Item -ItemType Directory -Force -Path $AppTerraformDirectory | Out-Null
    Copy-Item -Path (Join-Path $RootDirectory "terraform\*.tf") -Destination $AppTerraformDirectory -Force
    Copy-Item -Path (Join-Path $RootDirectory "terraform\.terraform.lock.hcl") -Destination $AppTerraformDirectory -Force
    Copy-Item -Path (Join-Path $RootDirectory "terraform\backup") -Destination $AppTerraformDirectory -Recurse -Force
    Invoke-Terraform @("-chdir=$AppTerraformDirectory", "init")
    $AppTerraformInitialized = $true
    Invoke-Terraform @("-chdir=$AppTerraformDirectory", "apply", "-auto-approve")

    $Discovery = Wait-Keycloak

    if ($Up) {
        $KeepResources = $true
        Write-Host ""
        Write-Host "Keycloak is running at $AppUrl (admin / $env:TF_VAR_keycloak_admin_password)"
        Write-Host "MySQL is published on localhost:$env:TF_VAR_mysql_external_port (root / $env:TF_VAR_mysql_root_password)"
        Write-Host "Backup script:  $(Join-Path $TestBinaryDirectory 'keycloak-backup.ps1')"
        Write-Host "Restore script: $(Join-Path $TestBinaryDirectory 'keycloak-restore.ps1')"
        Write-Host "Set these before running the scripts:"
        Write-Host "  `$env:AWS_ACCESS_KEY_ID='test'; `$env:AWS_SECRET_ACCESS_KEY='test'; `$env:AWS_DEFAULT_REGION='us-east-1'; `$env:AWS_S3_ENDPOINT_URL='http://localstack:4566'"
        Write-Host "Stop with: .\test\stop.ps1"
        return
    }

    if ($Discovery.issuer -ne "$AppUrl/realms/master") {
        throw "Keycloak reported unexpected issuer '$($Discovery.issuer)'"
    }

    $RealmCount = Invoke-Docker @(
        "exec", "keycloak-test-mysql", "mysql",
        "--user=$env:TF_VAR_keycloak_db_username",
        "--password=$env:TF_VAR_keycloak_db_password",
        "--batch", "--skip-column-names",
        "--execute=SELECT COUNT(*) FROM ``$env:TF_VAR_keycloak_db_name``.REALM WHERE NAME = 'master'"
    ) | Where-Object { $_ -is [string] -and $_ -match '^\d+$' }
    if ($RealmCount -ne "1") {
        throw "Keycloak did not store the master realm in MySQL"
    }

    Write-Host "Creating test realm '$TestRealm'"
    Invoke-RestMethod -Method Post -Uri "$AppUrl/admin/realms" -Headers (Get-AdminHeaders) `
        -ContentType "application/json" -Body (@{ realm = $TestRealm; enabled = $true } | ConvertTo-Json) | Out-Null
    if (-not (Test-RealmExists $TestRealm)) {
        throw "Could not create the backup test realm"
    }

    Invoke-GeneratedScript "keycloak-backup.ps1"
    Invoke-TestAwsCli @(
        "s3api", "head-object",
        "--endpoint-url", $env:AWS_S3_ENDPOINT_URL,
        "--bucket", $env:TF_VAR_backup_s3_bucket,
        "--key", $env:TF_VAR_backup_archive_name
    ) | Out-Null
    Wait-Keycloak | Out-Null

    Write-Host "Deleting test realm '$TestRealm'"
    Invoke-RestMethod -Method Delete -Uri "$AppUrl/admin/realms/$TestRealm" -Headers (Get-AdminHeaders) | Out-Null
    if (Test-RealmExists $TestRealm) {
        throw "Could not remove the backup test realm before restore"
    }

    Invoke-GeneratedScript "keycloak-restore.ps1"
    Wait-Keycloak | Out-Null
    if (-not (Test-RealmExists $TestRealm)) {
        throw "Restore did not recover the backed-up test realm"
    }

    Write-Host "Local Keycloak backup/restore test passed"
}
catch {
    Write-Host "Integration test failed: $($_.Exception.Message)"
    $ContainerName = Invoke-Docker @(
        "container", "ls", "--all",
        "--filter", "name=^$env:TF_VAR_keycloak_container_name$",
        "--format", "{{.Names}}"
    )
    if ($ContainerName) {
        Invoke-Docker @("logs", "--tail", "100", $env:TF_VAR_keycloak_container_name)
    }
    throw
}
finally {
    if (-not $KeepResources) {
        if ($AppTerraformInitialized) {
            Invoke-Terraform @("-chdir=$AppTerraformDirectory", "destroy", "-auto-approve") -AllowFailure
        }
        if ($TestTerraformInitialized) {
            Invoke-Terraform @("-chdir=$TestTerraformDirectory", "destroy", "-auto-approve") -AllowFailure
        }
        if (Test-Path -LiteralPath $AppTerraformDirectory) {
            for ($Attempt = 0; $Attempt -lt 5; $Attempt++) {
                try {
                    Remove-Item -LiteralPath $AppTerraformDirectory -Recurse -Force -ErrorAction Stop
                    break
                }
                catch {
                    if ($Attempt -eq 4) {
                        Write-Warning "Could not remove temporary Terraform files at $AppTerraformDirectory"
                    }
                    else {
                        Start-Sleep -Seconds 2
                    }
                }
            }
        }
        if (Test-Path -LiteralPath $TestArtifactsDirectory) {
            Remove-Item -LiteralPath $TestArtifactsDirectory -Recurse -Force
        }
        if (Test-Path -LiteralPath $TestBinaryDirectory) {
            Get-ChildItem -LiteralPath $TestBinaryDirectory -File -Filter "keycloak-*" | Remove-Item -Force
            if (-not (Get-ChildItem -LiteralPath $TestBinaryDirectory -Force)) {
                Remove-Item -LiteralPath $TestBinaryDirectory -Force
            }
        }
        if ((Test-Path -LiteralPath (Join-Path $PSScriptRoot "artifacts")) -and
            -not (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "artifacts") -Force)) {
            Remove-Item -LiteralPath (Join-Path $PSScriptRoot "artifacts") -Force
        }
    }
}
