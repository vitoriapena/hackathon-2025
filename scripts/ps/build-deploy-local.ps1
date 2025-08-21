#!/usr/bin/env pwsh
<#!
  scripts/ps/build-deploy-local.ps1
  Build Maven, build/tag Docker image, optionally import into k3d, render YAMLs (base + overlay), deploy to DES and optionally PRD, run smoke job.
  Requires: PowerShell 7+, Maven, Docker, kubectl, Git, (optional) k3d.

  Examples:
    pwsh -File scripts/ps/build-deploy-local.ps1 -Org myorg -Repo myrepo
    pwsh -File scripts/ps/build-deploy-local.ps1 -ApprovePrd
!>

param(
  [string]$Org,
  [string]$Repo,
  [string]$Tag,
  [string]$K3dCluster = 'hackathon-k3d',
  [string]$DesNamespace = 'des',
  [string]$PrdNamespace = 'prd',
  [switch]$ApprovePrd,
  [string]$TimeoutRollout = '120s',
  [string]$TimeoutSmoke = '60s'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location -Path $repoRoot

function Require-Cmd($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $name"
  }
}

function Infer-OrgRepo {
  try {
    $url = git remote get-url origin 2>$null
    if ($url) {
      if ($url -match "[/:]{1}([^/]+)/([^/.]+)(\.git)?$") {
        return @($Matches[1], $Matches[2])
      }
    }
  } catch { }
  return $null
}

function Render-ManifestsEnv([string]$ns, [string]$outDir, [string]$image) {
  New-Item -ItemType Directory -Force -Path (Join-Path $outDir 'base') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $outDir 'overlay') | Out-Null
  Copy-Item -Recurse -Force -Path (Join-Path $repoRoot 'deploy/base/*') -Destination (Join-Path $outDir 'base')
  if (Test-Path (Join-Path $repoRoot "deploy/$ns")) {
    Copy-Item -Recurse -Force -Path (Join-Path $repoRoot "deploy/$ns/*") -Destination (Join-Path $outDir 'overlay')
  }
  # Replace placeholders in all yaml files
  Get-ChildItem -Recurse -Path $outDir -Include *.yaml,*.yml | ForEach-Object {
    $content = Get-Content -Raw -Path $_.FullName
    $content = $content -replace 'ghcr.io/<org>/<repo>:<sha>', $image
    $content = $content -replace '\$\{NAMESPACE\}', $ns
    Set-Content -NoNewline -Path $_.FullName -Value $content
  }
}

# Preflight
Require-Cmd mvn
Require-Cmd docker
Require-Cmd kubectl
Require-Cmd git

# Tag
if (-not $Tag) { $Tag = (git rev-parse --short HEAD).Trim() }

# Org/Repo
if (-not $Org -or -not $Repo) {
  $inferred = Infer-OrgRepo
  if ($inferred) { $Org = $Org ? $Org : $inferred[0]; $Repo = $Repo ? $Repo : $inferred[1] }
}
if (-not $Org -or -not $Repo) { throw 'ORG and REPO not set and could not be inferred. Use -Org and -Repo.' }

$image = "ghcr.io/$Org/$Repo:$Tag"
$imageDes = "ghcr.io/$Org/$Repo:des"
Write-Host "Will build image: $image (alias: $imageDes)"

# Build
Write-Host '1) Maven build'; & mvn -B -DskipTests=false package
Write-Host '2) Docker build'; & docker build -t $image .; & docker tag $image $imageDes

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
Render-ManifestsEnv -ns $DesNamespace -outDir $desTmp -image $image
Render-ManifestsEnv -ns $PrdNamespace -outDir $prdTmp -image $image

function Use-K3dContext([string]$cluster) {
  $ctx = "k3d-$cluster"
  $names = (& kubectl config get-contexts -o name) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  if ($names -contains $ctx) { & kubectl config use-context $ctx | Out-Null; return $true }
  return $false
}

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
