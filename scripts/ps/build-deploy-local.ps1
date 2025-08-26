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
  [switch]$BuildOnly,
  [switch]$SkipTrivy,
  [string]$TrivySeverity = 'HIGH,CRITICAL'
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
if (-not $SkipTrivy) { Require-Cmd trivy }

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
  # No git remote found; silently using defaults for Org/Repo
}

$orgNorm = Sanitize-Name $Org
$repoNorm = Sanitize-Name $Repo
$tagNorm = Sanitize-Name $Tag
$image = "ghcr.io/${orgNorm}/${repoNorm}:${tagNorm}"
$imageDes = "ghcr.io/${orgNorm}/${repoNorm}:des"
Write-Host "Will build image: $image (alias: $imageDes)" -ForegroundColor DarkGray

# Build
Write-Host '1) Maven build' -ForegroundColor Green; Write-Host ''
& mvn -B -DskipTests=false package
Write-Host ''
Write-Host '2) Docker build' -ForegroundColor Green; Write-Host ''
& docker build -t $image .; & docker tag $image $imageDes

# Trivy image scan (optional)
Write-Host ''
Write-Host '3) Trivy image scan' -ForegroundColor Green; Write-Host ''
if ($SkipTrivy) {
  Write-Host 'Trivy scan skipped (-SkipTrivy).'
} else {
  # Fail on HIGH/CRITICAL (default) or custom severities; no progress bar for cleaner logs
  & trivy image --severity $TrivySeverity --exit-code 1 --no-progress $image
  if ($LASTEXITCODE -ne 0) {
    throw "Trivy scan failed (exit code $LASTEXITCODE) for image $image"
  } else {
    Write-Host "Trivy scan passed for $image (severity filter: $TrivySeverity)" -ForegroundColor DarkGray
  }
}

if ($RunLocalSmoke) {
  $name = 'local-app-smoke'
  try { & docker rm -f $name | Out-Null } catch { }
  Write-Host "Starting container $name (detached, non-root user 10001)"
  $containerId = & docker run -d --name $name --user 10001 -p "8080:8080" $image
  Write-Host "Container started."
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
    if ($sw.Elapsed.TotalSeconds -ge $timeoutSec) {
      Write-Host "Smoke test failed: readiness endpoint did not become ready within ${TimeoutSmoke}" -ForegroundColor Red
      throw "Smoke test failed: readiness endpoint did not become ready within ${TimeoutSmoke}"
    }
  }
  finally { try { & docker rm -f $name | Out-Null } catch { } }
}

if ($BuildOnly) { Write-Host 'BuildOnly set; skipping deploy.'; return }

# Import into k3d if present
$haveK3d = $false
if (Get-Command k3d -ErrorAction SilentlyContinue) { $haveK3d = $true }
if ($haveK3d) {
  try {
    Write-Host ''
    Write-Host "4) Importing images into k3d cluster '$K3dCluster'" -ForegroundColor Green; Write-Host ''
    & k3d image import $image --cluster $K3dCluster | Out-Null
    & k3d image import $imageDes --cluster $K3dCluster | Out-Null
  } catch { Write-Warning "Failed to import images into k3d cluster '$K3dCluster'" }
} else {
  Write-Host ''
  Write-Host '4) k3d not available. Ensure the image is reachable by the cluster (push to registry).' -ForegroundColor Green; Write-Host ''
}

# Render manifests
$root = New-Item -ItemType Directory -Force -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("hackathon-" + [System.Guid]::NewGuid().ToString('N')))
$desTmp = Join-Path $root 'des'
$prdTmp = Join-Path $root 'prd'
Write-Host ''
Write-Host "5) Rendering manifests (DES -> $desTmp, PRD -> $prdTmp)" -ForegroundColor Green; Write-Host ''
Render-ManifestsEnv -RepoRoot $repoRoot -Namespace $DesNamespace -OutDir $desTmp -Image $image
Render-ManifestsEnv -RepoRoot $repoRoot -Namespace $PrdNamespace -OutDir $prdTmp -Image $image


function Deploy-Env([string]$cluster, [string]$ns, [string]$envTmp) {
  Write-Host "==> Deploying to cluster '$cluster' namespace '$ns'"
  if (-not (Use-K3dContext $cluster)) { Write-Host "Context k3d-$cluster not found. Using current kubectl context." }
  Write-Host "Ensuring namespace '$ns' exists" -ForegroundColor DarkGray; & kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - | Out-Null
  
  # Apply all rendered manifests from the temporary directory
  Write-Host "Applying rendered manifests for '$ns'..."
  $applyOutput = & kubectl apply -R -f $envTmp 2>&1
  $applyText = ($applyOutput | Out-String).Trim()
  if ($applyText) {
    $lines = $applyText -split "(`r`n|`n)"
    $filtered = $lines | Where-Object { $_ -match '\b(created|configured|patched|deleted)\b' }
    if ($filtered -and $filtered.Count -gt 0) { $filtered | ForEach-Object { Write-Host $_ } }
    else { Write-Host $applyText }
  }

  # If we tried to change an immutable selector (common when standardizing labels), recreate the deployment
  if ($applyText -match 'field is immutable' -and $applyText -match 'spec.selector') {
    Write-Warning "Detected immutable selector change for deployment 'app' in namespace '$ns'. Recreating it to align labels."
    try {
      & kubectl -n $ns delete deploy app --ignore-not-found --wait=$true | Out-Null
      Write-Host "Re-applying deployment for '$ns'..."
      & kubectl apply -R -f $envTmp | Out-Null
    } catch { Write-Warning "Failed to recreate deployment 'app' in '$ns': $($_.Exception.Message)" }
  }

  Write-Host "Waiting for rollout of deploy/app in '$ns'"; & kubectl -n $ns rollout status deploy/app --timeout $TimeoutRollout
  
  # Internal smoke test via Kubernetes Job
  $smoke = (Get-ChildItem -Path $envTmp -Recurse -File -Include 'smoke-job.yaml','smoke-job.yml' -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($smoke) {
    Write-Host "Running internal smoke job for '$ns'"
    & kubectl -n $ns delete job smoke-health --ignore-not-found --wait=$false | Out-Null
    & kubectl -n $ns apply -f $($smoke.FullName) | Out-Null
    Write-Host "Waiting for smoke job to complete..."
    try {
      & kubectl -n $ns wait --for=condition=complete job/smoke-health --timeout $TimeoutSmoke
      Write-Host "Smoke job: OK" -ForegroundColor Green
    } catch {
      Write-Host "Smoke job failed or timed out in namespace '$ns'" -ForegroundColor Red
      Write-Host "Smoke job logs:" -ForegroundColor Red
      & kubectl -n $ns logs job/smoke-health || $true
      throw
    }
  }
  
  # External smoke test via Ingress
  Write-Host "Testing external access via Ingress for '$ns'"
  Test-IngressEndpoint -Namespace $ns -TimeoutSmoke $TimeoutSmoke
}

function Test-IngressEndpoint([string]$Namespace, [string]$TimeoutSmoke) {
  $hostname = "app.$Namespace.local"
  $timeoutSec = Parse-DurationSeconds -Value $TimeoutSmoke
  $url = "http://localhost/q/health"
  Write-Host "Testing external endpoint: $url (Host: $hostname, timeout: $TimeoutSmoke)"

  try {
    $success = $false
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec -and -not $success) {
      try {
        $headers = @{ "Host" = $hostname }
        $resp = Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $headers -TimeoutSec 5
        if ($resp.StatusCode -eq 200) {
          Write-Host "External smoke test: OK (HTTP $($resp.StatusCode))"
          $ext = "http://$hostname/q/health"
          Write-Host "Endpoint: " -NoNewline; Write-Host $ext -ForegroundColor Blue
          $success = $true
          break
        }
      } catch {
        # Continue to next retry
      }
      if (-not $success) { Start-Sleep -Seconds 2 }
    }

    if (-not $success) {
      $msg = "External smoke test failed: endpoint $hostname did not respond within $TimeoutSmoke"
      Write-Host $msg -ForegroundColor Red
      throw $msg
    }
  } catch {
    $msg = "External smoke test failed: $($_.Exception.Message)"
    Write-Host $msg -ForegroundColor Red
    throw $msg
  }
}

Write-Host ''
Write-Host "6) Deploying to DES (cluster=$K3dCluster ns=$DesNamespace)" -ForegroundColor Green; Write-Host ''
Use-K3dContext $K3dCluster | Out-Null
Deploy-Env -cluster $K3dCluster -ns $DesNamespace -envTmp $desTmp
Write-Host 'DES deploy complete.'

# Display access information
Write-Host ""
Write-Host "=== INFORMAÇÕES DE ACESSO ==="
Write-Host "Para acessar a aplicação externamente, configure o arquivo de hosts:"
Write-Host "Opção 1: Execute como Administrador:"
Write-Host "  pwsh -File scripts/ps/setup-hosts.ps1"
Write-Host ""
Write-Host "Opção 2: Adicione manualmente em C:\Windows\System32\drivers\etc\hosts:"
Write-Host "  127.0.0.1    app.des.local"
Write-Host "  127.0.0.1    app.prd.local"
Write-Host ""
Write-Host "Em seguida, acesse: " -NoNewline; Write-Host "http://app.des.local/hello" -ForegroundColor Blue
Write-Host "Verificação de saúde: " -NoNewline; Write-Host "http://app.des.local/q/health" -ForegroundColor Blue
Write-Host ""

$doPrd = $false
if ($ApprovePrd) { $doPrd = $true } else {
  if ([Environment]::UserInteractive) {
    $ans = Read-Host "Proceed to deploy PRD (cluster=$K3dCluster ns=$PrdNamespace)? [y/N]"
    if ($ans -match '^[Yy]$') { $doPrd = $true }
  }
}

if ($doPrd) {
  Write-Host ''
  Write-Host "7) Deploying to PRD (cluster=$K3dCluster ns=$PrdNamespace)" -ForegroundColor Green; Write-Host ''
  Use-K3dContext $K3dCluster | Out-Null
  Deploy-Env -cluster $K3dCluster -ns $PrdNamespace -envTmp $prdTmp
  Write-Host 'PRD deploy complete.'
} else {
  Write-Host 'PRD deployment skipped.'
}

Remove-Item -Recurse -Force $root
Write-Host 'Done.'
