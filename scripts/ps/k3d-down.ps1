#!/usr/bin/env pwsh
<#
  scripts/ps/k3d-down.ps1
  Delete the k3d cluster (if exists) and remove hosts block from Windows hosts file.
#>

param(
  [string]$ClusterName = 'hackathon-k3d'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'common.ps1')

$hostsPath = 'C:\Windows\System32\drivers\etc\hosts'
$beginMarker = '# >>> hackathon-2025 hosts BEGIN'
$endMarker = '# <<< hackathon-2025 hosts END'

function Remove-HostsBlock {
  if (-not (Test-Path $hostsPath)) { return }
  $lines = Get-Content -Path $hostsPath
  $inside = $false
  $kept = foreach ($line in $lines) {
    if ($line -eq $beginMarker) { $inside = $true; continue }
    if ($line -eq $endMarker) { $inside = $false; continue }
    if (-not $inside) { $line }
  }
  Set-Content -Path $hostsPath -Value ($kept -join "`n")
  Write-Host "Removed $beginMarker block from hosts file."
}

try {
  if (Get-Command k3d -ErrorAction SilentlyContinue) {
    $exists = (& k3d cluster list -o json | Out-String | ConvertFrom-Json) | Where-Object { $_.name -eq $ClusterName }
    if ($exists) {
      Write-Host "Deleting cluster $ClusterName"
      & k3d cluster delete $ClusterName | Out-Null
    } else {
      Write-Host "Cluster $ClusterName not found. Nothing to do."
    }
  } else {
    Write-Host 'k3d not installed. Skipping cluster deletion.'
  }
} finally {
  Remove-HostsBlock
}
