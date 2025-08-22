#!/usr/bin/env pwsh
<#
  scripts/ps/build-local.ps1
  Build the project, build a Docker image and run it detached to perform a smoke test on Windows (PowerShell 7+).
  Usage examples:
    pwsh -File scripts/ps/build-local.ps1
    pwsh -File scripts/ps/build-local.ps1 -Image ghcr.io/org/repo:dev -NoClean
#>

param(
  [string]$Image = "local-app:dev",
  [int]$Port = 8080,
  [int]$Timeout = 30,
  [switch]$NoClean
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Name = 'local-app-smoke'

Write-Host "IMAGE=$Image"
Write-Host "PORT=$Port"

Write-Host 'Running Maven package...'
& mvn -q -DskipTests package | Out-Null

Write-Host "Building Docker image $Image"
& docker build -t $Image . | Out-Null

# Remove existing container if present
try { & docker rm -f $Name | Out-Null } catch { }

Write-Host "Starting container $Name (detached, non-root user 10001)"
$containerId = & docker run -d --name $Name --user 10001 -p "$("$($Port):8080")" $Image
Write-Host "Container started: $containerId"

function Cleanup {
  if (-not $NoClean) {
    Write-Host "Stopping and removing container $Name"
    try { & docker rm -f $Name | Out-Null } catch { }
  } else {
    Write-Host "-NoClean set, keeping container $Name for debugging"
  }
}

try {
  Write-Host "Waiting for readiness endpoint http://localhost:$Port/q/health/ready (timeout ${Timeout}s)"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
    try {
      $resp = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:$Port/q/health/ready" -TimeoutSec 5
      if ($resp.StatusCode -eq 200) {
        Write-Host 'Smoke test: READY OK'
        return
      }
    } catch { }
    Start-Sleep -Seconds 2
  }
  throw "Smoke test failed: readiness endpoint did not become ready within ${Timeout}s"
}
finally {
  Cleanup
}
