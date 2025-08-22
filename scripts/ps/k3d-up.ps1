#!/usr/bin/env pwsh
<#
  scripts/ps/k3d-up.ps1
  Create/ensure a k3d cluster exists and update Windows hosts file from infra/k3d/hosts.conf.
#>

param(
  [string]$ClusterName = 'hackathon-k3d'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Require-Cmd($name) { if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Required command not found: $name" } }
$RequireCmd = 'k3d','kubectl'
foreach ($c in $RequireCmd) { if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { throw "Required command not found: $c" } }

function Get-RepoRoot {
  # Start from script directory and walk up until we find a repository marker (pom.xml or .git)
  $dir = Split-Path -Parent $PSCommandPath
  while ($dir -and ($dir -ne [System.IO.Path]::GetPathRoot($dir))) {
  if ((Test-Path (Join-Path $dir 'pom.xml')) -or (Test-Path (Join-Path $dir '.git'))) { return $dir }
    $dir = Split-Path -Parent $dir
  }
  # fallback to three levels up (original scripts/ -> repo root)
  return Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
}

$repoRoot = Get-RepoRoot
$k3dConfig = Join-Path $repoRoot 'infra/k3d/cluster.yaml'
$hostsFileConf = Join-Path $repoRoot 'infra/k3d/hosts.conf'
$hostsPath = 'C:\Windows\System32\drivers\etc\hosts'
$beginMarker = '# >>> hackathon-2025 hosts BEGIN'
$endMarker = '# <<< hackathon-2025 hosts END'

# Create cluster if not exists
$exists = (& k3d cluster list -o json | Out-String | ConvertFrom-Json) | Where-Object { $_.name -eq $ClusterName }
if ($exists) {
  Write-Host "Cluster $ClusterName already exists. Skipping creation."
} else {
  Write-Host "Creating cluster $ClusterName from $k3dConfig"
  & k3d cluster create $ClusterName -c $k3dConfig
}

# Apply namespaces.yaml if present
$nsFile = Join-Path $repoRoot 'deploy/base/namespaces.yaml'
if (Test-Path $nsFile) { & kubectl apply -f $nsFile | Out-Null }

# Update hosts file (run PowerShell as Administrator)
if (Test-Path $hostsFileConf) {
  Write-Host "Updating $hostsPath from $hostsFileConf (run PowerShell as Administrator)"
  # Read existing hosts and remove previous marked block
  $lines = Get-Content -Path $hostsPath -ErrorAction Stop
  $inside = $false
  $kept = foreach ($line in $lines) {
    if ($line -eq $beginMarker) { $inside = $true; continue }
    if ($line -eq $endMarker) { $inside = $false; continue }
    if (-not $inside) { $line }
  }
  # Read hosts.conf and strip comments/blank lines
  $hostsBodyLines = Get-Content -Path $hostsFileConf -ErrorAction Stop | Where-Object { $_ -and ($_ -notmatch '^\s*#') }
  $newContent = @()
  $newContent += $kept
  if ($newContent.Count -gt 0 -and $newContent[-1] -ne '') { $newContent += '' }
  $newContent += $beginMarker
  $newContent += $hostsBodyLines
  $newContent += $endMarker
  try {
    Set-Content -Path $hostsPath -Value ($newContent -join "`n") -Encoding ascii
    Write-Host "Hosts file updated."
  } catch {
    Write-Host "Failed to update hosts file: $($_.Exception.Message)"
    Write-Host "You can re-run this script from an elevated PowerShell (Run as Administrator) to update $hostsPath, or copy the contents of infra/k3d/hosts.conf into the hosts file manually."
  }
} else {
  Write-Host "No hosts.conf found; skipping hosts update"
}

Write-Host 'k3d cluster is ready.'
