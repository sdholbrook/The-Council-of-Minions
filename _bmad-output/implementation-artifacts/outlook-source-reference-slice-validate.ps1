param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$SlicePath = "$PSScriptRoot\outlook-source-reference-slice.json"
)

$ErrorActionPreference = "Stop"

function Add-Issue {
  param(
    [Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $Issues.Add($Message) | Out-Null
}

function Get-Table {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)][string]$SchemaName
  )

  @($Manifest.tables) | Where-Object { $_.schemaName -eq $SchemaName } | Select-Object -First 1
}

function Get-ChoiceValues {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)][string]$ChoiceName
  )

  $choice = @($Manifest.choices) | Where-Object { $_.name -eq $ChoiceName } | Select-Object -First 1
  @($choice.values)
}

function Test-ContainsAll {
  param(
    [Parameter(Mandatory = $true)][string[]]$Actual,
    [Parameter(Mandatory = $true)][string[]]$Expected
  )

  foreach ($item in $Expected) {
    if ($Actual -notcontains $item) {
      return $false
    }
  }
  return $true
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Manifest not found: $ManifestPath"
}

if (-not (Test-Path -LiteralPath $SlicePath)) {
  throw "Outlook Source Reference slice artifact not found: $SlicePath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$slice = Get-Content -LiteralPath $SlicePath -Raw | ConvertFrom-Json
$issues = [System.Collections.Generic.List[string]]::new()

$sourceTable = Get-Table -Manifest $manifest -SchemaName "com_councilsourcerecord"
if (-not $sourceTable) {
  Add-Issue $issues "Manifest is missing com_councilsourcerecord."
} else {
  $columns = @($sourceTable.columns)
  $columnNames = @($columns | ForEach-Object { $_.name })
  $requiredColumns = @(
    "com_council_source_record_id",
    "com_source_system",
    "com_source_kind",
    "com_source_object_ref",
    "com_source_object_url",
    "com_conversation_ref",
    "com_parent_ref",
    "com_captured_at",
    "com_captured_by",
    "com_observed_modified_at",
    "com_source_version_ref",
    "com_attachment_refs",
    "com_permission_snapshot",
    "com_sensitivity_label",
    "com_retention_or_hold_flags",
    "com_extraction_status",
    "com_source_to_work_item_rationale",
    "com_data_boundary_policy"
  )

  foreach ($columnName in $requiredColumns) {
    if ($columnNames -notcontains $columnName) {
      Add-Issue $issues "Source Record table missing Outlook reference column: $columnName."
    }
  }

  $views = @($sourceTable.views)
  foreach ($viewName in @("New Source Records", "Outlook Source Records", "Mock Outlook Source Records")) {
    if ($views -notcontains $viewName) {
      Add-Issue $issues "Source Record table missing Outlook story view: $viewName."
    }
  }

  $formFields = @()
  foreach ($form in @($sourceTable.forms)) {
    foreach ($section in @($form.sections)) {
      $formFields += @($section.fields)
    }
  }
  foreach ($fieldName in @("com_source_object_ref", "com_source_object_url", "com_conversation_ref", "com_parent_ref", "com_observed_modified_at", "com_source_version_ref", "com_attachment_refs", "com_permission_snapshot", "com_sensitivity_label", "com_retention_or_hold_flags", "com_extraction_status", "com_source_to_work_item_rationale", "com_data_boundary_policy")) {
    if ($formFields -notcontains $fieldName) {
      Add-Issue $issues "Source Record form metadata must expose Outlook reference field: $fieldName."
    }
  }
}

$sourceSystems = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_sourcesystem"
if ($sourceSystems -notcontains "outlook") {
  Add-Issue $issues "com_sourcesystem choice must contain outlook."
}

$sourceKinds = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_sourcekind"
if (-not (Test-ContainsAll -Actual $sourceKinds -Expected @("message", "thread"))) {
  Add-Issue $issues "com_sourcekind choice must contain message and thread."
}

$dataBoundaryPolicies = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_databoundarypolicy"
if (-not (Test-ContainsAll -Actual $dataBoundaryPolicies -Expected @("link_only", "hash_only", "summary_allowed", "unknown"))) {
  Add-Issue $issues "com_databoundarypolicy does not contain required Outlook-safe policy values."
}

$intakeGroup = @($manifest.modelDrivenApp.navigationGroups) | Where-Object { $_.name -eq "Intake" } | Select-Object -First 1
if (-not $intakeGroup -or @($intakeGroup.tables) -notcontains "com_councilsourcerecord") {
  Add-Issue $issues "Council Queue app must expose Source Records in the Intake group."
}

if ($slice.storyKey -ne "1-2-capture-outlook-source-references") {
  Add-Issue $issues "Slice storyKey must be 1-2-capture-outlook-source-references."
}

if ($slice.guards.liveOutlookGraphReadsApproved -ne $false) {
  Add-Issue $issues "Slice guard liveOutlookGraphReadsApproved must remain false until Doug approves live reads."
}

if ($slice.guards.liveTenantWritesApproved -ne $false) {
  Add-Issue $issues "Local Outlook fixture guard liveTenantWritesApproved must remain false because this fixture does not perform writes."
}

if ($slice.outlookCapture.workItemCreationOnSave -ne $false) {
  Add-Issue $issues "Outlook capture must not create a Work Item on save."
}

if ($slice.outlookCapture.requiresExplicitExtractionStep -ne $true) {
  Add-Issue $issues "Outlook capture must require explicit extraction before Work Item creation."
}

if ($slice.outlookCapture.defaultSourceSystem -ne "outlook") {
  Add-Issue $issues "Outlook capture defaultSourceSystem must be outlook."
}

if (@($slice.outlookCapture.allowedSourceKinds) -notcontains "message" -or @($slice.outlookCapture.allowedSourceKinds) -notcontains "thread") {
  Add-Issue $issues "Outlook capture allowedSourceKinds must include message and thread."
}

if ($slice.outlookCapture.graphIdPolicy.requiredPreferHeader -ne 'Prefer: IdType="ImmutableId"') {
  Add-Issue $issues "Outlook capture must require Prefer: IdType=`"ImmutableId`" for authorized Graph reads."
}

$samples = @($slice.outlookCapture.sampleRecords)
if ($samples.Count -lt 2) {
  Add-Issue $issues "Slice must include at least two Outlook sample records for message and thread shapes."
}

foreach ($sample in $samples) {
  foreach ($field in @("com_council_source_record_id", "com_source_system", "com_source_kind", "com_source_object_ref", "com_conversation_ref", "com_captured_at", "com_captured_by", "com_extraction_status", "com_source_to_work_item_rationale", "com_data_boundary_policy")) {
    if (-not $sample.PSObject.Properties.Name.Contains($field) -or -not $sample.$field) {
      Add-Issue $issues "Outlook sample missing required field: $field."
    }
  }

  if ($sample.com_source_system -ne "outlook") {
    Add-Issue $issues "Outlook sample must use source_system outlook."
  }
  if (@("message", "thread") -notcontains $sample.com_source_kind) {
    Add-Issue $issues "Outlook sample must use source_kind message or thread."
  }
  if ($sample.com_extraction_status -ne "new" -and $sample.com_extraction_status -ne "held") {
    Add-Issue $issues "Outlook sample must start with extraction status new or held."
  }
  if ($sample.PSObject.Properties.Name -contains "work_item" -or $sample.PSObject.Properties.Name -contains "workItem") {
    Add-Issue $issues "Outlook sample must not embed or create a Work Item."
  }
  if ($sample.evidenceStatus -eq "mock_manual_not_tenant_verified" -and $sample.com_permission_snapshot -notmatch "mock|manual|not tenant verified") {
    Add-Issue $issues "Mock/manual Outlook samples must be visibly marked as not tenant verified."
  }
}

$messageSample = $samples | Where-Object { $_.com_source_kind -eq "message" } | Select-Object -First 1
if (-not $messageSample) {
  Add-Issue $issues "Missing Outlook message sample."
}

$threadSample = $samples | Where-Object { $_.com_source_kind -eq "thread" } | Select-Object -First 1
if (-not $threadSample) {
  Add-Issue $issues "Missing Outlook thread sample."
}

$linkOnlySamples = $samples | Where-Object { $_.com_data_boundary_policy -eq "link_only" }
foreach ($sample in $linkOnlySamples) {
  if ($sample.com_content_snapshot_ref) {
    Add-Issue $issues "link_only Outlook sample must not store content snapshot."
  }
}

$hashOnlySamples = $samples | Where-Object { $_.com_data_boundary_policy -eq "hash_only" }
foreach ($sample in $hashOnlySamples) {
  if (-not $sample.com_content_hash) {
    Add-Issue $issues "hash_only Outlook sample must include content hash."
  }
  if ($sample.com_content_snapshot_ref) {
    Add-Issue $issues "hash_only Outlook sample must not store content snapshot."
  }
}

if ($issues.Count -gt 0) {
  Write-Host "Outlook Source Reference slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Outlook Source Reference slice validation succeeded."
Write-Host "Samples: $($samples.Count)"
Write-Host "OUTLOOK_SOURCE_REFERENCE_SLICE_VALIDATE_OK"
