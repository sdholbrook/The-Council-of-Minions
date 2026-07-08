param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [switch]$RequireTargetAuth
)

$ErrorActionPreference = "Stop"

function Invoke-OptionalCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  $cmd = Get-Command $Command -ErrorAction SilentlyContinue
  if (-not $cmd) {
    return [pscustomobject]@{
      Command = "$Command $($Arguments -join ' ')"
      Found = $false
      ExitCode = $null
      Output = ""
    }
  }

  $output = & $Command @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  [pscustomobject]@{
    Command = "$Command $($Arguments -join ' ')"
    Found = $true
    ExitCode = $exitCode
    Output = ($output | Out-String).Trim()
  }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Manifest not found: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$expectedUrl = [string]$manifest.target.environmentUrl
$expectedEnvironmentId = [string]$manifest.target.environmentId
$expectedOrganizationId = [string]$manifest.target.organizationId
$expectedUniqueName = [string]$manifest.target.environmentUniqueName

Write-Host "Council tenant local prerequisite check"
Write-Host "Manifest: $ManifestPath"
Write-Host "Expected environment URL: $expectedUrl"
Write-Host "Expected environment unique name: $expectedUniqueName"
Write-Host "Expected environment ID: $expectedEnvironmentId"
Write-Host "Expected organization ID: $expectedOrganizationId"
Write-Host ""

$pacHelp = Invoke-OptionalCommand -Command "pac" -Arguments @("help")
if (-not $pacHelp.Found) {
  throw "Power Platform CLI 'pac' was not found in PATH."
}

if ($pacHelp.ExitCode -ne 0) {
  throw "Power Platform CLI 'pac help' failed."
}

$pacVersionLine = (($pacHelp.Output -split "`r?`n") | Where-Object { $_ -match '^Version:' } | Select-Object -First 1)
Write-Host "Power Platform CLI: found"
if ($pacVersionLine) {
  Write-Host $pacVersionLine
}

$pacAuthList = Invoke-OptionalCommand -Command "pac" -Arguments @("auth", "list")
if ($pacAuthList.ExitCode -ne 0) {
  Write-Host ""
  Write-Host "WARNING: pac auth list failed. Interactive auth is probably needed."
  Write-Host $pacAuthList.Output
} else {
  Write-Host ""
  Write-Host "pac auth list succeeded."
}

$activeAuthLine = ""
if ($pacAuthList.Output) {
  $activeAuthLine = (($pacAuthList.Output -split "`r?`n") | Where-Object { $_ -match '\*\s+UNIVERSAL' } | Select-Object -First 1)
}

$targetAuthVisible = $false
if ($pacAuthList.Output -and $pacAuthList.Output -match [regex]::Escape($expectedUrl)) {
  $targetAuthVisible = $true
}

$activeAuthMatchesTarget = $false
if ($activeAuthLine -and $activeAuthLine -match [regex]::Escape($expectedUrl)) {
  $activeAuthMatchesTarget = $true
}

if ($activeAuthLine) {
  Write-Host "Active PAC auth profile:"
  Write-Host $activeAuthLine
} else {
  Write-Host "Active PAC auth profile: not detected"
}

Write-Host "Council target auth visible in pac auth list: $targetAuthVisible"
Write-Host "Active auth points to Council target URL: $activeAuthMatchesTarget"

$azVersion = Invoke-OptionalCommand -Command "az" -Arguments @("version")
Write-Host ""
if ($azVersion.Found -and $azVersion.ExitCode -eq 0) {
  $azVersionLine = (($azVersion.Output -split "`r?`n") | Where-Object { $_ -match '"azure-cli"' } | Select-Object -First 1)
  Write-Host "Azure CLI: found"
  if ($azVersionLine) {
    Write-Host $azVersionLine.Trim()
  }
} elseif ($azVersion.Found) {
  Write-Host "Azure CLI: found but version check failed"
  Write-Host $azVersion.Output
} else {
  Write-Host "Azure CLI: not found"
}

Write-Host ""
Write-Host "Next safe command for Doug-present interactive auth:"
Write-Host "  pac auth create --url $expectedUrl --name Council-SDH-Dev"
Write-Host ""
Write-Host "Next safe read-only validation after auth:"
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\dataverse-preflight-readonly.ps1`""

if ($RequireTargetAuth -and -not $activeAuthMatchesTarget) {
  throw "Active PAC auth does not point to the Council target. Run pac auth create/select for $expectedUrl before tenant validation."
}

Write-Host ""
Write-Host "TENANT_PREREQ_LOCAL_CHECK_OK"
if (-not $activeAuthMatchesTarget) {
  Write-Host "WARNING: Active PAC auth is not the Council target. Do not run tenant preflight or writes until auth is created or selected for $expectedUrl."
}
