param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$SlicePath = "$PSScriptRoot\manual-source-record-slice.json"
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
  throw "Manual Source Record slice artifact not found: $SlicePath"
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
    "com_captured_at",
    "com_captured_by",
    "com_extraction_status",
    "com_source_to_work_item_rationale",
    "com_data_boundary_policy"
  )

  foreach ($columnName in $requiredColumns) {
    if ($columnNames -notcontains $columnName) {
      Add-Issue $issues "Source Record table missing required story column: $columnName."
    }
  }

  foreach ($columnName in @("com_council_source_record_id", "com_source_system", "com_source_kind", "com_source_object_ref", "com_captured_at", "com_captured_by", "com_extraction_status", "com_data_boundary_policy")) {
    $column = $columns | Where-Object { $_.name -eq $columnName } | Select-Object -First 1
    if (-not $column.required) {
      Add-Issue $issues "Source Record column must be required for manual capture: $columnName."
    }
  }

  $views = @($sourceTable.views)
  foreach ($viewName in @("New Source Records", "Held Source Records")) {
    if ($views -notcontains $viewName) {
      Add-Issue $issues "Source Record table missing MVP view: $viewName."
    }
  }

  $formFields = @()
  foreach ($form in @($sourceTable.forms)) {
    foreach ($section in @($form.sections)) {
      $formFields += @($section.fields)
    }
  }
  foreach ($fieldName in @("com_source_object_ref", "com_source_object_url", "com_data_boundary_policy", "com_sensitivity_label", "com_retention_or_hold_flags", "com_extraction_status", "com_source_to_work_item_rationale")) {
    if ($formFields -notcontains $fieldName) {
      Add-Issue $issues "Source Record form metadata must expose field: $fieldName."
    }
  }
}

$sourceSystems = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_sourcesystem"
if ($sourceSystems -notcontains "manual") {
  Add-Issue $issues "com_sourcesystem choice must contain manual."
}

$sourceKinds = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_sourcekind"
if ($sourceKinds -notcontains "manual_note") {
  Add-Issue $issues "com_sourcekind choice must contain manual_note."
}

$dataBoundaryPolicies = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_databoundarypolicy"
if (-not (Test-ContainsAll -Actual $dataBoundaryPolicies -Expected @("link_only", "hash_only", "summary_allowed", "full_snapshot_allowed", "unknown"))) {
  Add-Issue $issues "com_databoundarypolicy does not contain all required policy values."
}

$extractionStatuses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_extractionstatus"
if (-not (Test-ContainsAll -Actual $extractionStatuses -Expected @("new", "held", "extracted", "failed", "superseded"))) {
  Add-Issue $issues "com_extractionstatus does not contain required Source Record lifecycle values."
}

$intakeGroup = @($manifest.modelDrivenApp.navigationGroups) | Where-Object { $_.name -eq "Intake" } | Select-Object -First 1
if (-not $intakeGroup -or @($intakeGroup.tables) -notcontains "com_councilsourcerecord") {
  Add-Issue $issues "Council Queue app must expose Source Records in the Intake group."
}

if ($slice.storyKey -ne "1-1-capture-manual-source-records") {
  Add-Issue $issues "Slice storyKey must be 1-1-capture-manual-source-records."
}

if ($slice.guards.liveTenantWritesApproved -ne $false) {
  Add-Issue $issues "Slice guard liveTenantWritesApproved must remain false until Doug approves writes."
}

if ($slice.manualCapture.workItemCreationOnSave -ne $false) {
  Add-Issue $issues "Manual capture must not create a Work Item on save."
}

if ($slice.manualCapture.requiresExplicitExtractionStep -ne $true) {
  Add-Issue $issues "Manual capture must require explicit extraction before Work Item creation."
}

if ($slice.manualCapture.defaultSourceSystem -ne "manual") {
  Add-Issue $issues "Manual capture defaultSourceSystem must be manual."
}

if ($slice.manualCapture.defaultSourceKind -ne "manual_note") {
  Add-Issue $issues "Manual capture defaultSourceKind must be manual_note."
}

$samples = @($slice.manualCapture.sampleRecords)
if ($samples.Count -lt 3) {
  Add-Issue $issues "Slice must include at least three manual sample records for link_only, hash_only, and summary_allowed."
}

foreach ($policy in @("link_only", "hash_only", "summary_allowed")) {
  $sample = $samples | Where-Object { $_.com_data_boundary_policy -eq $policy } | Select-Object -First 1
  if (-not $sample) {
    Add-Issue $issues "Missing manual sample record for data boundary policy: $policy."
    continue
  }

  foreach ($field in @("com_council_source_record_id", "com_source_system", "com_source_kind", "com_source_object_ref", "com_captured_at", "com_captured_by", "com_extraction_status", "com_source_to_work_item_rationale", "com_data_boundary_policy")) {
    if (-not $sample.PSObject.Properties.Name.Contains($field) -or -not $sample.$field) {
      Add-Issue $issues "Sample $policy missing required field: $field."
    }
  }

  if ($sample.com_source_system -ne "manual") {
    Add-Issue $issues "Sample $policy must use source_system manual."
  }
  if ($sample.com_source_kind -ne "manual_note") {
    Add-Issue $issues "Sample $policy must use source_kind manual_note."
  }
  if ($sample.com_extraction_status -ne "new" -and $sample.com_extraction_status -ne "held") {
    Add-Issue $issues "Sample $policy must start with extraction status new or held."
  }
  if ($sample.PSObject.Properties.Name -contains "work_item" -or $sample.PSObject.Properties.Name -contains "workItem") {
    Add-Issue $issues "Sample $policy must not embed or create a Work Item."
  }
}

$linkOnly = $samples | Where-Object { $_.com_data_boundary_policy -eq "link_only" } | Select-Object -First 1
if ($linkOnly -and $linkOnly.com_content_snapshot_ref) {
  Add-Issue $issues "link_only sample must not store content snapshot."
}

$hashOnly = $samples | Where-Object { $_.com_data_boundary_policy -eq "hash_only" } | Select-Object -First 1
if ($hashOnly) {
  if (-not $hashOnly.com_content_hash) {
    Add-Issue $issues "hash_only sample must include content hash."
  }
  if ($hashOnly.com_content_snapshot_ref) {
    Add-Issue $issues "hash_only sample must not store content snapshot."
  }
}

$summaryAllowed = $samples | Where-Object { $_.com_data_boundary_policy -eq "summary_allowed" } | Select-Object -First 1
if ($summaryAllowed -and -not $summaryAllowed.com_content_snapshot_ref) {
  Add-Issue $issues "summary_allowed sample should include a summary snapshot reference."
}

if ($issues.Count -gt 0) {
  Write-Host "Manual Source Record slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Manual Source Record slice validation succeeded."
Write-Host "Samples: $($samples.Count)"
Write-Host "MANUAL_SOURCE_RECORD_SLICE_VALIDATE_OK"
