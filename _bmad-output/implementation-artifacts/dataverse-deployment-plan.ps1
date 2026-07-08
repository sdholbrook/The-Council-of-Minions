param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [switch]$ExecuteWrites
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Manifest not found: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

Write-Host "Council Dataverse MVP deployment plan"
Write-Host "Manifest: $ManifestPath"
Write-Host "Target environment: $($manifest.target.environmentUrl)"
Write-Host "Environment unique name: $($manifest.target.environmentUniqueName)"
Write-Host "Expected environment ID: $($manifest.target.environmentId)"
Write-Host "Expected organization ID: $($manifest.target.organizationId)"
Write-Host "Web API endpoint: $($manifest.target.webApiEndpoint)"
Write-Host "Discovery endpoint: $($manifest.target.discoveryEndpoint)"
Write-Host ""

if (-not $ExecuteWrites) {
  Write-Host "DRY RUN ONLY. No tenant writes will be performed."
  Write-Host "This script currently emits the ordered deployment plan and guard checks."
  Write-Host "Use -ExecuteWrites only after Doug approves Dataverse sandbox writes and a reviewed write implementation exists."
  Write-Host ""
}

if ($ExecuteWrites) {
  throw "Write execution is intentionally not implemented yet. Use this plan for review, then implement table creation through approved Power Platform tooling or reviewed Dataverse Web API scripts."
}

Write-Host "Guard requirements:"
Write-Host "- Doug approval before write: $($manifest.guards.requiresDougApprovalBeforeWrite)"
Write-Host "- pac env who must match: $($manifest.guards.requiresPacEnvWhoMatch)"
Write-Host "- No outbound action: $($manifest.guards.noOutboundAction)"
Write-Host "- No flow publish: $($manifest.guards.noFlowPublish)"
Write-Host "- No agent publish: $($manifest.guards.noAgentPublish)"
Write-Host "- No app registration: $($manifest.guards.noAppRegistration)"
Write-Host "- No Fabric mutation: $($manifest.guards.noFabricMutation)"
Write-Host ""

Write-Host "Solution:"
Write-Host "- Display name: $($manifest.solution.displayName)"
Write-Host "- Unique name: $($manifest.solution.uniqueName)"
Write-Host "- Publisher prefix: $($manifest.solution.publisherPrefix)"
Write-Host "- Version: $($manifest.solution.version)"
Write-Host ""

Write-Host "Choices to create:"
foreach ($choice in $manifest.choices) {
  Write-Host "- $($choice.name): $($choice.displayName) [$($choice.values -join ', ')]"
}
Write-Host ""

Write-Host "Tables to create:"
foreach ($table in $manifest.tables) {
  Write-Host "- $($table.schemaName): $($table.displayName) ($($table.columns.Count) columns, contract: $($table.contract))"
  foreach ($column in $table.columns) {
    $flags = @()
    if ($column.required) { $flags += "required" }
    if ($column.alternateKey) { $flags += "alternate-key" }
    if ($column.choice) { $flags += "choice=$($column.choice)" }
    if ($column.target) { $flags += "target=$($column.target)" }
    $flagText = if ($flags.Count) { " [$($flags -join ', ')]" } else { "" }
    Write-Host "  - $($column.name): $($column.type)$flagText"
  }
}
Write-Host ""

Write-Host "Model-driven app:"
Write-Host "- $($manifest.modelDrivenApp.displayName) ($($manifest.modelDrivenApp.uniqueName))"
foreach ($group in $manifest.modelDrivenApp.navigationGroups) {
  Write-Host "  - $($group.name): $($group.tables -join ', ')"
}
Write-Host ""

Write-Host "Recommended next command before any write:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSScriptRoot\dataverse-preflight-readonly.ps1`""
