param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$ExtractionPath = "$PSScriptRoot\proposed-work-item-extraction-slice.json",
  [string]$ManualSlicePath = "$PSScriptRoot\manual-source-record-slice.json",
  [string]$OutlookSlicePath = "$PSScriptRoot\outlook-source-reference-slice.json"
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

foreach ($path in @($ManifestPath, $ExtractionPath, $ManualSlicePath, $OutlookSlicePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required extraction validation input not found: $path"
  }
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$extraction = Get-Content -LiteralPath $ExtractionPath -Raw | ConvertFrom-Json
$manualSlice = Get-Content -LiteralPath $ManualSlicePath -Raw | ConvertFrom-Json
$outlookSlice = Get-Content -LiteralPath $OutlookSlicePath -Raw | ConvertFrom-Json
$issues = [System.Collections.Generic.List[string]]::new()

$sourceTable = Get-Table -Manifest $manifest -SchemaName "com_councilsourcerecord"
$workItemTable = Get-Table -Manifest $manifest -SchemaName "com_councilworkitem"
$workItemSourceTable = Get-Table -Manifest $manifest -SchemaName "com_councilworkitemsource"

if (-not $sourceTable) {
  Add-Issue $issues "Manifest is missing com_councilsourcerecord."
}
if (-not $workItemTable) {
  Add-Issue $issues "Manifest is missing com_councilworkitem."
}
if (-not $workItemSourceTable) {
  Add-Issue $issues "Manifest is missing com_councilworkitemsource."
}

if ($workItemTable) {
  $columns = @($workItemTable.columns)
  $columnNames = @($columns | ForEach-Object { $_.name })
  $requiredColumns = @(
    "com_council_work_item_id",
    "com_type",
    "com_summary",
    "com_state_group",
    "com_owner_candidate",
    "com_owner_candidate_confidence",
    "com_urgency",
    "com_risk_class",
    "com_confidence_summary",
    "com_primary_source_record",
    "com_rationale",
    "com_recommended_next_action",
    "com_approval_required",
    "com_semantic_contract_version",
    "com_auto_creation_policy_result",
    "com_policy_flags"
  )

  foreach ($columnName in $requiredColumns) {
    if ($columnNames -notcontains $columnName) {
      Add-Issue $issues "Work Item table missing extraction story column: $columnName."
    }
  }

  $primarySource = $columns | Where-Object { $_.name -eq "com_primary_source_record" } | Select-Object -First 1
  if (-not $primarySource -or $primarySource.type -ne "lookup" -or $primarySource.target -ne "com_councilsourcerecord" -or $primarySource.required -ne $true) {
    Add-Issue $issues "Work Item primary source must be a required lookup to com_councilsourcerecord."
  }

  foreach ($viewName in @("Proposed Work Items", "Needs Human Approval")) {
    if (@($workItemTable.views) -notcontains $viewName) {
      Add-Issue $issues "Work Item table missing view: $viewName."
    }
  }
}

if ($workItemSourceTable) {
  $columns = @($workItemSourceTable.columns)
  $sourceLookup = $columns | Where-Object { $_.name -eq "com_source_record" } | Select-Object -First 1
  $workItemLookup = $columns | Where-Object { $_.name -eq "com_work_item" } | Select-Object -First 1
  if (-not $sourceLookup -or $sourceLookup.target -ne "com_councilsourcerecord") {
    Add-Issue $issues "Work Item Source must look up to com_councilsourcerecord."
  }
  if (-not $workItemLookup -or $workItemLookup.target -ne "com_councilworkitem") {
    Add-Issue $issues "Work Item Source must look up to com_councilworkitem."
  }
}

$workItemTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemtype"
if (-not (Test-ContainsAll -Actual $workItemTypes -Expected @("decision", "delegation", "follow_up", "request", "risk", "artifact_task", "meeting_action"))) {
  Add-Issue $issues "com_workitemtype does not contain all MVP Work Item types."
}

$stateGroups = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemstategroup"
if ($stateGroups -notcontains "proposed") {
  Add-Issue $issues "com_workitemstategroup must contain proposed."
}

$riskClasses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_riskclass"
if (-not (Test-ContainsAll -Actual $riskClasses -Expected @("none", "relationship", "legal", "finance", "delivery", "sensitive", "governance", "unknown"))) {
  Add-Issue $issues "com_riskclass does not contain all MVP risk classes."
}

if ($extraction.storyKey -ne "1-3-extract-proposed-work-items-from-source-records") {
  Add-Issue $issues "Extraction slice storyKey must be 1-3-extract-proposed-work-items-from-source-records."
}

foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "noReceiptCreationInThisSlice", "requiresExplicitHumanApprovalForExecution", "sourceRecordsRemainSeparate")) {
  if ($extraction.guards.$guard -ne $true) {
    Add-Issue $issues "Extraction guard must be true: $guard."
  }
}

if ($extraction.extractionRun.inputSourceRecordsFrom -notcontains "manual-source-record-slice.json") {
  Add-Issue $issues "Extraction run must reference manual-source-record-slice.json as an input."
}
if ($extraction.extractionRun.inputSourceRecordsFrom -notcontains "outlook-source-reference-slice.json") {
  Add-Issue $issues "Extraction run must reference outlook-source-reference-slice.json as an input."
}

$knownSourceIds = @()
$knownSourceIds += @($manualSlice.manualCapture.sampleRecords | ForEach-Object { $_.com_council_source_record_id })
$knownSourceIds += @($outlookSlice.outlookCapture.sampleRecords | ForEach-Object { $_.com_council_source_record_id })

$proposedItems = @($extraction.extractionRun.proposedWorkItems)
if ($proposedItems.Count -lt 2) {
  Add-Issue $issues "Extraction slice must include at least two proposed Work Item examples."
}

$ids = @{}
foreach ($item in $proposedItems) {
  foreach ($field in @("com_council_work_item_id", "com_title", "com_type", "com_summary", "com_state_group", "com_urgency", "com_risk_class", "com_confidence_summary", "com_primary_source_record", "com_rationale", "com_recommended_next_action", "com_approval_required", "com_semantic_contract_version", "com_auto_creation_policy_result", "extraction_rationale", "extraction_confidence", "type_confidence", "source_identification_confidence", "uncertainty")) {
    if (-not $item.PSObject.Properties.Name.Contains($field) -or $null -eq $item.$field -or [string]::IsNullOrWhiteSpace([string]$item.$field)) {
      Add-Issue $issues "Proposed Work Item missing required extraction field: $field."
    }
  }

  if ($ids.ContainsKey($item.com_council_work_item_id)) {
    Add-Issue $issues "Duplicate proposed Work Item ID: $($item.com_council_work_item_id)."
  } else {
    $ids[$item.com_council_work_item_id] = $true
  }

  if ($item.com_council_work_item_id -notmatch "^CWI-") {
    Add-Issue $issues "Proposed Work Item ID must use Council-level CWI-* identity: $($item.com_council_work_item_id)."
  }
  if ($item.com_council_work_item_id -match "mock-outlook|manual:|crm|dataverse|graph:") {
    Add-Issue $issues "Proposed Work Item ID must not be a source, Graph, or Dataverse row ID: $($item.com_council_work_item_id)."
  }
  if ($item.com_state_group -ne "proposed") {
    Add-Issue $issues "Story 1.3 proposed Work Items must start in proposed state."
  }
  if ($workItemTypes -notcontains $item.com_type) {
    Add-Issue $issues "Invalid Work Item type: $($item.com_type)."
  }
  if ($riskClasses -notcontains $item.com_risk_class) {
    Add-Issue $issues "Invalid risk class: $($item.com_risk_class)."
  }
  if ($knownSourceIds -notcontains $item.com_primary_source_record) {
    Add-Issue $issues "Primary source record does not match a known local Source Record sample: $($item.com_primary_source_record)."
  }
  if ([decimal]$item.extraction_confidence -lt 0 -or [decimal]$item.extraction_confidence -gt 1) {
    Add-Issue $issues "Extraction confidence must be between 0 and 1 for $($item.com_council_work_item_id)."
  }
  if ([decimal]$item.type_confidence -lt 0 -or [decimal]$item.type_confidence -gt 1) {
    Add-Issue $issues "Type confidence must be between 0 and 1 for $($item.com_council_work_item_id)."
  }
  if ([decimal]$item.source_identification_confidence -lt 0 -or [decimal]$item.source_identification_confidence -gt 1) {
    Add-Issue $issues "Source identification confidence must be between 0 and 1 for $($item.com_council_work_item_id)."
  }
  if ($item.com_auto_creation_policy_result -ne "proposal_only" -and $item.com_auto_creation_policy_result -ne "not_evaluated") {
    Add-Issue $issues "Story 1.3 must stop at proposal_only or not_evaluated, not auto-create executable work."
  }
  if ($item.com_approval_required -ne $true) {
    Add-Issue $issues "Story 1.3 examples must require approval before execution."
  }
  if ($item.PSObject.Properties.Name -contains "receipt" -or $item.PSObject.Properties.Name -contains "created_receipt" -or $item.PSObject.Properties.Name -contains "com_created_receipt") {
    Add-Issue $issues "Story 1.3 must not create receipts; that belongs to later stories."
  }
}

$links = @($extraction.extractionRun.workItemSourceLinks)
if ($links.Count -lt $proposedItems.Count) {
  Add-Issue $issues "Extraction slice must include Work Item Source links for each proposed item."
}

foreach ($link in $links) {
  if (-not $ids.ContainsKey($link.com_work_item)) {
    Add-Issue $issues "Work Item Source link references unknown Work Item: $($link.com_work_item)."
  }
  if ($knownSourceIds -notcontains $link.com_source_record) {
    Add-Issue $issues "Work Item Source link references unknown Source Record: $($link.com_source_record)."
  }
  if (@("primary", "supporting", "contradicting", "superseding") -notcontains $link.com_source_role) {
    Add-Issue $issues "Work Item Source link has invalid source role: $($link.com_source_role)."
  }
  if (-not $link.com_rationale) {
    Add-Issue $issues "Work Item Source link must include rationale."
  }
}

foreach ($criterion in @(1, 2)) {
  $mapping = @($extraction.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
  if (-not $mapping) {
    Add-Issue $issues "Missing acceptance mapping for AC $criterion."
  }
}

if ($issues.Count -gt 0) {
  Write-Host "Proposed Work Item extraction slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Proposed Work Item extraction slice validation succeeded."
Write-Host "Proposed Work Items: $($proposedItems.Count)"
Write-Host "Work Item Source links: $($links.Count)"
Write-Host "PROPOSED_WORK_ITEM_EXTRACTION_SLICE_VALIDATE_OK"
