param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$FailureSlicePath = "$PSScriptRoot\failure-policy-denial-slice.json",
  [string]$ManualSlicePath = "$PSScriptRoot\manual-source-record-slice.json",
  [string]$OutlookSlicePath = "$PSScriptRoot\outlook-source-reference-slice.json",
  [string]$Story13ExtractionPath = "$PSScriptRoot\proposed-work-item-extraction-slice.json",
  [string]$Story14ExtractionPath = "$PSScriptRoot\zero-multi-item-extraction-slice.json",
  [string]$DemoEvidencePath = "$PSScriptRoot\state-transition-demo-evidence.json"
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

  if (@($Record.PSObject.Properties.Name) -notcontains $Field) {
    return $false
  }
  if ($null -eq $Record.$Field -or [string]::IsNullOrWhiteSpace([string]$Record.$Field)) {
    return $false
  }
  return $true
}

function Test-StrictBooleanTrue {
  param($Value)

  ($Value -is [bool]) -and $Value
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

function Test-IsoTimestamp {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$Field,
    [Parameter(Mandatory = $true)][string]$Subject
  )

  if (-not (Test-HasNonEmptyField -Record $Record -Field $Field)) {
    Add-Issue $Issues "$Subject must carry a non-empty ${Field}."
    return $null
  }
  $rawValue = $Record.$Field
  if ($rawValue -is [datetime]) {
    if ($rawValue.Kind -eq [System.DateTimeKind]::Unspecified) {
      Add-Issue $Issues "$Subject ${Field} must be ISO 8601 with an explicit UTC offset, found: $rawValue."
      return $null
    }
    return [datetimeoffset]$rawValue
  }
  $parsed = [datetimeoffset]::MinValue
  if (-not [datetimeoffset]::TryParse([string]$rawValue, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
    Add-Issue $Issues "$Subject ${Field} must be an ISO 8601 timestamp, found: $rawValue."
    return $null
  }
  if ([string]$rawValue -notmatch "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$") {
    Add-Issue $Issues "$Subject ${Field} must be ISO 8601 with an explicit UTC offset, found: $rawValue."
    return $null
  }
  return $parsed
}

function Read-JsonInput {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  try {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  }
  catch {
    Write-Host "Failure and policy denial slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

function Split-EvidenceRefs {
  param([Parameter(Mandatory = $true)][string]$Raw)

  @(([string]$Raw) -split "[;\r\n]" | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

foreach ($path in @($ManifestPath, $FailureSlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required failure and policy denial validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$failure = Read-JsonInput -Path $FailureSlicePath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath
$issues = [System.Collections.Generic.List[string]]::new()

$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$workItemStateGroups = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemstategroup"
$authorityClasses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_authorityclass"
$evidenceRoles = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilreceiptsource" -ColumnName "com_evidence_role"

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_workitemstategroup"; Values = $workItemStateGroups },
    @{ Name = "com_authorityclass"; Values = $authorityClasses },
    @{ Name = "com_councilreceiptsource.com_evidence_role"; Values = $evidenceRoles }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

foreach ($requiredVerb in @("failed", "policy_denied")) {
  if ($receiptVerbs -notcontains $requiredVerb) {
    Add-Issue $issues "Manifest com_receiptverb is missing the Story 2.6 verb: $requiredVerb."
  }
}
foreach ($requiredResult in @("failed", "rejected")) {
  if ($receiptResults -notcontains $requiredResult) {
    Add-Issue $issues "Manifest com_receiptresult is missing the Story 2.6 result: $requiredResult."
  }
}
foreach ($requiredState in @("proposed", "in_review", "blocked", "held")) {
  if ($workItemStateGroups -notcontains $requiredState) {
    Add-Issue $issues "Manifest com_workitemstategroup is missing a reviewable state group required by Story 2.6: $requiredState."
  }
}
if ($evidenceRoles -notcontains "failure_evidence") {
  Add-Issue $issues "Manifest com_councilreceiptsource.com_evidence_role is missing: failure_evidence."
}

# Reviewable state groups: any non-terminal state from which a Work Item can still be acted on.
# Approved/completed are treated as terminal-for-this-check; failed is reviewable (manifest "Failed Needs Review" view).
$reviewableStateGroups = @("proposed", "in_review", "blocked", "held", "failed")

if ($failure.storyKey -ne "2-6-record-failures-and-policy-denials") {
  Add-Issue $issues "Failure slice storyKey must be 2-6-record-failures-and-policy-denials."
}
if ([string]$failure.status -notmatch "^local-contract") {
  Add-Issue $issues "Failure slice status must declare local contract evidence, found: $($failure.status)."
}

foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "requiresExplicitHumanApprovalForExecution", "sourceRecordsRemainSeparate", "meaningGraphDoesNotOwnWorkflowState", "dataverseRowsNotUsedAsCouncilIdentity", "receiptsAreLocalContractEvidenceOnly", "failuresAreRecordedNotSilent", "policyDenialsKeepAffectedWorkItemReviewable", "receiptsAreAppendOnlyCorrectionsAreNewReceipts", "noWorkItemStateChangeInThisSlice")) {
  if (-not ($failure.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Failure slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($failure.guards.PSObject.Properties)) {
  if (-not (Test-StrictBooleanTrue $guardProperty.Value)) {
    Add-Issue $issues "Failure guard must be boolean true: $($guardProperty.Name)."
  }
}

# Cross-slice ID loading: prior source records, prior work items, and reserved demo receipt ids.
$manualSources = @($manualSlice.manualCapture.sampleRecords | Where-Object { $null -ne $_ })
$outlookSources = @($outlookSlice.outlookCapture.sampleRecords | Where-Object { $null -ne $_ })
$story14EmbeddedSources = @($story14Extraction.extractionRun.embeddedSampleSourceRecords | Where-Object { $null -ne $_ })
$priorSourcesById = @{}
foreach ($record in @($manualSources + $outlookSources + $story14EmbeddedSources)) {
  $recordId = [string]$record.com_council_source_record_id
  if ([string]::IsNullOrWhiteSpace($recordId)) {
    continue
  }
  if (-not $priorSourcesById.ContainsKey($recordId)) {
    $priorSourcesById[$recordId] = $record
  }
  elseif ((ConvertTo-Json $record -Depth 10 -Compress) -ne (ConvertTo-Json $priorSourcesById[$recordId] -Depth 10 -Compress)) {
    Add-Issue $issues "Divergent duplicate prior Source Record across sibling slices: $recordId; cross-slice checks would silently run against an arbitrary copy."
  }
}
$knownPriorSourceIds = @($priorSourcesById.Keys)

$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$knownWorkItems = @($story13Items + $story14Items)
$knownWorkItemsById = @{}
foreach ($item in $knownWorkItems) {
  $itemId = [string]$item.com_council_work_item_id
  if ([string]::IsNullOrWhiteSpace($itemId)) {
    continue
  }
  if (-not $knownWorkItemsById.ContainsKey($itemId)) {
    $knownWorkItemsById[$itemId] = $item
  }
  elseif ((ConvertTo-Json $item -Depth 10 -Compress) -ne (ConvertTo-Json $knownWorkItemsById[$itemId] -Depth 10 -Compress)) {
    Add-Issue $issues "Divergent duplicate prior Work Item across sibling slices: $itemId; cross-slice checks would silently run against an arbitrary copy."
  }
}
$knownWorkItemIds = @($knownWorkItemsById.Keys)

# Prior slice receipt ids that our new CR-LOCAL-FAILURE-* ids must not collide with.
$priorReceiptIds = @{}
$driftSlicePath = Join-Path $PSScriptRoot "source-drift-supersession-slice.json"
if (Test-Path -LiteralPath $driftSlicePath) {
  $driftSlice = Read-JsonInput -Path $driftSlicePath
  foreach ($r in @($driftSlice.driftRun.receipts | Where-Object { $null -ne $_ })) {
    $rid = [string]$r.com_receipt_id
    if (-not [string]::IsNullOrWhiteSpace($rid)) {
      $priorReceiptIds[$rid] = "source-drift-supersession-slice.json"
    }
  }
}
else {
  Add-Issue $issues "Sibling slice source-drift-supersession-slice.json not found; cross-slice receipt collision checks would silently no-op."
}
$demoReceiptIds = @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
foreach ($rid in $demoReceiptIds) {
  $priorReceiptIds[[string]$rid] = "state-transition-demo-evidence.json"
}

foreach ($sliceLoad in @(
    @{ Name = "manual-source-record-slice sampleRecords"; Count = $manualSources.Count },
    @{ Name = "outlook-source-reference-slice sampleRecords"; Count = $outlookSources.Count },
    @{ Name = "zero-multi-item-extraction-slice embeddedSampleSourceRecords"; Count = $story14EmbeddedSources.Count },
    @{ Name = "proposed-work-item-extraction-slice proposedWorkItems"; Count = $story13Items.Count },
    @{ Name = "zero-multi-item-extraction-slice proposedWorkItems"; Count = $story14Items.Count }
  )) {
  if ($sliceLoad.Count -eq 0) {
    Add-Issue $issues "No records loaded from $($sliceLoad.Name); its cross-slice checks would silently no-op."
  }
}
if ($knownPriorSourceIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be loaded from the Story 1.1/1.2/1.4 slices; evidence-ref resolution would silently no-op."
}
if ($knownWorkItemIds.Count -eq 0) {
  Add-Issue $issues "No Work Item IDs could be loaded from the Story 1.3/1.4 slices; affected-work-item checks would silently no-op."
}
if ($priorReceiptIds.Count -eq 0) {
  Add-Issue $issues "No reserved receipt IDs could be loaded from sibling slices; receipt collision checks would silently no-op."
}

$run = $failure.failureRun
if ($null -eq $run) {
  Add-Issue $issues "Failure slice must carry a failureRun block."
  Write-Host "Failure and policy denial slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Failure run must declare a runId."
}
elseif (@([string]$story13Extraction.extractionRun.runId, [string]$story14Extraction.runId, [string]$driftSlice.driftRun.runId) -contains [string]$run.runId) {
  Add-Issue $issues "Failure run must use a new local runId, not a sibling slice runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Failure run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Failure run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Failure run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "proposed-work-item-extraction-slice.json", "zero-multi-item-extraction-slice.json")) {
  if (@($run.inputSlicesFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Failure run must reference $inputSlice as an input."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Failure run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("failuresAppendReceiptsNeverEditPriorReceipts", "systemErrorsMayBeRetriedUnderANewReceipt", "policyDenialsAreNonRetryableWithoutPolicyChange", "humanReviewFailuresHoldUntilReviewed", "affectedWorkItemsStayReviewableUntilCleared", "liveWorkItemStateChangeReceiptGatedToStory23")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Failure run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if (-not (Test-StrictBooleanTrue $policyProperty.Value)) {
      Add-Issue $issues "Failure run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# Failure code vocabulary: declared as a Story 2.6 local extension of the manifest free-text com_failure_code column.
$failureCodeVocab = $run.failureCodeVocabulary
$declaredFailureCodes = @{}
$declaredCodeKinds = @{}
if ($null -eq $failureCodeVocab) {
  Add-Issue $issues "Failure run must declare a failureCodeVocabulary block."
}
else {
  if (-not (Test-HasNonEmptyField -Record $failureCodeVocab -Field "basis")) {
    Add-Issue $issues "failureCodeVocabulary must carry a non-empty basis explaining the manifest extension."
  }
  elseif (([string]$failureCodeVocab.basis) -notmatch "extension|free-text|no enumerated|local extension") {
    Add-Issue $issues "failureCodeVocabulary.basis must state that the codes extend the manifest's free-text com_failure_code column."
  }
  $codes = @($failureCodeVocab.codes | Where-Object { $null -ne $_ })
  if ($codes.Count -lt 3) {
    Add-Issue $issues "failureCodeVocabulary must declare at least three failure codes (system_error, policy_denial, human_review), found $($codes.Count)."
  }
  $validKinds = @("system_error", "policy_denial", "human_review")
  foreach ($code in $codes) {
    $codeValue = [string]$code.code
    if ([string]::IsNullOrWhiteSpace($codeValue)) {
      Add-Issue $issues "failureCodeVocabulary entry must declare a non-empty code."
      continue
    }
    if ($declaredFailureCodes.ContainsKey($codeValue)) {
      Add-Issue $issues "Duplicate failure code declared in failureCodeVocabulary: $codeValue."
    }
    else {
      $declaredFailureCodes[$codeValue] = $code
    }
    $subject = "Failure code $codeValue"
    if (-not (Test-HasNonEmptyField -Record $code -Field "definition")) {
      Add-Issue $issues "$subject must carry a non-empty definition."
    }
    if ($validKinds -notcontains [string]$code.kind) {
      Add-Issue $issues "$subject kind must be one of system_error, policy_denial, human_review, found: $($code.kind)."
    }
    else {
      $declaredCodeKinds[[string]$code.kind] = $codeValue
    }
    if (-not (Test-HasNonEmptyField -Record $code -Field "retryAllowed") -or -not (Test-StrictBooleanTrue $code.retryAllowed) -and ($code.retryAllowed -isnot [bool])) {
      Add-Issue $issues "$subject retryAllowed must be a strict boolean."
    }
    elseif ($code.retryAllowed -isnot [bool]) {
      Add-Issue $issues "$subject retryAllowed must be a strict boolean, found: $($code.retryAllowed)."
    }
    if ($code.humanReviewRequired -isnot [bool]) {
      Add-Issue $issues "$subject humanReviewRequired must be a strict boolean, found: $($code.humanReviewRequired)."
    }
  }
  foreach ($requiredKind in @("system_error", "policy_denial", "human_review")) {
    if (-not $declaredCodeKinds.ContainsKey($requiredKind)) {
      Add-Issue $issues "failureCodeVocabulary must declare a code of kind $requiredKind."
    }
  }
}

$receipts = @($run.failureReceipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 3) {
  Add-Issue $issues "Failure slice must include at least three failure receipts (system error, policy denial, human review), found $($receipts.Count)."
}

$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
# Manifest-required columns plus the Story 2.6 receipt-contract pins (attempted action, retry, review, state, evidence, rationale, policy flags).
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("attemptedAction", "retryAllowed", "humanReviewRequired", "com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique

$sliceReceiptIds = @{}
$seenIdempotencyKeys = @{}
$receiptByCode = @{}
$receiptByKind = @{}
foreach ($receipt in $receipts) {
  $receiptId = [string]$receipt.com_receipt_id
  $subject = "Receipt $receiptId"

  foreach ($field in $receiptRequiredFields) {
    if (-not (Test-HasNonEmptyField -Record $receipt -Field $field)) {
      Add-Issue $issues "$subject missing required receipt field: $field."
    }
  }

  if ([string]::IsNullOrWhiteSpace($receiptId)) {
    Add-Issue $issues "Receipt must declare com_receipt_id."
  }
  else {
    if ($receiptId -notmatch "^CR-") {
      Add-Issue $issues "$subject must use Council-level CR-* identity."
    }
    if ($sliceReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "Duplicate receipt ID in slice: $receiptId."
    }
    else {
      $sliceReceiptIds[$receiptId] = $true
    }
    if ($priorReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "$subject collides with a reserved receipt ID from $($priorReceiptIds[$receiptId]); new failure receipts must be unique across all slices."
    }
  }

  if ($receiptVerbs -notcontains $receipt.com_verb) {
    Add-Issue $issues "$subject verb is not in manifest com_receiptverb vocabulary: $($receipt.com_verb)."
  }
  elseif ($receipt.com_verb -ne "failed" -and $receipt.com_verb -ne "policy_denied") {
    Add-Issue $issues "$subject must use verb failed or policy_denied for Story 2.6, found: $($receipt.com_verb)."
  }
  if ($actorTypes -notcontains $receipt.com_actor_type) {
    Add-Issue $issues "$subject actor type is not in manifest com_actortype vocabulary: $($receipt.com_actor_type)."
  }
  if ($receiptResults -notcontains $receipt.com_result) {
    Add-Issue $issues "$subject result is not in manifest com_receiptresult vocabulary: $($receipt.com_result)."
  }
  Test-IsoTimestamp -Issues $issues -Record $receipt -Field "com_occurred_at" -Subject $subject | Out-Null

  $idempotencyKey = [string]$receipt.com_idempotency_key
  if ([string]::IsNullOrWhiteSpace($idempotencyKey)) {
    Add-Issue $issues "$subject must carry a non-empty com_idempotency_key."
  }
  elseif ($seenIdempotencyKeys.ContainsKey($idempotencyKey)) {
    Add-Issue $issues "$subject reuses an idempotency key already used in this slice: $idempotencyKey."
  }
  else {
    $seenIdempotencyKeys[$idempotencyKey] = $true
  }

  if (-not (Test-StrictBooleanTrue $receipt.com_append_only_locked)) {
    Add-Issue $issues "$subject com_append_only_locked must be strict boolean true (receipts are append-only)."
  }
  if ($receipt.retryAllowed -isnot [bool]) {
    Add-Issue $issues "$subject retryAllowed must be a strict boolean, found: $($receipt.retryAllowed)."
  }
  if ($receipt.humanReviewRequired -isnot [bool]) {
    Add-Issue $issues "$subject humanReviewRequired must be a strict boolean, found: $($receipt.humanReviewRequired)."
  }
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject

  $failureCode = [string]$receipt.com_failure_code
  if ([string]::IsNullOrWhiteSpace($failureCode)) {
    Add-Issue $issues "$subject must carry a non-empty com_failure_code."
  }
  elseif ($declaredFailureCodes.Count -gt 0 -and -not $declaredFailureCodes.ContainsKey($failureCode)) {
    Add-Issue $issues "$subject com_failure_code '$failureCode' is not declared in failureCodeVocabulary."
  }
  else {
    $receiptByCode[$failureCode] = $receipt
    if ($null -ne $declaredFailureCodes[$failureCode]) {
      $receiptByKind[[string]$declaredFailureCodes[$failureCode].kind] = $receipt
    }
  }

  # No live-write marker fields: this slice is local contract evidence only.
  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 2.6 receipts are local contract evidence only."
    }
  }
  # Append-only tripwire: a receipt that claims to edit/replace a prior receipt would break append-only semantics.
  foreach ($editMarker in @("supersedesPriorReceipt", "replacesReceipt", "editedReceiptId", "correctsReceiptId")) {
    if ($receipt.PSObject.Properties.Name -contains $editMarker) {
      Add-Issue $issues "$subject must not carry edit marker '$editMarker'; corrections are new receipts, never edits."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 2.6 receipts are local contract evidence only."
      }
    }
  }

  # Evidence refs must resolve to a known prior Source Record or Work Item (cross-slice).
  $evidenceRefTokens = Split-EvidenceRefs -Raw ([string]$receipt.com_evidence_refs)
  if ($evidenceRefTokens.Count -eq 0) {
    Add-Issue $issues "$subject com_evidence_refs must name at least one resolvable evidence reference."
  }
  else {
    foreach ($ref in $evidenceRefTokens) {
      if ($knownPriorSourceIds -notcontains $ref -and $knownWorkItemIds -notcontains $ref) {
        Add-Issue $issues "$subject evidence ref '$ref' does not resolve to a known prior Source Record or Work Item."
      }
    }
  }

  # Work-Item-bound failure receipts move no state in this slice: before and after state must match.
  $workItemId = [string]$receipt.com_work_item
  if (-not [string]::IsNullOrWhiteSpace($workItemId)) {
    if ($knownWorkItemIds -notcontains $workItemId) {
      Add-Issue $issues "$subject com_work_item references an unknown Work Item: $workItemId."
    }
    if ((Test-HasNonEmptyField -Record $receipt -Field "com_before_state") -and (Test-HasNonEmptyField -Record $receipt -Field "com_after_state")) {
      if ([string]$receipt.com_before_state -ne [string]$receipt.com_after_state) {
        Add-Issue $issues "$subject must keep com_before_state == com_after_state for a Work-Item-bound failure receipt; Story 2.6 records failures and moves no state in-slice, found: $($receipt.com_before_state) -> $($receipt.com_after_state)."
      }
      if ($workItemStateGroups -notcontains [string]$receipt.com_after_state) {
        Add-Issue $issues "$subject com_after_state must be a manifest com_workitemstategroup value, found: $($receipt.com_after_state)."
      }
      if ($reviewableStateGroups -notcontains [string]$receipt.com_after_state) {
        Add-Issue $issues "$subject com_after_state must be a reviewable state group, found: $($receipt.com_after_state)."
      }
    }
  }
}

# The three kinds must be distinguishable by their field combinations.
$systemErrorReceipt = $receiptByKind["system_error"]
$policyDenialReceipt = $receiptByKind["policy_denial"]
$humanReviewReceipt = $receiptByKind["human_review"]
if ($null -eq $systemErrorReceipt) {
  Add-Issue $issues "Failure slice must include exactly one system_error receipt."
}
else {
  if ($systemErrorReceipt.com_verb -ne "failed" -or $systemErrorReceipt.com_result -ne "failed") {
    Add-Issue $issues "system_error receipt must use verb failed and result failed, found: $($systemErrorReceipt.com_verb) / $($systemErrorReceipt.com_result)."
  }
  if (-not (Test-StrictBooleanTrue $systemErrorReceipt.retryAllowed)) {
    Add-Issue $issues "system_error receipt must have retryAllowed=true (retryable)."
  }
  if ($systemErrorReceipt.humanReviewRequired -isnot [bool] -or $systemErrorReceipt.humanReviewRequired) {
    Add-Issue $issues "system_error receipt must have humanReviewRequired=false (strict boolean)."
  }
}
if ($null -eq $policyDenialReceipt) {
  Add-Issue $issues "Failure slice must include exactly one policy_denial receipt."
}
else {
  if ($policyDenialReceipt.com_verb -ne "policy_denied" -or $policyDenialReceipt.com_result -ne "rejected") {
    Add-Issue $issues "policy_denial receipt must use verb policy_denied and result rejected, found: $($policyDenialReceipt.com_verb) / $($policyDenialReceipt.com_result)."
  }
  if ($policyDenialReceipt.retryAllowed -isnot [bool] -or $policyDenialReceipt.retryAllowed) {
    Add-Issue $issues "policy_denial receipt must have retryAllowed=false (non-retryable, strict boolean)."
  }
  if ($policyDenialReceipt.humanReviewRequired -isnot [bool] -or $policyDenialReceipt.humanReviewRequired) {
    Add-Issue $issues "policy_denial receipt must have humanReviewRequired=false (strict boolean)."
  }
}
if ($null -eq $humanReviewReceipt) {
  Add-Issue $issues "Failure slice must include exactly one human_review receipt."
}
else {
  if ($humanReviewReceipt.com_verb -ne "failed" -or $humanReviewReceipt.com_result -ne "failed") {
    Add-Issue $issues "human_review receipt must use verb failed and result failed, found: $($humanReviewReceipt.com_verb) / $($humanReviewReceipt.com_result)."
  }
  if ($humanReviewReceipt.retryAllowed -isnot [bool] -or $humanReviewReceipt.retryAllowed) {
    Add-Issue $issues "human_review receipt must have retryAllowed=false (strict boolean)."
  }
  if (-not (Test-StrictBooleanTrue $humanReviewReceipt.humanReviewRequired)) {
    Add-Issue $issues "human_review receipt must have humanReviewRequired=true."
  }
}
# Mutual distinguishability: the three receipts must differ by failure code and by at least one of retry/review.
$kindCodes = @($receiptByKind.Keys | ForEach-Object { [string]$receiptByKind[$_].com_failure_code })
if (($kindCodes | Select-Object -Unique).Count -ne $kindCodes.Count) {
  Add-Issue $issues "The three failure kinds must be distinguishable by distinct failure codes, found: $($kindCodes -join ', ')."
}

foreach ($expectedReceiptId in @("CR-LOCAL-FAILURE-001", "CR-LOCAL-FAILURE-002", "CR-LOCAL-FAILURE-003")) {
  if (-not $sliceReceiptIds.ContainsKey($expectedReceiptId)) {
    Add-Issue $issues "Failure slice must include receipt $expectedReceiptId."
  }
}

# Receipt source links: each failure receipt must be bound to its source evidence by a failure_evidence link.
$links = @($run.receiptSourceLinks | Where-Object { $null -ne $_ })
foreach ($link in $links) {
  $linkSubject = "Receipt source link $($link.com_name)"
  if (-not (Test-HasNonEmptyField -Record $link -Field "com_name")) {
    Add-Issue $issues "Receipt source link must carry a non-empty com_name."
  }
  $linkReceiptId = [string]$link.com_receipt
  if ([string]::IsNullOrWhiteSpace($linkReceiptId) -or -not $sliceReceiptIds.ContainsKey($linkReceiptId)) {
    Add-Issue $issues "$linkSubject references unknown receipt: $linkReceiptId."
  }
  if ($knownPriorSourceIds -notcontains [string]$link.com_source_record) {
    Add-Issue $issues "$linkSubject must bind a known prior Source Record, found: $($link.com_source_record)."
  }
  if ($evidenceRoles -notcontains $link.com_evidence_role) {
    Add-Issue $issues "$linkSubject evidence role is not in manifest vocabulary: $($link.com_evidence_role)."
  }
  elseif ($link.com_evidence_role -ne "failure_evidence") {
    Add-Issue $issues "$linkSubject must use the failure_evidence role, found: $($link.com_evidence_role)."
  }
}
foreach ($receiptId in @($sliceReceiptIds.Keys)) {
  if (@($links | Where-Object { $_.com_receipt -eq $receiptId }).Count -lt 1) {
    Add-Issue $issues "Receipt $receiptId must be bound to its source evidence by at least one failure_evidence receipt source link."
  }
}

# Policy denial traceability: the policy_denied receipt must trace to specific policy flags and evidence refs that resolve within the slice.
$policyDenialTraceEntries = @($run.policyDenialTrace | Where-Object { $null -ne $_ })
if ($policyDenialTraceEntries.Count -ne 1) {
  Add-Issue $issues "Failure slice must record exactly one policyDenialTrace entry for the policy denial, found $($policyDenialTraceEntries.Count)."
}
foreach ($trace in $policyDenialTraceEntries) {
  $traceSubject = "Policy denial trace"
  $traceReceiptId = [string]$trace.receipt
  if ([string]::IsNullOrWhiteSpace($traceReceiptId) -or -not $sliceReceiptIds.ContainsKey($traceReceiptId)) {
    Add-Issue $issues "$traceSubject must name a slice receipt, found: $traceReceiptId."
    continue
  }
  if ($traceReceiptId -ne "CR-LOCAL-FAILURE-002") {
    Add-Issue $issues "$traceSubject must reference the policy denial receipt CR-LOCAL-FAILURE-002, found: $traceReceiptId."
  }
  $tracedReceipt = $receipts | Where-Object { $_.com_receipt_id -eq $traceReceiptId } | Select-Object -First 1
  if ($null -eq $tracedReceipt) {
    continue
  }
  if (-not (Test-HasNonEmptyField -Record $trace -Field "denialRationale")) {
    Add-Issue $issues "$traceSubject must carry a non-empty denialRationale."
  }
  $tracedFlags = @($trace.policyFlagsTraced | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($tracedFlags.Count -lt 2) {
    Add-Issue $issues "$traceSubject must trace at least two policy flags, found $($tracedFlags.Count)."
  }
  foreach ($flag in $tracedFlags) {
    if ([string]$tracedReceipt.com_policy_flags -notmatch [regex]::Escape([string]$flag)) {
      Add-Issue $issues "$traceSubject policy flag '$flag' must appear in the denial receipt's com_policy_flags."
    }
  }
  $requiredDenialFlags = @("policy_denied", "human_approval_required")
  foreach ($requiredFlag in $requiredDenialFlags) {
    if ($tracedFlags -notcontains $requiredFlag) {
      Add-Issue $issues "$traceSubject policyFlagsTraced must include $requiredFlag."
    }
  }
  $tracedRefs = @($trace.evidenceRefsTraced | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($tracedRefs.Count -lt 1) {
    Add-Issue $issues "$traceSubject must trace at least one evidence reference."
  }
  foreach ($ref in $tracedRefs) {
    if ($knownPriorSourceIds -notcontains $ref -and $knownWorkItemIds -notcontains $ref) {
      Add-Issue $issues "$traceSubject evidence ref '$ref' does not resolve to a known prior Source Record or Work Item."
    }
    if (([string]$tracedReceipt.com_evidence_refs) -notmatch [regex]::Escape([string]$ref)) {
      Add-Issue $issues "$traceSubject evidence ref '$ref' must appear in the denial receipt's com_evidence_refs."
    }
  }
  $affectedId = [string]$trace.affectedWorkItem
  if ([string]::IsNullOrWhiteSpace($affectedId) -or $knownWorkItemIds -notcontains $affectedId) {
    Add-Issue $issues "$traceSubject affectedWorkItem must reference a known prior Work Item, found: $affectedId."
  }
  else {
    $affectedItem = $knownWorkItemsById[$affectedId]
    $tracedState = [string]$trace.reviewableStateGroup
    if ($workItemStateGroups -notcontains $tracedState) {
      Add-Issue $issues "$traceSubject reviewableStateGroup must be a manifest com_workitemstategroup value, found: $tracedState."
    }
    elseif ($reviewableStateGroups -notcontains $tracedState) {
      Add-Issue $issues "$traceSubject reviewableStateGroup must be a reviewable state group, found: $tracedState."
    }
    if ($null -ne $affectedItem -and (Test-HasNonEmptyField -Record $affectedItem -Field "com_state_group")) {
      if ([string]$affectedItem.com_state_group -ne $tracedState) {
        Add-Issue $issues "$traceSubject reviewableStateGroup ($tracedState) must match the affected Work Item's actual com_state_group in its source slice ($($affectedItem.com_state_group))."
      }
    }
    if ($trace.stateGroupChangedInThisSlice -isnot [bool] -or $trace.stateGroupChangedInThisSlice) {
      Add-Issue $issues "$traceSubject must state stateGroupChangedInThisSlice=false (strict boolean); a policy denial moves no state in-slice."
    }
    elseif (-not $trace.stateGroupChangedInThisSlice) {
      if ([string]$tracedReceipt.com_before_state -ne [string]$tracedReceipt.com_after_state) {
        Add-Issue $issues "$traceSubject denial receipt must keep before==after state since stateGroupChangedInThisSlice=false."
      }
    }
  }
}

# Affected work items: each must be a known prior Work Item in a reviewable state group, with no in-slice state change.
$affectedWorkItems = @($run.affectedWorkItems | Where-Object { $null -ne $_ })
if ($affectedWorkItems.Count -lt 1) {
  Add-Issue $issues "Failure slice must record its affected Work Items in affectedWorkItems."
}
$seenAffectedIds = @{}
foreach ($affected in $affectedWorkItems) {
  $affectedId = [string]$affected.workItem
  $subject = "Affected Work Item $affectedId"
  if ([string]::IsNullOrWhiteSpace($affectedId) -or $knownWorkItemIds -notcontains $affectedId) {
    Add-Issue $issues "$subject must reference a known prior Work Item."
    continue
  }
  if ($seenAffectedIds.ContainsKey($affectedId)) {
    Add-Issue $issues "$subject duplicate affectedWorkItems entry."
  }
  else {
    $seenAffectedIds[$affectedId] = $true
  }
  $affectedItem = $knownWorkItemsById[$affectedId]
  if ($null -ne $affectedItem -and (Test-HasNonEmptyField -Record $affectedItem -Field "com_state_group")) {
    if ([string]$affected.com_state_group -ne [string]$affectedItem.com_state_group) {
      Add-Issue $issues "$subject com_state_group must match the actual value in its source slice ($($affectedItem.com_state_group)), found: $($affected.com_state_group)."
    }
    if ($reviewableStateGroups -notcontains [string]$affected.com_state_group) {
      Add-Issue $issues "$subject com_state_group must be a reviewable state group, found: $($affected.com_state_group)."
    }
  }
  if ($affected.reviewable -isnot [bool] -or -not $affected.reviewable) {
    Add-Issue $issues "$subject reviewable must be strict boolean true."
  }
  if ($affected.stateGroupChangedInThisSlice -isnot [bool] -or $affected.stateGroupChangedInThisSlice) {
    Add-Issue $issues "$subject must state stateGroupChangedInThisSlice=false (strict boolean)."
  }
  if (-not (Test-HasNonEmptyField -Record $affected -Field "note")) {
    Add-Issue $issues "$subject must carry a non-empty note."
  }
}
if (-not $seenAffectedIds.ContainsKey("CWI-LOCAL-FOLLOWUP-001")) {
  Add-Issue $issues "The policy-denied Work Item CWI-LOCAL-FOLLOWUP-001 must appear in affectedWorkItems."
}

# Deferred Work Item state changes: every Work-Item-bound failure receipt must have a deferred entry stating the live move is receipt-gated.
$workItemStateChangesDeferred = @($run.workItemStateChangesDeferred | Where-Object { $null -ne $_ })
$deferredWorkItemIds = @{}
foreach ($deferred in $workItemStateChangesDeferred) {
  $deferredId = [string]$deferred.workItem
  if ([string]::IsNullOrWhiteSpace($deferredId) -or $knownWorkItemIds -notcontains $deferredId) {
    Add-Issue $issues "Deferred Work Item state change references an unknown Work Item: $deferredId."
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred Work Item state change must carry a non-empty deferredUpdate: $deferredId."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred Work Item state change for $deferredId must state that any state move is receipt-gated."
  }
  if (-not [string]::IsNullOrWhiteSpace($deferredId)) {
    $deferredWorkItemIds[$deferredId] = $true
  }
}
foreach ($receipt in $receipts) {
  $workItemId = [string]$receipt.com_work_item
  if ([string]::IsNullOrWhiteSpace($workItemId)) {
    continue
  }
  if (-not $deferredWorkItemIds.ContainsKey($workItemId)) {
    Add-Issue $issues "Work-Item-bound failure receipt $($receipt.com_receipt_id) must have a matching workItemStateChangesDeferred entry for $workItemId."
  }
}

foreach ($criterion in @(1, 2, 3)) {
  $mapping = @($failure.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
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
  Write-Host "Failure and policy denial slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Failure and policy denial slice validation succeeded."
Write-Host "Failure receipts: $($receipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "Policy denial traces: $($policyDenialTraceEntries.Count)"
Write-Host "Affected work items: $($affectedWorkItems.Count)"
Write-Host "FAILURE_POLICY_DENIAL_SLICE_VALIDATE_OK"
