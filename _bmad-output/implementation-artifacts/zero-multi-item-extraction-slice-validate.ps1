param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$ExtractionPath = "$PSScriptRoot\zero-multi-item-extraction-slice.json",
  [string]$ManualSlicePath = "$PSScriptRoot\manual-source-record-slice.json",
  [string]$OutlookSlicePath = "$PSScriptRoot\outlook-source-reference-slice.json",
  [string]$Story13ExtractionPath = "$PSScriptRoot\proposed-work-item-extraction-slice.json"
)

$ErrorActionPreference = "Stop"

function Add-Issue {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $Issues.Add($Message) | Out-Null
}

function Get-ChoiceValues {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)][string]$ChoiceName
  )

  $choice = @($Manifest.choices) | Where-Object { $_.name -eq $ChoiceName } | Select-Object -First 1
  @($choice.values | Where-Object { $null -ne $_ })
}

function Get-ColumnChoiceValues {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)][string]$TableSchemaName,
    [Parameter(Mandatory = $true)][string]$ColumnName
  )

  $table = @($Manifest.tables) | Where-Object { $_.schemaName -eq $TableSchemaName } | Select-Object -First 1
  $column = @($table.columns) | Where-Object { $_.name -eq $ColumnName } | Select-Object -First 1
  @($column.values | Where-Object { $null -ne $_ })
}

function Test-HasNonEmptyField {
  param(
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$Field
  )

  if (-not $Record.PSObject.Properties.Name.Contains($Field)) {
    return $false
  }
  if ($null -eq $Record.$Field -or [string]::IsNullOrWhiteSpace([string]$Record.$Field)) {
    return $false
  }
  return $true
}

function Test-ConfidenceInRange {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$Field,
    [Parameter(Mandatory = $true)][string]$Subject
  )

  if (-not (Test-HasNonEmptyField -Record $Record -Field $Field)) {
    Add-Issue $Issues "$Subject must carry a non-empty ${Field}."
    return
  }
  $parsed = [decimal]0
  if (-not [decimal]::TryParse([string]$Record.$Field, [System.Globalization.NumberStyles]::Number, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
    Add-Issue $Issues "$Subject ${Field} must be numeric, found: $($Record.$Field)."
    return
  }
  if ($parsed -lt 0 -or $parsed -gt 1) {
    Add-Issue $Issues "$Subject ${Field} must be between 0 and 1, found: $parsed."
  }
}

function Test-NoReceiptFields {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$Subject
  )

  foreach ($receiptField in @("receipt", "created_receipt", "com_created_receipt", "com_receipt", "com_receipt_id")) {
    if ($Record.PSObject.Properties.Name -contains $receiptField) {
      Add-Issue $Issues "$Subject must not carry receipt field '$receiptField'; Story 1.4 creates no receipts."
    }
  }
}

function Read-JsonInput {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  try {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  }
  catch {
    Write-Host "Zero/multi-item extraction slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

foreach ($path in @($ManifestPath, $ExtractionPath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required zero/multi-item extraction validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$extraction = Read-JsonInput -Path $ExtractionPath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$issues = [System.Collections.Generic.List[string]]::new()

$extractionStatuses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_extractionstatus"
$workItemTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemtype"
$riskClasses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_riskclass"
$sourceSystems = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_sourcesystem"
$sourceKinds = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_sourcekind"
$dataBoundaryPolicies = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_databoundarypolicy"
$urgencyValues = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilworkitem" -ColumnName "com_urgency"

foreach ($vocabulary in @(
    @{ Name = "com_extractionstatus"; Values = $extractionStatuses },
    @{ Name = "com_workitemtype"; Values = $workItemTypes },
    @{ Name = "com_riskclass"; Values = $riskClasses },
    @{ Name = "com_sourcesystem"; Values = $sourceSystems },
    @{ Name = "com_sourcekind"; Values = $sourceKinds },
    @{ Name = "com_databoundarypolicy"; Values = $dataBoundaryPolicies },
    @{ Name = "com_councilworkitem.com_urgency"; Values = $urgencyValues }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

foreach ($status in @("ignored", "held")) {
  if ($extractionStatuses -notcontains $status) {
    Add-Issue $issues "Manifest com_extractionstatus is missing zero-item outcome status: $status."
  }
}

if ($extraction.storyKey -ne "1-4-handle-zero-item-and-multi-item-extraction") {
  Add-Issue $issues "Extraction slice storyKey must be 1-4-handle-zero-item-and-multi-item-extraction."
}

foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "noReceiptCreationInThisSlice", "requiresExplicitHumanApprovalForExecution", "sourceRecordsRemainSeparate", "noWorkItemCreatedForZeroItemSources")) {
  if (-not ($extraction.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Extraction slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($extraction.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Extraction guard must be boolean true: $($guardProperty.Name)."
  }
}

if ($extraction.extractionRun.inputSourceRecordsFrom -notcontains "manual-source-record-slice.json") {
  Add-Issue $issues "Extraction run must reference manual-source-record-slice.json as an input."
}
if ($extraction.extractionRun.inputSourceRecordsFrom -notcontains "outlook-source-reference-slice.json") {
  Add-Issue $issues "Extraction run must reference outlook-source-reference-slice.json as an input."
}
if ($extraction.extractionRun.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Extraction run semanticContractVersion must be 2026-07-07."
}
if (-not (Test-HasNonEmptyField -Record $extraction.extractionRun -Field "runId")) {
  Add-Issue $issues "Extraction run must declare a runId."
}
Test-NoReceiptFields -Issues $issues -Record $extraction.extractionRun -Subject "Extraction run"

$knownSourceIds = @()
$knownSourceIds += @($manualSlice.manualCapture.sampleRecords | ForEach-Object { $_.com_council_source_record_id })
$knownSourceIds += @($outlookSlice.outlookCapture.sampleRecords | ForEach-Object { $_.com_council_source_record_id })
$story13WorkItemIds = @($story13Extraction.extractionRun.proposedWorkItems | ForEach-Object { $_.com_council_work_item_id })
$story13ExtractedSourceIds = @($story13Extraction.extractionRun.proposedWorkItems | ForEach-Object { $_.com_primary_source_record })

if (@($knownSourceIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be loaded from the Story 1.1/1.2 slices; cross-slice checks would silently no-op."
}
if (@($story13WorkItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) {
  Add-Issue $issues "No Work Item IDs could be loaded from the Story 1.3 slice; cross-slice checks would silently no-op."
}

$embeddedSources = @($extraction.extractionRun.embeddedSampleSourceRecords | Where-Object { $null -ne $_ })
$embeddedSourceIds = @($embeddedSources | ForEach-Object { $_.com_council_source_record_id })
$requiredSourceFields = @(
  "com_name",
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

if ($embeddedSourceIds -notcontains "CSR-MANUAL-MEETING-001") {
  Add-Issue $issues "Extraction slice must embed the multi-item sample source CSR-MANUAL-MEETING-001."
}

$seenEmbeddedSourceIds = @{}
foreach ($source in $embeddedSources) {
  foreach ($field in $requiredSourceFields) {
    if (-not (Test-HasNonEmptyField -Record $source -Field $field)) {
      Add-Issue $issues "Embedded sample Source Record missing required field: $field."
    }
  }

  if (Test-HasNonEmptyField -Record $source -Field "com_captured_at") {
    $capturedAt = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$source.com_captured_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$capturedAt)) {
      Add-Issue $issues "Embedded sample Source Record com_captured_at must be an ISO 8601 timestamp, found: $($source.com_captured_at)."
    }
  }

  $sourceId = [string]$source.com_council_source_record_id
  if (-not [string]::IsNullOrWhiteSpace($sourceId)) {
    if ($seenEmbeddedSourceIds.ContainsKey($sourceId)) {
      Add-Issue $issues "Duplicate embedded sample Source Record ID: $sourceId."
    } else {
      $seenEmbeddedSourceIds[$sourceId] = $true
    }
    if ($knownSourceIds -contains $sourceId) {
      Add-Issue $issues "Embedded sample Source Record ID collides with a Story 1.1/1.2 sample Source Record: $sourceId."
    }
  }

  if ($sourceId -notmatch "^CSR-") {
    Add-Issue $issues "Embedded sample Source Record ID must use Council-level CSR-* identity: $sourceId."
  }
  if ($sourceSystems -notcontains $source.com_source_system) {
    Add-Issue $issues "Embedded sample Source Record has invalid source system: $($source.com_source_system)."
  }
  if ($sourceKinds -notcontains $source.com_source_kind) {
    Add-Issue $issues "Embedded sample Source Record has invalid source kind: $($source.com_source_kind)."
  }
  if ($dataBoundaryPolicies -notcontains $source.com_data_boundary_policy) {
    Add-Issue $issues "Embedded sample Source Record has invalid data boundary policy: $($source.com_data_boundary_policy)."
  }
  if ($extractionStatuses -notcontains $source.com_extraction_status) {
    Add-Issue $issues "Embedded sample Source Record has invalid extraction status: $($source.com_extraction_status)."
  }
  if ($sourceId -eq "CSR-MANUAL-MEETING-001") {
    if ($source.com_data_boundary_policy -ne "summary_allowed") {
      Add-Issue $issues "Multi-item sample source must use data boundary policy summary_allowed."
    }
    if ($source.com_extraction_status -ne "new") {
      Add-Issue $issues "Multi-item sample source must start with extraction status new."
    }
    if (-not (Test-HasNonEmptyField -Record $source -Field "com_content_snapshot_ref")) {
      Add-Issue $issues "Multi-item sample source must carry a content snapshot reference."
    }
    if ($source.com_source_to_work_item_rationale -notmatch "\(1\)" -or $source.com_source_to_work_item_rationale -notmatch "\(2\)" -or $source.com_source_to_work_item_rationale -notmatch "\(3\)") {
      Add-Issue $issues "Multi-item sample source rationale must state its three distinct commitments."
    }
  }
}

$allSourceIds = @($knownSourceIds + $embeddedSourceIds)

$sourcePolicyById = @{}
foreach ($record in @(@($manualSlice.manualCapture.sampleRecords) + @($outlookSlice.outlookCapture.sampleRecords) + $embeddedSources | Where-Object { $null -ne $_ })) {
  $recordId = [string]$record.com_council_source_record_id
  if (-not [string]::IsNullOrWhiteSpace($recordId) -and -not $sourcePolicyById.ContainsKey($recordId)) {
    $sourcePolicyById[$recordId] = [string]$record.com_data_boundary_policy
  }
}

$zeroItemOutcomes = @($extraction.extractionRun.zeroItemOutcomes | Where-Object { $null -ne $_ })
if ($zeroItemOutcomes.Count -lt 2) {
  Add-Issue $issues "Extraction slice must include at least two zero-item outcomes."
}

$expectedZeroItemOutcomes = @{
  "CSR-MANUAL-LINK-001"         = "ignored"
  "CSR-OUTLOOK-THREAD-MOCK-001" = "held"
}
foreach ($expectedSource in $expectedZeroItemOutcomes.Keys) {
  $outcome = $zeroItemOutcomes | Where-Object { $_.sourceRecord -eq $expectedSource } | Select-Object -First 1
  if (-not $outcome) {
    Add-Issue $issues "Missing zero-item outcome for $expectedSource."
  }
  elseif ($outcome.com_extraction_status -ne $expectedZeroItemOutcomes[$expectedSource]) {
    Add-Issue $issues "Zero-item outcome for $expectedSource must be $($expectedZeroItemOutcomes[$expectedSource]), found: $($outcome.com_extraction_status)."
  }
}

$zeroItemSourceIds = @()
$seenZeroItemSourceIds = @{}
foreach ($outcome in $zeroItemOutcomes) {
  $outcomeSourceId = [string]$outcome.sourceRecord
  $zeroItemSourceIds += $outcomeSourceId

  if ([string]::IsNullOrWhiteSpace($outcomeSourceId)) {
    Add-Issue $issues "Zero-item outcome must name its sourceRecord."
  }
  else {
    if ($seenZeroItemSourceIds.ContainsKey($outcomeSourceId)) {
      Add-Issue $issues "Duplicate zero-item outcome for Source Record: $outcomeSourceId."
    } else {
      $seenZeroItemSourceIds[$outcomeSourceId] = $true
    }
    if ($knownSourceIds -notcontains $outcomeSourceId) {
      Add-Issue $issues "Zero-item outcome references an unknown Source Record: $outcomeSourceId."
    }
    if ($story13ExtractedSourceIds -contains $outcomeSourceId) {
      Add-Issue $issues "Zero-item outcome contradicts Story 1.3, which already extracted a proposed Work Item from: $outcomeSourceId."
    }
  }
  if (@("ignored", "held") -notcontains $outcome.com_extraction_status) {
    Add-Issue $issues "Zero-item outcome status must be ignored or held, found: $($outcome.com_extraction_status) for $outcomeSourceId."
  }
  if ($extractionStatuses -notcontains $outcome.com_extraction_status) {
    Add-Issue $issues "Zero-item outcome status is not in manifest com_extractionstatus: $($outcome.com_extraction_status)."
  }
  if (-not (Test-HasNonEmptyField -Record $outcome -Field "extraction_rationale")) {
    Add-Issue $issues "Zero-item outcome must carry a non-empty extraction_rationale: $outcomeSourceId."
  }
  Test-ConfidenceInRange -Issues $issues -Record $outcome -Field "extraction_confidence" -Subject "Zero-item outcome $outcomeSourceId"
  if ($outcome.workItemCreated -isnot [bool] -or $outcome.workItemCreated) {
    Add-Issue $issues "Zero-item outcome must state workItemCreated=false (boolean): $outcomeSourceId."
  }
  if (-not (Test-HasNonEmptyField -Record $outcome -Field "noWorkItemNote")) {
    Add-Issue $issues "Zero-item outcome must carry a note that no Work Item was created: $outcomeSourceId."
  }
  Test-NoReceiptFields -Issues $issues -Record $outcome -Subject "Zero-item outcome $outcomeSourceId"
}

$proposedItems = @($extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
if ($proposedItems.Count -lt 3) {
  Add-Issue $issues "Extraction slice must include at least three proposed Work Items for the multi-item source."
}

$ids = @{}
foreach ($item in $proposedItems) {
  foreach ($field in @("com_council_work_item_id", "com_title", "com_type", "com_summary", "com_state_group", "com_owner_candidate", "com_urgency", "com_risk_class", "com_confidence_summary", "com_primary_source_record", "com_rationale", "com_recommended_next_action", "com_approval_required", "com_semantic_contract_version", "com_auto_creation_policy_result", "com_policy_flags", "extraction_rationale", "extraction_confidence", "type_confidence", "source_identification_confidence", "uncertainty")) {
    if (-not (Test-HasNonEmptyField -Record $item -Field $field)) {
      Add-Issue $issues "Proposed Work Item missing required extraction field: $field."
    }
  }

  $itemId = [string]$item.com_council_work_item_id
  if ([string]::IsNullOrWhiteSpace($itemId)) {
    Add-Issue $issues "Proposed Work Item must declare com_council_work_item_id."
  }
  else {
    if ($ids.ContainsKey($itemId)) {
      Add-Issue $issues "Duplicate proposed Work Item ID: $itemId."
    } else {
      $ids[$itemId] = $true
    }
    if ($story13WorkItemIds -contains $itemId) {
      Add-Issue $issues "Proposed Work Item ID collides with a Story 1.3 Work Item ID: $itemId."
    }
  }

  if ($itemId -notmatch "^CWI-") {
    Add-Issue $issues "Proposed Work Item ID must use Council-level CWI-* identity: $itemId."
  }
  if ($itemId -match "mock-outlook|manual:|crm|dataverse|graph:") {
    Add-Issue $issues "Proposed Work Item ID must not be a source, Graph, or Dataverse row ID: $itemId."
  }
  if ($item.com_state_group -ne "proposed") {
    Add-Issue $issues "Story 1.4 proposed Work Items must start in proposed state."
  }
  if ($workItemTypes -notcontains $item.com_type) {
    Add-Issue $issues "Invalid Work Item type: $($item.com_type)."
  }
  if ($riskClasses -notcontains $item.com_risk_class) {
    Add-Issue $issues "Invalid risk class: $($item.com_risk_class)."
  }
  if ($urgencyValues.Count -gt 0 -and $urgencyValues -notcontains $item.com_urgency) {
    Add-Issue $issues "Invalid urgency: $($item.com_urgency) for $itemId."
  }
  if ($allSourceIds -notcontains $item.com_primary_source_record) {
    Add-Issue $issues "Primary source record does not match a known or embedded local Source Record sample: $($item.com_primary_source_record)."
  }
  if ($zeroItemSourceIds -contains $item.com_primary_source_record) {
    Add-Issue $issues "Proposed Work Item $itemId references zero-item source $($item.com_primary_source_record); zero-item sources must have zero proposed Work Items."
  }
  $primarySourceId = [string]$item.com_primary_source_record
  if ($sourcePolicyById.ContainsKey($primarySourceId) -and $sourcePolicyById[$primarySourceId] -eq "unknown") {
    Add-Issue $issues "Proposed Work Item $itemId extracts from a source whose data boundary policy is unknown; extraction is blocked until the policy is resolved or a link-only/hash-only fallback is recorded."
  }
  if ($item.com_semantic_contract_version -ne "2026-07-07") {
    Add-Issue $issues "Proposed Work Item semantic contract version must be 2026-07-07: $itemId."
  }
  Test-ConfidenceInRange -Issues $issues -Record $item -Field "extraction_confidence" -Subject "Proposed Work Item $itemId"
  Test-ConfidenceInRange -Issues $issues -Record $item -Field "type_confidence" -Subject "Proposed Work Item $itemId"
  Test-ConfidenceInRange -Issues $issues -Record $item -Field "source_identification_confidence" -Subject "Proposed Work Item $itemId"
  Test-ConfidenceInRange -Issues $issues -Record $item -Field "com_owner_candidate_confidence" -Subject "Proposed Work Item $itemId"
  if ($item.com_auto_creation_policy_result -ne "proposal_only" -and $item.com_auto_creation_policy_result -ne "not_evaluated") {
    Add-Issue $issues "Story 1.4 must stop at proposal_only or not_evaluated, not auto-create executable work."
  }
  if ($item.com_approval_required -isnot [bool] -or -not $item.com_approval_required) {
    Add-Issue $issues "Story 1.4 examples must require approval before execution (boolean true)."
  }
  Test-NoReceiptFields -Issues $issues -Record $item -Subject "Proposed Work Item $itemId"
}

$multiItemSourceItems = @($proposedItems | Where-Object { $_.com_primary_source_record -eq "CSR-MANUAL-MEETING-001" })
if ($multiItemSourceItems.Count -lt 3) {
  Add-Issue $issues "Multi-item source CSR-MANUAL-MEETING-001 must yield at least three proposed Work Items, found $($multiItemSourceItems.Count)."
}
$distinctMultiItemTypes = @($multiItemSourceItems | ForEach-Object { $_.com_type } | Sort-Object -Unique)
if ($distinctMultiItemTypes.Count -lt 2) {
  Add-Issue $issues "Multi-item source Work Items must span at least two distinct types, found $($distinctMultiItemTypes.Count)."
}
$distinctMultiItemRationales = @($multiItemSourceItems | ForEach-Object { [string]$_.extraction_rationale } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
if ($multiItemSourceItems.Count -gt 0 -and $distinctMultiItemRationales.Count -lt $multiItemSourceItems.Count) {
  Add-Issue $issues "Each multi-item Work Item must carry its own distinct extraction_rationale; found $($distinctMultiItemRationales.Count) distinct rationale(s) across $($multiItemSourceItems.Count) items."
}

$links = @($extraction.extractionRun.workItemSourceLinks | Where-Object { $null -ne $_ })
foreach ($link in $links) {
  $linkWorkItemId = [string]$link.com_work_item
  if ([string]::IsNullOrWhiteSpace($linkWorkItemId) -or -not $ids.ContainsKey($linkWorkItemId)) {
    Add-Issue $issues "Work Item Source link references unknown Work Item: $linkWorkItemId."
  }
  if ($allSourceIds -notcontains $link.com_source_record) {
    Add-Issue $issues "Work Item Source link references unknown Source Record: $($link.com_source_record)."
  }
  if ($zeroItemSourceIds -contains $link.com_source_record) {
    Add-Issue $issues "Work Item Source link references zero-item source $($link.com_source_record); zero-item sources must have zero proposed Work Items."
  }
  if (@("primary", "supporting", "contradicting", "superseding") -notcontains $link.com_source_role) {
    Add-Issue $issues "Work Item Source link has invalid source role: $($link.com_source_role)."
  }
  if (-not (Test-HasNonEmptyField -Record $link -Field "com_rationale")) {
    Add-Issue $issues "Work Item Source link must include rationale: $($link.com_name)."
  }
  Test-ConfidenceInRange -Issues $issues -Record $link -Field "com_confidence" -Subject "Work Item Source link $($link.com_name)"
  Test-NoReceiptFields -Issues $issues -Record $link -Subject "Work Item Source link $($link.com_name)"
}

foreach ($item in $proposedItems) {
  $primaryLinks = @($links | Where-Object { $_.com_work_item -eq $item.com_council_work_item_id -and $_.com_source_role -eq "primary" })
  if ($primaryLinks.Count -ne 1) {
    Add-Issue $issues "Proposed Work Item $($item.com_council_work_item_id) must have exactly one primary Work Item Source link, found $($primaryLinks.Count)."
  }
  elseif ($primaryLinks[0].com_source_record -ne $item.com_primary_source_record) {
    Add-Issue $issues "Primary Work Item Source link for $($item.com_council_work_item_id) must match its com_primary_source_record."
  }
}

$deferredUpdates = @($extraction.extractionRun.sourceUpdatesDeferred | Where-Object { $null -ne $_ })
$extractedFromSourceIds = @($proposedItems | ForEach-Object { [string]$_.com_primary_source_record } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
foreach ($sourceId in @(@($zeroItemSourceIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) + $extractedFromSourceIds + @("CSR-MANUAL-MEETING-001") | Sort-Object -Unique)) {
  $deferred = $deferredUpdates | Where-Object { $_.sourceRecord -eq $sourceId } | Select-Object -First 1
  if (-not $deferred -or -not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Missing deferred extraction-status update entry for $sourceId."
  }
}

foreach ($criterion in @(1, 2)) {
  $mapping = @($extraction.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
  if (-not $mapping) {
    Add-Issue $issues "Missing acceptance mapping for AC $criterion."
  }
  else {
    if (@($mapping.localEvidence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -lt 1) {
      Add-Issue $issues "Acceptance mapping for AC $criterion must list non-empty localEvidence."
    }
    if (-not (Test-HasNonEmptyField -Record $mapping -Field "tenantEvidenceRequired")) {
      Add-Issue $issues "Acceptance mapping for AC $criterion must state tenantEvidenceRequired."
    }
  }
}

if ($issues.Count -gt 0) {
  Write-Host "Zero/multi-item extraction slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Zero/multi-item extraction slice validation succeeded."
Write-Host "Zero-item outcomes: $($zeroItemOutcomes.Count)"
Write-Host "Proposed Work Items: $($proposedItems.Count)"
Write-Host "Distinct multi-item types: $($distinctMultiItemTypes.Count)"
Write-Host "Work Item Source links: $($links.Count)"
Write-Host "ZERO_MULTI_ITEM_EXTRACTION_SLICE_VALIDATE_OK"
