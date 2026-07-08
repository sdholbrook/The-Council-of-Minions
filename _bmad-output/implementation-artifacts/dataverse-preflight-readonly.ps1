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
$evidence = @"

### Preflight Evidence - $timestamp

- Manifest: `$ManifestPath`
- Expected environment URL: `$($manifest.target.environmentUrl)`
- Expected environment unique name: `$($manifest.target.environmentUniqueName)`
- Expected environment ID: `$expectedEnvironmentId`
- Expected organization ID: `$expectedOrganizationId`
- Web API endpoint: `$($manifest.target.webApiEndpoint)`
- Discovery endpoint: `$($manifest.target.discoveryEndpoint)`
- `pac auth who` exit code: $(($results | Where-Object { $_.Command -like "pac auth who*" }).ExitCode)
- `pac env who` exit code: $(($results | Where-Object { $_.Command -like "pac env who*" }).ExitCode)
- Environment ID matched in `pac env who`: $matchesEnvironment
- Organization ID matched in `pac env who`: $matchesOrganization
- `pac env list-settings` exit code: $(($results | Where-Object { $_.Command -like "pac env list-settings*" }).ExitCode)

#### pac auth who

````text
$(($results | Where-Object { $_.Command -like "pac auth who*" }).Output)
````

#### pac env who

````text
$envWho
````

#### pac env list-settings

````text
$(($results | Where-Object { $_.Command -like "pac env list-settings*" }).Output)
````

"@

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
