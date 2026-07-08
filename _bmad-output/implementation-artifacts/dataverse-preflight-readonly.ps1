param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$EvidencePath = "$PSScriptRoot\..\planning-artifacts\tenant-validation-evidence-2026-07-08.md"
)

$ErrorActionPreference = "Stop"

function Invoke-CheckedCommand {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  $output = & $FilePath @Arguments 2>&1
  $exit = $LASTEXITCODE
  [pscustomobject]@{
    Command = "$FilePath $($Arguments -join ' ')"
    ExitCode = $exit
    Output = ($output | Out-String).Trim()
  }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Manifest not found: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

$pac = Get-Command pac -ErrorAction SilentlyContinue
if (-not $pac) {
  throw "Power Platform CLI 'pac' was not found in PATH."
}

$results = @()
$results += Invoke-CheckedCommand -FilePath "pac" -Arguments @("auth", "who")
$results += Invoke-CheckedCommand -FilePath "pac" -Arguments @("env", "who")
$results += Invoke-CheckedCommand -FilePath "pac" -Arguments @("env", "list-settings")

foreach ($result in $results) {
  $result.Output = (($result.Output -split "`r?`n") | ForEach-Object { $_.TrimEnd() }) -join "`n"
}

$failed = $results | Where-Object { $_.ExitCode -ne 0 }
if ($failed) {
  $failed | ForEach-Object {
    Write-Host "FAILED: $($_.Command)"
    Write-Host $_.Output
  }
  throw "One or more read-only preflight commands failed. Authenticate first with: pac auth create --url $($manifest.target.environmentUrl) --name Council-SDH-Dev"
}

$envWho = ($results | Where-Object { $_.Command -like "pac env who*" }).Output
$expectedEnvironmentId = [string]$manifest.target.environmentId
$expectedOrganizationId = [string]$manifest.target.organizationId

$matchesEnvironment = $envWho -match [regex]::Escape($expectedEnvironmentId)
$matchesOrganization = $envWho -match [regex]::Escape($expectedOrganizationId)

$timestamp = (Get-Date).ToString("o")
$authExitCode = ($results | Where-Object { $_.Command -like "pac auth who*" }).ExitCode
$envExitCode = ($results | Where-Object { $_.Command -like "pac env who*" }).ExitCode
$settingsExitCode = ($results | Where-Object { $_.Command -like "pac env list-settings*" }).ExitCode
$evidenceLines = @(
  "",
  "### Preflight Evidence - $timestamp",
  "",
  ("- Manifest: {0}" -f $ManifestPath),
  ("- Expected environment URL: {0}" -f $manifest.target.environmentUrl),
  ("- Expected environment unique name: {0}" -f $manifest.target.environmentUniqueName),
  ("- Expected environment ID: {0}" -f $expectedEnvironmentId),
  ("- Expected organization ID: {0}" -f $expectedOrganizationId),
  ("- Web API endpoint: {0}" -f $manifest.target.webApiEndpoint),
  ("- Discovery endpoint: {0}" -f $manifest.target.discoveryEndpoint),
  ("- pac auth who exit code: {0}" -f $authExitCode),
  ("- pac env who exit code: {0}" -f $envExitCode),
  ("- Environment ID matched in pac env who: {0}" -f $matchesEnvironment),
  ("- Organization ID matched in pac env who: {0}" -f $matchesOrganization),
  ("- pac env list-settings exit code: {0}" -f $settingsExitCode),
  "- pac auth who, pac env who, and pac env list-settings output retained only as summaries to avoid storing raw tenant details."
)
$evidence = $evidenceLines -join [Environment]::NewLine

if (Test-Path -LiteralPath $EvidencePath) {
  Add-Content -LiteralPath $EvidencePath -Value $evidence -Encoding UTF8
} else {
  Set-Content -LiteralPath $EvidencePath -Value $evidence -Encoding UTF8
}

if (-not $matchesEnvironment -or -not $matchesOrganization) {
  throw "Preflight commands succeeded, but environment/org ID match was not proven. Inspect evidence before any write."
}

Write-Host "Preflight read-only validation succeeded."
Write-Host "Evidence appended to $EvidencePath"
