param(
  [string]$DecisionPath = "$PSScriptRoot\tenant-decision-packet.json",
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [switch]$RequireComplete
)

$ErrorActionPreference = "Stop"

function Add-Issue {
  param(
    [Parameter(Mandatory = $true)]$Issues,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $Issues.Add($Message) | Out-Null
}

function Get-Decision {
  param(
    [Parameter(Mandatory = $true)]$Packet,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $Packet.decisions.PSObject.Properties[$Name].Value
}

function Test-PendingValue {
  param(
    [AllowNull()]$Value
  )

  if ($null -eq $Value) {
    return $true
  }

  $text = [string]$Value
  return [string]::IsNullOrWhiteSpace($text) -or $text -eq "pending"
}

if (-not (Test-Path -LiteralPath $DecisionPath)) {
  throw "Decision packet not found: $DecisionPath"
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Manifest not found: $ManifestPath"
}

$packet = Get-Content -LiteralPath $DecisionPath -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$issues = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

foreach ($field in @("environmentUrl", "environmentUniqueName", "environmentId", "organizationId")) {
  $packetValue = [string]$packet.target.$field
  $manifestValue = [string]$manifest.target.$field
  if ($packetValue -ne $manifestValue) {
    Add-Issue $issues "Decision packet target.$field '$packetValue' does not match manifest target.$field '$manifestValue'."
  }
}

$requiredDecisionNames = @(
  "dataverseMvpOperationalStore",
  "fabricIqGraphPhase2",
  "tenantDomainOrId",
  "environmentType",
  "outlookGraphLiveReads",
  "dataverseSandboxWrites",
  "sourceBodyPolicy",
  "publisherPrefix",
  "modelDrivenAppSurface",
  "powerAppsMcpAgentFeedEvaluation",
  "humanApprovalOwner"
)

foreach ($name in $requiredDecisionNames) {
  $decision = Get-Decision -Packet $packet -Name $name
  if (-not $decision) {
    Add-Issue $issues "Decision packet is missing decision: $name."
    continue
  }

  if (Test-PendingValue $decision.value) {
    Add-Issue $warnings "Decision pending: $name - $($decision.question)"
    continue
  }

  $allowedValues = @($decision.allowedValues)
  if ($allowedValues.Count -gt 0 -and $allowedValues -notcontains $decision.value) {
    Add-Issue $issues "Decision $name has invalid value '$($decision.value)'. Allowed: $($allowedValues -join ', ')."
  }
}

$publisherPrefix = [string](Get-Decision -Packet $packet -Name "publisherPrefix").value
if (-not (Test-PendingValue $publisherPrefix) -and $publisherPrefix -notmatch '^[a-z][a-z0-9]{1,7}$') {
  Add-Issue $issues "Publisher prefix must match ^[a-z][a-z0-9]{1,7}$."
}

$writesDecision = (Get-Decision -Packet $packet -Name "dataverseSandboxWrites").value
$dataverseDecision = (Get-Decision -Packet $packet -Name "dataverseMvpOperationalStore").value
$modelDrivenDecision = (Get-Decision -Packet $packet -Name "modelDrivenAppSurface").value

if ($writesDecision -eq "allowed_after_readonly_preflight" -and $dataverseDecision -ne "approved") {
  Add-Issue $issues "Dataverse writes cannot be allowed unless Dataverse is approved as MVP operational store."
}

if ($writesDecision -eq "allowed_after_readonly_preflight" -and $modelDrivenDecision -eq "rejected") {
  Add-Issue $warnings "Dataverse writes are conditionally allowed, but the model-driven app surface is rejected. Confirm alternate Council Queue surface before app creation."
}

foreach ($guard in @("noTenantWritesUntilReadonlyPreflightMatches", "noWritesWhenDecisionPending", "noOutboundAction", "noFlowPublish", "noAgentPublish", "noAppRegistration", "noFabricMutation")) {
  if ($packet.guards.$guard -ne $true) {
    Add-Issue $issues "Required guard must be true: $guard."
  }
}

if ($issues.Count -gt 0) {
  Write-Host "Tenant decision packet validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

if ($warnings.Count -gt 0) {
  Write-Host "Tenant decision packet validation warnings:"
  foreach ($warning in $warnings) {
    Write-Host "- $warning"
  }

  if ($RequireComplete) {
    throw "Decision packet is incomplete. Resolve pending decisions before write approval."
  }
}

Write-Host "Tenant decision packet validation succeeded."
Write-Host "Pending decisions: $($warnings.Count)"
Write-Host "TENANT_DECISION_PACKET_VALIDATE_OK"
