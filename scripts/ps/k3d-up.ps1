#!/usr/bin/env pwsh
<#!
  scripts/ps/k3d-up.ps1
  Create/ensure a k3d cluster exists and update Windows hosts file from infra/k3d/hosts.conf.
!>

param(
  [string]$ClusterName = 'hackathon-k3d'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Require-Cmd($name) { if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Required command not found: $name" } }
Require-Cmd k3d
Require-Cmd kubectl

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
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
  Set-Content -Path $hostsPath -Value ($newContent -join "`n") -Encoding ascii
  Write-Host "Hosts file updated."
} else {
  Write-Host "No hosts.conf found; skipping hosts update"
}

Write-Host 'k3d cluster is ready.'
