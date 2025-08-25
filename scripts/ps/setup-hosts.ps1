#!/usr/bin/env pwsh
<#
  scripts/ps/setup-hosts.ps1
  Configure Windows hosts file for local development with k3d ingress.
  Requires: Administrator privileges
#>

param(
  [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$marker = "# hackathon-2025 local development"
$entries = @(
  "127.0.0.1    app.des.local",
  "127.0.0.1    app.prd.local"
)

# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Error "This script requires Administrator privileges. Run PowerShell as Administrator."
  exit 1
}

Write-Host "Managing hosts file: $hostsFile"

# Read current hosts file
$currentContent = Get-Content -Path $hostsFile -ErrorAction SilentlyContinue
if (-not $currentContent) { $currentContent = @() }

if ($Remove) {
  Write-Host "Removing hackathon-2025 entries from hosts file..."
  $newContent = @()
  $inBlock = $false
  
  foreach ($line in $currentContent) {
    if ($line -eq $marker) {
      $inBlock = $true
      continue
    }
    if ($inBlock -and ($line.Trim() -eq "" -or $line.StartsWith("#"))) {
      if ($line.Trim() -eq "") { $inBlock = $false }
      continue
    }
    if ($inBlock) { continue }
    $newContent += $line
  }
  
  Set-Content -Path $hostsFile -Value $newContent -Encoding UTF8
  Write-Host "Removed hackathon-2025 entries from hosts file."
} else {
  Write-Host "Adding hackathon-2025 entries to hosts file..."
  
  # Check if entries already exist
  $hasMarker = $currentContent -contains $marker
  if ($hasMarker) {
    Write-Host "Entries already exist. Remove first with -Remove parameter."
    exit 0
  }
  
  # Add entries
  $newContent = $currentContent + @("", $marker) + $entries + @("")
  Set-Content -Path $hostsFile -Value $newContent -Encoding UTF8
  Write-Host "Added hackathon-2025 entries to hosts file."
  Write-Host ""
  Write-Host "You can now access:"
  Write-Host "  http://app.des.local"
  Write-Host "  http://app.prd.local"
}
