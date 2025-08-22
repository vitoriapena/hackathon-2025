#!/usr/bin/env pwsh
<#
  scripts/ps/common.ps1
  Shared PowerShell helpers for local build/deploy and k3d operations.
#>

$ErrorActionPreference = $ErrorActionPreference ?? 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Require-Cmd {
  param([Parameter(Mandatory)][string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $Name"
  }
}

function Resolve-RepoRoot {
  param([string]$StartFrom)
  $start = $StartFrom
  if (-not $start) { $start = $PSScriptRoot }
  if (-not $start) { $start = Split-Path -Parent $PSCommandPath }
  $dir = $start
  while ($dir -and ($dir -ne [System.IO.Path]::GetPathRoot($dir))) {
    if ((Test-Path (Join-Path $dir 'pom.xml')) -or (Test-Path (Join-Path $dir '.git'))) { return $dir }
    $dir = Split-Path -Parent $dir
  }
  # Fallback: two levels up from scripts/ps
  return Split-Path -Parent (Split-Path -Parent $start)
}

function Remove-Diacritics {
  param([string]$s)
  if (-not $s) { return $s }
  $norm = $s.Normalize([System.Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $norm.ToCharArray()) {
    $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($c)
    if ($cat -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
  }
  return $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)
}

function Sanitize-Name {
  param([string]$s)
  if (-not $s) { return $s }
  $noDi = Remove-Diacritics $s
  $lower = $noDi.ToLowerInvariant()
  $san = [regex]::Replace($lower, '[^a-z0-9\._-]+', '-')
  $san = $san.Trim('-')
  if (-not $san) { throw "Sanitized name for '$s' is empty; provide explicit value" }
  return $san
}

function Parse-DurationSeconds {
  param([Parameter(Mandatory)][string]$Value)
  $v = $Value.Trim()
  if ($v -match '^(\d+)$') { return [int]$Matches[1] }
  if ($v -match '^(\d+)\s*[sS]$') { return [int]$Matches[1] }
  if ($v -match '^(\d+)\s*[mM]$') { return [int]$Matches[1] * 60 }
  if ($v -match '^(\d+)\s*[hH]$') { return [int]$Matches[1] * 3600 }
  try { return [int]([TimeSpan]::Parse($v).TotalSeconds) } catch { }
  throw "Invalid duration format: '$Value'. Use seconds (e.g. '60s'), minutes ('2m'), hours ('1h') or hh:mm:ss."
}

function Get-OrgRepo {
  try {
    $url = git remote get-url origin 2>$null
    if ($url) {
      if ($url -match "[/:]{1}([^/]+)/([^/.]+)(\\.git)?$") { return @($Matches[1], $Matches[2]) }
    }
  } catch { }
  return $null
}

function Infer-OrgRepo { return Get-OrgRepo }

function Render-ManifestsEnv {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Namespace,
    [Parameter(Mandatory)][string]$OutDir,
    [Parameter(Mandatory)][string]$Image
  )
  New-Item -ItemType Directory -Force -Path (Join-Path $OutDir 'base') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $OutDir 'overlay') | Out-Null
  Copy-Item -Recurse -Force -Path (Join-Path $RepoRoot 'deploy/base/*') -Destination (Join-Path $OutDir 'base')
  $overlayPath = Join-Path $RepoRoot (Join-Path 'deploy' $Namespace)
  if (Test-Path $overlayPath) { Copy-Item -Recurse -Force -Path (Join-Path $overlayPath '*') -Destination (Join-Path $OutDir 'overlay') }
  Get-ChildItem -Recurse -Path $OutDir -Include *.yaml,*.yml | ForEach-Object {
    $content = Get-Content -Raw -Path $_.FullName
    $content = $content -replace 'ghcr.io/<org>/<repo>:<sha>', $Image
    $content = $content -replace '\$\{NAMESPACE\}', $Namespace
    Set-Content -NoNewline -Path $_.FullName -Value $content
  }
}

function Use-K3dContext {
  param([Parameter(Mandatory)][string]$Cluster)
  $ctx = "k3d-$Cluster"
  $names = (& kubectl config get-contexts -o name) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  if ($names -contains $ctx) { & kubectl config use-context $ctx | Out-Null; return $true }
  return $false
}
