# Starts the local test environment (MySQL + Keycloak) and leaves it running.
$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "run.ps1") -Up
