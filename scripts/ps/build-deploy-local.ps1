#!/usr/bin/env pwsh
<#
  scripts/ps/build-deploy-local.ps1
  Build Maven, build/tag Docker image, optionally import into k3d, render YAMLs (base + overlay), deploy to DES and optionally PRD, run smoke job.
  Requires: PowerShell 7+, Maven, Docker, kubectl, Git, (optional) k3d.

  Examples:
    pwsh -File scripts/ps/build-deploy-local.ps1 -Org myorg -Repo myrepo
    pwsh -File scripts/ps/build-deploy-local.ps1 -ApprovePrd
#>

param(
  [string]$Org,
  [string]$Repo,
  [string]$Tag,
  [string]$K3dCluster = 'hackathon-k3d',
  [string]$DesNamespace = 'des',
  [string]$PrdNamespace = 'prd',
  [switch]$ApprovePrd,
  [string]$TimeoutRollout = '120s',
  [string]$TimeoutSmoke = '60s',
  [switch]$RunLocalSmoke,
  [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Resolve-RepoRoot -StartFrom $PSScriptRoot
Set-Location -Path $repoRoot

# Preflight
Require-Cmd mvn
Require-Cmd docker
Require-Cmd git
if (-not $BuildOnly) { Require-Cmd kubectl }

# Tag
if (-not $Tag) { $Tag = (git rev-parse --short HEAD).Trim() }

# Org/Repo
if (-not $Org -or -not $Repo) {
  $inferred = Infer-OrgRepo
  if ($inferred) { $Org = $Org ? $Org : $inferred[0]; $Repo = $Repo ? $Repo : $inferred[1] }
}
  if (-not $Org -or -not $Repo) {
    # Fallbacks to be tolerant on local machines without a git remote.
    if (-not $Repo) { $Repo = Split-Path -Leaf $repoRoot }
    if (-not $Org) {
      $candidate = (git config user.name 2>$null) -as [string]
      if (-not $candidate) { $candidate = $env:USERNAME }
      if (-not $candidate) { $candidate = 'local' }
      $Org = $candidate
    }
    Write-Warning "ORG/REPO not found from git remote; falling back to Org='$Org' Repo='$Repo'. To be explicit, pass -Org and -Repo to the script."
}

$orgNorm = Sanitize-Name $Org
$repoNorm = Sanitize-Name $Repo
$tagNorm = Sanitize-Name $Tag
$image = "ghcr.io/${orgNorm}/${repoNorm}:${tagNorm}"
$imageDes = "ghcr.io/${orgNorm}/${repoNorm}:des"
Write-Host "Will build image: $image (alias: $imageDes)"

# Build
Write-Host '1) Maven build'; & mvn -B -DskipTests=false package
Write-Host '2) Docker build'; & docker build -t $image .; & docker tag $image $imageDes

if ($RunLocalSmoke) {
  $name = 'local-app-smoke'
  try { & docker rm -f $name | Out-Null } catch { }
  Write-Host "Starting container $name (detached, non-root user 10001)"
  $containerId = & docker run -d --name $name --user 10001 -p "8080:8080" $image
  Write-Host "Container started: $containerId"
  try {
    Write-Host "Waiting for readiness endpoint http://localhost:8080/q/health/ready (timeout ${TimeoutSmoke})"
  $timeoutSec = Parse-DurationSeconds -Value $TimeoutSmoke
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
      try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:8080/q/health/ready' -TimeoutSec 5
        if ($resp.StatusCode -eq 200) { Write-Host 'Smoke test: READY OK'; break }
      } catch { }
      Start-Sleep -Seconds 2
    }
    if ($sw.Elapsed.TotalSeconds -ge $timeoutSec) { throw "Smoke test failed: readiness endpoint did not become ready within ${TimeoutSmoke}" }
  }
  finally { try { & docker rm -f $name | Out-Null } catch { } }
}

if ($BuildOnly) { Write-Host 'BuildOnly set; skipping deploy.'; return }

# Import into k3d if present
$haveK3d = $false
if (Get-Command k3d -ErrorAction SilentlyContinue) { $haveK3d = $true }
if ($haveK3d) {
  try {
    Write-Host "Importing images into k3d cluster '$K3dCluster'"
    & k3d image import $image --cluster $K3dCluster | Out-Null
    & k3d image import $imageDes --cluster $K3dCluster | Out-Null
  } catch { Write-Warning "Failed to import images into k3d cluster '$K3dCluster'" }
} else {
  Write-Host '3) k3d not available. Ensure the image is reachable by the cluster (push to registry).'
}

# Render manifests
$root = New-Item -ItemType Directory -Force -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("hackathon-" + [System.Guid]::NewGuid().ToString('N')))
$desTmp = Join-Path $root 'des'
$prdTmp = Join-Path $root 'prd'
Write-Host "4) Rendering manifests (DES -> $desTmp, PRD -> $prdTmp)"
Render-ManifestsEnv -RepoRoot $repoRoot -Namespace $DesNamespace -OutDir $desTmp -Image $image
Render-ManifestsEnv -RepoRoot $repoRoot -Namespace $PrdNamespace -OutDir $prdTmp -Image $image


function Deploy-Env([string]$cluster, [string]$ns, [string]$envTmp) {
  Write-Host "==> Deploying to cluster '$cluster' namespace '$ns'"
  if (-not (Use-K3dContext $cluster)) { Write-Host "Context k3d-$cluster not found. Using current kubectl context." }
  Write-Host "Ensuring namespace '$ns' exists"; & kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - | Out-Null
  Write-Host "Applying rendered deploy/base for '$ns'"; & kubectl apply -R -f (Join-Path $envTmp 'base')
  if (Test-Path (Join-Path $envTmp 'overlay')) { Write-Host "Applying rendered overlay for '$ns'"; & kubectl apply -R -f (Join-Path $envTmp 'overlay') }
  Write-Host "Waiting for rollout of deploy/app in '$ns'"; & kubectl -n $ns rollout status deploy/app --timeout $TimeoutRollout
  $smoke = Join-Path (Join-Path $envTmp 'base') 'smoke-job.yaml'
  if (Test-Path $smoke) {
    Write-Host "Running smoke job for '$ns'"
    & kubectl -n $ns delete job smoke-health --ignore-not-found | Out-Null
    & kubectl -n $ns apply -f $smoke | Out-Null
    & kubectl -n $ns wait --for=condition=complete job/smoke-health --timeout $TimeoutSmoke
    & kubectl -n $ns logs job/smoke-health || $true
  }
}

Write-Host "5) Deploying to DES (cluster=$K3dCluster ns=$DesNamespace)"
Use-K3dContext $K3dCluster | Out-Null
Deploy-Env -cluster $K3dCluster -ns $DesNamespace -envTmp $desTmp
Write-Host 'DES deploy complete.'

$doPrd = $false
if ($ApprovePrd) { $doPrd = $true } else {
  if ([Environment]::UserInteractive) {
    $ans = Read-Host "Proceed to deploy PRD (cluster=$K3dCluster ns=$PrdNamespace)? [y/N]"
    if ($ans -match '^[Yy]$') { $doPrd = $true }
  }
}

if ($doPrd) {
  Write-Host "6) Deploying to PRD (cluster=$K3dCluster ns=$PrdNamespace)"
  Use-K3dContext $K3dCluster | Out-Null
  Deploy-Env -cluster $K3dCluster -ns $PrdNamespace -envTmp $prdTmp
  Write-Host 'PRD deploy complete.'
} else {
  Write-Host 'PRD deployment skipped.'
}

Remove-Item -Recurse -Force $root
Write-Host 'Done.'
