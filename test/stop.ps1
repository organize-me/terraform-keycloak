# Stops and removes the local test environment started with start.ps1.
$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "run.ps1") -Down
