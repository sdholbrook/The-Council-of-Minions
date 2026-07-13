param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$SlicePath = "$PSScriptRoot\receipt-backed-state-changes-slice.json",
  [string]$ManualSlicePath = "$PSScriptRoot\manual-source-record-slice.json",
  [string]$OutlookSlicePath = "$PSScriptRoot\outlook-source-reference-slice.json",
  [string]$Story13ExtractionPath = "$PSScriptRoot\proposed-work-item-extraction-slice.json",
  [string]$Story14ExtractionPath = "$PSScriptRoot\zero-multi-item-extraction-slice.json",
  [string]$Story15DriftPath = "$PSScriptRoot\source-drift-supersession-slice.json",
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
      Add-Issue $Issues "$Subject ${Field} must be ISO 8601 with an explicit UTC offset so ordering is not host-timezone dependent, found: $rawValue."
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
    Add-Issue $Issues "$Subject ${Field} must be ISO 8601 with an explicit UTC offset so ordering is not host-timezone dependent, found: $rawValue."
    return $null
  }
  return $parsed
}

function Get-ComparableInstant {
  param($Value)
  if ($null -eq $Value) {
    return $null
  }
  if ($Value -is [datetime]) {
    if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) {
      return $null
    }
    return [datetimeoffset]$Value
  }
  $parsed = [datetimeoffset]::MinValue
  if ([datetimeoffset]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
    return $parsed
  }
  return $null
}

function Read-JsonInput {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )
  try {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  }
  catch {
    Write-Host "Receipt-backed state changes slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

function Get-IdsFromSliceText {
  param(
    [Parameter(Mandatory = $true)][string]$RawText,
    [Parameter(Mandatory = $true)][string]$Pattern
  )
  $matches = [regex]::Matches($RawText, $Pattern)
  $ids = [System.Collections.Generic.List[string]]::new()
  foreach ($m in $matches) {
    $val = [string]$m.Groups[1].Value
    if (-not [string]::IsNullOrWhiteSpace($val) -and $ids -notcontains $val) {
      $ids.Add($val)
    }
  }
  return @($ids)
}

foreach ($path in @($ManifestPath, $SlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $Story15DriftPath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required receipt-backed state changes validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$slice = Read-JsonInput -Path $SlicePath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$story15Drift = Read-JsonInput -Path $Story15DriftPath
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath
$rawSliceText = Get-Content -LiteralPath $SlicePath -Raw
$issues = [System.Collections.Generic.List[string]]::new()

$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$stateGroups = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemstategroup"
$workItemTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemtype"
$riskClasses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_riskclass"

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_workitemstategroup"; Values = $stateGroups },
    @{ Name = "com_workitemtype"; Values = $workItemTypes },
    @{ Name = "com_riskclass"; Values = $riskClasses }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

foreach ($requiredVerb in @("proposed", "approved", "blocked", "held", "resumed", "reviewed", "completed", "failed")) {
  if ($receiptVerbs -notcontains $requiredVerb) {
    Add-Issue $issues "Manifest com_receiptverb is missing required state verb: $requiredVerb."
  }
}

if ($slice.storyKey -ne "2-3-apply-receipt-backed-queue-state-changes") {
  Add-Issue $issues "State-change slice storyKey must be 2-3-apply-receipt-backed-queue-state-changes."
}
if ([string]$slice.status -notmatch "^local-contract") {
  Add-Issue $issues "State-change slice status must declare local contract evidence, found: $($slice.status)."
}

$requiredGuards = @(
  "noTenantWrites",
  "noOutboundAction",
  "noApprovalExecution",
  "requiresExplicitHumanApprovalForExecution",
  "receiptsAreLocalContractEvidenceOnly",
  "receiptsAreAppendOnly",
  "priorReceiptsUnchanged",
  "correctionsAreNewReceiptsOnly"
)
foreach ($guard in $requiredGuards) {
  if (-not ($slice.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "State-change slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($slice.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "State-change guard must be boolean true: $($guardProperty.Name)."
  }
}

# Cross-slice ID inventories (siblings 1.1-1.5 + demo)
$siblingRaw = @()
foreach ($siblingPath in @($ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $Story15DriftPath, $DemoEvidencePath)) {
  $siblingRaw += Get-Content -LiteralPath $siblingPath -Raw
}
$siblingText = $siblingRaw -join "`n"

$siblingCwiIds = Get-IdsFromSliceText -RawText $siblingText -Pattern '"com_council_work_item_id"\s*:\s*"(CWI-[^"]+)"'
$siblingCwiIds += Get-IdsFromSliceText -RawText $siblingText -Pattern '"(CWI-(?:LOCAL|DEMO)[^"]+)"'
$siblingCrIds = Get-IdsFromSliceText -RawText $siblingText -Pattern '"com_receipt_id"\s*:\s*"(CR-[^"]+)"'
$siblingCrIds += Get-IdsFromSliceText -RawText $siblingText -Pattern '"(CR-(?:LOCAL|DEMO)[^"]+)"'
$siblingCsrIds = Get-IdsFromSliceText -RawText $siblingText -Pattern '"com_council_source_record_id"\s*:\s*"(CSR-[^"]+)"'

$demoReceiptIds = @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$demoWorkItemIds = @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($demoReceiptIds.Count -eq 0) {
  Add-Issue $issues "No reserved receipt IDs could be loaded from state-transition-demo-evidence.json; receipt collision checks would silently no-op."
}
if ($demoWorkItemIds.Count -eq 0) {
  Add-Issue $issues "No reserved work-item IDs could be loaded from state-transition-demo-evidence.json; work-item collision checks would silently no-op."
}

$driftReceipts = @()
if ($null -ne $story15Drift.driftRun -and $null -ne $story15Drift.driftRun.receipts) {
  $driftReceipts = @($story15Drift.driftRun.receipts | Where-Object { $null -ne $_ })
}
if ($driftReceipts.Count -eq 0) {
  Add-Issue $issues "No receipts loaded from source-drift-supersession-slice.json; cross-slice CR-* collision checks would silently no-op."
}
$driftReceiptIds = @($driftReceipts | ForEach-Object { [string]$_.com_receipt_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$knownPriorWorkItemIds = @(
  @($story13Items + $story14Items) | ForEach-Object { [string]$_.com_council_work_item_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($knownPriorWorkItemIds.Count -eq 0) {
  Add-Issue $issues "No Work Item IDs could be loaded from Story 1.3/1.4 slices; cross-slice CWI collision checks would silently no-op."
}

$manualSources = @($manualSlice.manualCapture.sampleRecords | Where-Object { $null -ne $_ })
$outlookSources = @($outlookSlice.outlookCapture.sampleRecords | Where-Object { $null -ne $_ })
$story14EmbeddedSources = @($story14Extraction.extractionRun.embeddedSampleSourceRecords | Where-Object { $null -ne $_ })
$knownPriorSourceIds = @(
  @($manualSources + $outlookSources + $story14EmbeddedSources) |
    ForEach-Object { [string]$_.com_council_source_record_id } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique
)
if ($knownPriorSourceIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be loaded from sibling slices; primary-source binding checks would silently no-op."
}

foreach ($sliceLoad in @(
    @{ Name = "manual-source-record-slice sampleRecords"; Count = $manualSources.Count },
    @{ Name = "outlook-source-reference-slice sampleRecords"; Count = $outlookSources.Count },
    @{ Name = "zero-multi-item-extraction-slice embeddedSampleSourceRecords"; Count = $story14EmbeddedSources.Count },
    @{ Name = "proposed-work-item-extraction-slice proposedWorkItems"; Count = $story13Items.Count },
    @{ Name = "zero-multi-item-extraction-slice proposedWorkItems"; Count = $story14Items.Count },
    @{ Name = "source-drift-supersession-slice receipts"; Count = $driftReceipts.Count }
  )) {
  if ($sliceLoad.Count -eq 0) {
    Add-Issue $issues "No records loaded from $($sliceLoad.Name); its cross-slice checks would silently no-op."
  }
}

$run = $slice.stateChangeRun
if ($null -eq $run) {
  Add-Issue $issues "State-change slice must carry a stateChangeRun block."
  Write-Host "Receipt-backed state changes slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "State-change run must declare a runId."
}
elseif ([string]$run.runId -match "DRIFT-LOCAL|EXTRACT") {
  Add-Issue $issues "State-change run must use a new local runId, not a prior-story runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "State-change run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "State-change run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "State-change run must carry a non-empty ${field}."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "State-change run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @(
      "everyStateChangeRequiresAppendedReceipt",
      "receiptsAreAppendOnlyNeverEdited",
      "correctionsAreNewReceiptsOnly",
      "verbsDrawnOnlyFromManifest",
      "occurredAtStrictlyOrderedPerChain",
      "liveWorkItemMutationReceiptGated"
    )) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "State-change decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "State-change decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

$workItems = @($run.workItems | Where-Object { $null -ne $_ })
if ($workItems.Count -lt 3) {
  Add-Issue $issues "State-change run must include at least three Work Items (happy, blocked, correction), found $($workItems.Count)."
}

$workItemTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilworkitem" } | Select-Object -First 1
$manifestRequiredWorkItemFields = @(@($workItemTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredWorkItemFields.Count -eq 0) {
  Add-Issue $issues "No required work-item columns could be derived from manifest com_councilworkitem; required-field checks would silently no-op."
}

$sliceWorkItemIds = @{}
foreach ($item in $workItems) {
  $itemId = [string]$item.com_council_work_item_id
  $subject = "Work Item $itemId"
  foreach ($field in $manifestRequiredWorkItemFields) {
    if ($field -eq "com_primary_source_record") {
      if (-not (Test-HasNonEmptyField -Record $item -Field $field)) {
        Add-Issue $issues "$subject missing required manifest field: $field."
      }
      continue
    }
    if (-not (Test-HasNonEmptyField -Record $item -Field $field) -and $field -ne "com_approval_required") {
      # booleans handled below
      if (@($item.PSObject.Properties.Name) -notcontains $field) {
        Add-Issue $issues "$subject missing required manifest field: $field."
      }
    }
  }
  if ([string]::IsNullOrWhiteSpace($itemId)) {
    Add-Issue $issues "Work Item must declare com_council_work_item_id."
  }
  else {
    if ($itemId -notmatch "^CWI-LOCAL-") {
      Add-Issue $issues "$subject must use new CWI-LOCAL-* identity."
    }
    if ($sliceWorkItemIds.ContainsKey($itemId)) {
      Add-Issue $issues "Duplicate Work Item ID in slice: $itemId."
    }
    else {
      $sliceWorkItemIds[$itemId] = $true
    }
    if ($knownPriorWorkItemIds -contains $itemId -or $demoWorkItemIds -contains $itemId) {
      Add-Issue $issues "$subject collides with a reserved sibling or demo Work Item ID."
    }
  }
  if ($workItemTypes -notcontains $item.com_type) {
    Add-Issue $issues "$subject type is not in manifest com_workitemtype vocabulary: $($item.com_type)."
  }
  if ($stateGroups -notcontains $item.com_state_group) {
    Add-Issue $issues "$subject state group is not in manifest com_workitemstategroup vocabulary: $($item.com_state_group)."
  }
  if ($riskClasses -notcontains $item.com_risk_class) {
    Add-Issue $issues "$subject risk class is not in manifest com_riskclass vocabulary: $($item.com_risk_class)."
  }
  if ($item.com_approval_required -isnot [bool]) {
    Add-Issue $issues "$subject com_approval_required must be a strict boolean."
  }
  $primarySource = [string]$item.com_primary_source_record
  if (-not [string]::IsNullOrWhiteSpace($primarySource) -and $knownPriorSourceIds -notcontains $primarySource) {
    Add-Issue $issues "$subject primary source must reference a known sibling CSR-* id, found: $primarySource."
  }
  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($item.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'."
    }
  }
}

foreach ($expectedItem in @("CWI-LOCAL-QUEUE-HAPPY-001", "CWI-LOCAL-QUEUE-BLOCK-001", "CWI-LOCAL-QUEUE-CORR-001")) {
  if (-not $sliceWorkItemIds.ContainsKey($expectedItem)) {
    Add-Issue $issues "State-change slice must include Work Item $expectedItem."
  }
}

$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
# Manifest-required columns plus story-pinned receipt contract fields for state transitions.
$receiptRequiredFields = @(
  $manifestRequiredReceiptFields + @(
    "com_before_state",
    "com_after_state",
    "com_evidence_refs",
    "com_decision_rationale",
    "com_policy_flags",
    "com_work_item"
  )
) | Sort-Object -Unique

$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 11) {
  Add-Issue $issues "State-change run must include at least 11 receipts (4 happy + 4 blocked + 3 correction), found $($receipts.Count)."
}

$sliceReceiptIds = @{}
$seenIdempotencyKeys = @{}
$receiptById = @{}
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
    if ($receiptId -notmatch "^CR-LOCAL-") {
      Add-Issue $issues "$subject must use new CR-LOCAL-* identity."
    }
    if ($sliceReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "Duplicate receipt ID in slice: $receiptId."
    }
    else {
      $sliceReceiptIds[$receiptId] = $true
      $receiptById[$receiptId] = $receipt
    }
    if ($demoReceiptIds -contains $receiptId) {
      Add-Issue $issues "$subject collides with a reserved state-transition-demo receipt ID."
    }
    if ($driftReceiptIds -contains $receiptId) {
      Add-Issue $issues "$subject collides with a Story 1.5 drift/supersession receipt ID."
    }
  }

  $workItemRef = [string]$receipt.com_work_item
  if (-not [string]::IsNullOrWhiteSpace($workItemRef) -and -not $sliceWorkItemIds.ContainsKey($workItemRef)) {
    Add-Issue $issues "$subject references unknown Work Item in this slice: $workItemRef."
  }

  if ($receiptVerbs -notcontains $receipt.com_verb) {
    Add-Issue $issues "$subject verb is not in manifest com_receiptverb vocabulary: $($receipt.com_verb)."
  }
  if ($actorTypes -notcontains $receipt.com_actor_type) {
    Add-Issue $issues "$subject actor type is not in manifest com_actortype vocabulary: $($receipt.com_actor_type)."
  }
  if ($receiptResults -notcontains $receipt.com_result) {
    Add-Issue $issues "$subject result is not in manifest com_receiptresult vocabulary: $($receipt.com_result)."
  }

  $before = [string]$receipt.com_before_state
  $after = [string]$receipt.com_after_state
  if ($before -ne "none" -and $stateGroups -notcontains $before) {
    Add-Issue $issues "$subject com_before_state must be a manifest state group or 'none', found: $before."
  }
  if ($stateGroups -notcontains $after) {
    Add-Issue $issues "$subject com_after_state must be a manifest state group, found: $after."
  }

  Test-IsoTimestamp -Issues $issues -Record $receipt -Field "com_occurred_at" -Subject $subject | Out-Null

  $idempotencyKey = [string]$receipt.com_idempotency_key
  if (-not [string]::IsNullOrWhiteSpace($idempotencyKey)) {
    if ($seenIdempotencyKeys.ContainsKey($idempotencyKey)) {
      Add-Issue $issues "$subject reuses an idempotency key already used in this slice: $idempotencyKey."
    }
    else {
      $seenIdempotencyKeys[$idempotencyKey] = $true
    }
  }

  if ($receipt.com_append_only_locked -isnot [bool] -or -not $receipt.com_append_only_locked) {
    Add-Issue $issues "$subject com_append_only_locked must be strict boolean true."
  }
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject

  if ([string]$receipt.com_result -eq "failed" -and -not (Test-HasNonEmptyField -Record $receipt -Field "com_failure_code")) {
    Add-Issue $issues "$subject with result failed must carry com_failure_code."
  }

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 2.3 receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; receipts are local contract evidence only."
      }
    }
  }
}

# Transition chains: completeness + unbroken before/after + strict time order
$chains = @($run.transitionChains | Where-Object { $null -ne $_ })
if ($chains.Count -lt 3) {
  Add-Issue $issues "State-change run must declare at least three transitionChains, found $($chains.Count)."
}

$chainIdsSeen = @{}
$receiptsAssignedToChain = @{}
$happyChainFound = $false
$blockChainFound = $false
$corrChainFound = $false

foreach ($chain in $chains) {
  $chainId = [string]$chain.chainId
  $chainSubject = "Transition chain $chainId"
  if ([string]::IsNullOrWhiteSpace($chainId)) {
    Add-Issue $issues "Transition chain must declare chainId."
    continue
  }
  if ($chainIdsSeen.ContainsKey($chainId)) {
    Add-Issue $issues "Duplicate transition chainId: $chainId."
  }
  else {
    $chainIdsSeen[$chainId] = $true
  }

  $chainWorkItem = [string]$chain.workItem
  if ([string]::IsNullOrWhiteSpace($chainWorkItem) -or -not $sliceWorkItemIds.ContainsKey($chainWorkItem)) {
    Add-Issue $issues "$chainSubject references unknown Work Item: $chainWorkItem."
  }

  $chainReceiptIds = @($chain.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  $expectedStates = @($chain.expectedStates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($chainReceiptIds.Count -lt 2) {
    Add-Issue $issues "$chainSubject must list at least two receiptIds."
  }
  if ($expectedStates.Count -ne $chainReceiptIds.Count) {
    Add-Issue $issues "$chainSubject expectedStates count ($($expectedStates.Count)) must match receiptIds count ($($chainReceiptIds.Count))."
  }

  $priorAfter = $null
  $priorOccurred = $null
  for ($i = 0; $i -lt $chainReceiptIds.Count; $i++) {
    $rid = [string]$chainReceiptIds[$i]
    if (-not $sliceReceiptIds.ContainsKey($rid)) {
      Add-Issue $issues "$chainSubject references unknown receipt: $rid."
      continue
    }
    if ($receiptsAssignedToChain.ContainsKey($rid)) {
      Add-Issue $issues "Receipt $rid is assigned to multiple chains ($($receiptsAssignedToChain[$rid]) and $chainId)."
    }
    else {
      $receiptsAssignedToChain[$rid] = $chainId
    }

    $receipt = $receiptById[$rid]
    if ([string]$receipt.com_work_item -ne $chainWorkItem) {
      Add-Issue $issues "$chainSubject receipt $rid must target Work Item $chainWorkItem, found: $($receipt.com_work_item)."
    }

    $after = [string]$receipt.com_after_state
    $before = [string]$receipt.com_before_state
    if ($i -lt $expectedStates.Count -and $after -ne [string]$expectedStates[$i]) {
      Add-Issue $issues "$chainSubject receipt $rid after_state must equal expectedStates[$i]=$($expectedStates[$i]), found: $after."
    }
    if ($i -eq 0) {
      if ($before -ne "none") {
        Add-Issue $issues "$chainSubject first receipt $rid com_before_state must be 'none', found: $before."
      }
    }
    else {
      if ($null -ne $priorAfter -and $before -ne $priorAfter) {
        Add-Issue $issues "$chainSubject unbroken chain broken at ${rid}: before_state=$before but prior after_state=$priorAfter."
      }
    }
    $priorAfter = $after

    $occurred = Get-ComparableInstant -Value $receipt.com_occurred_at
    if ($null -eq $occurred) {
      # already flagged by Test-IsoTimestamp when parse fails
    }
    elseif ($null -ne $priorOccurred -and $occurred -le $priorOccurred) {
      Add-Issue $issues "$chainSubject occurred-at must be strictly increasing; $rid is not after its predecessor."
    }
    if ($null -ne $occurred) {
      $priorOccurred = $occurred
    }
  }

  $pathLabel = [string]$chain.pathLabel
  if ($chainWorkItem -eq "CWI-LOCAL-QUEUE-HAPPY-001") {
    $happyChainFound = $true
    if ($pathLabel -notmatch "proposed" -or $pathLabel -notmatch "approved" -or $pathLabel -notmatch "in_review" -or $pathLabel -notmatch "completed") {
      Add-Issue $issues "$chainSubject pathLabel must describe proposed → approved → in_review → completed."
    }
    if ($expectedStates -join "," -ne "proposed,approved,in_review,completed") {
      Add-Issue $issues "$chainSubject expectedStates must be proposed,approved,in_review,completed."
    }
    foreach ($verb in @("proposed", "approved", "reviewed", "completed")) {
      $hasVerb = $false
      foreach ($rid in $chainReceiptIds) {
        if ($receiptById.ContainsKey($rid) -and [string]$receiptById[$rid].com_verb -eq $verb) {
          $hasVerb = $true
        }
      }
      if (-not $hasVerb) {
        Add-Issue $issues "$chainSubject must include a receipt with verb $verb."
      }
    }
  }
  if ($chainWorkItem -eq "CWI-LOCAL-QUEUE-BLOCK-001") {
    $blockChainFound = $true
    if ($pathLabel -notmatch "proposed" -or $pathLabel -notmatch "blocked" -or $pathLabel -notmatch "resumed" -or $pathLabel -notmatch "failed") {
      Add-Issue $issues "$chainSubject pathLabel must describe proposed → blocked → resumed → failed."
    }
    foreach ($verb in @("proposed", "blocked", "resumed", "failed")) {
      $hasVerb = $false
      foreach ($rid in $chainReceiptIds) {
        if ($receiptById.ContainsKey($rid) -and [string]$receiptById[$rid].com_verb -eq $verb) {
          $hasVerb = $true
        }
      }
      if (-not $hasVerb) {
        Add-Issue $issues "$chainSubject must include a receipt with verb $verb."
      }
    }
  }
  if ($chainWorkItem -eq "CWI-LOCAL-QUEUE-CORR-001") {
    $corrChainFound = $true
    if ($chain.includesCorrection -isnot [bool] -or -not $chain.includesCorrection) {
      Add-Issue $issues "$chainSubject must declare includesCorrection=true (strict boolean)."
    }
  }

  # Final projected work-item state must match last after_state
  $item = $workItems | Where-Object { $_.com_council_work_item_id -eq $chainWorkItem } | Select-Object -First 1
  if ($item -and $chainReceiptIds.Count -ge 1) {
    $lastRid = [string]$chainReceiptIds[$chainReceiptIds.Count - 1]
    if ($receiptById.ContainsKey($lastRid)) {
      $lastAfter = [string]$receiptById[$lastRid].com_after_state
      if ([string]$item.com_state_group -ne $lastAfter) {
        Add-Issue $issues "Work Item $chainWorkItem com_state_group ($($item.com_state_group)) must match last receipt after_state ($lastAfter)."
      }
    }
  }
}

if (-not $happyChainFound) {
  Add-Issue $issues "Missing happy-path transition chain for CWI-LOCAL-QUEUE-HAPPY-001."
}
if (-not $blockChainFound) {
  Add-Issue $issues "Missing blocked-path transition chain for CWI-LOCAL-QUEUE-BLOCK-001."
}
if (-not $corrChainFound) {
  Add-Issue $issues "Missing correction transition chain for CWI-LOCAL-QUEUE-CORR-001."
}

# Every receipt must belong to exactly one chain (no free-floating state-change receipts)
foreach ($rid in @($sliceReceiptIds.Keys)) {
  if (-not $receiptsAssignedToChain.ContainsKey($rid)) {
    Add-Issue $issues "Receipt $rid is not assigned to any transition chain; every state-change receipt must sit on a chain."
  }
}

# Correction scenario
$corr = $run.correctionScenario
if ($null -eq $corr) {
  Add-Issue $issues "State-change run must declare a correctionScenario block."
}
else {
  if ($corr.priorReceiptsUnchanged -isnot [bool] -or -not $corr.priorReceiptsUnchanged) {
    Add-Issue $issues "correctionScenario.priorReceiptsUnchanged must be strict boolean true."
  }
  $errId = [string]$corr.erroneousReceiptId
  $fixId = [string]$corr.correctionReceiptId
  if (-not $sliceReceiptIds.ContainsKey($errId)) {
    Add-Issue $issues "correctionScenario.erroneousReceiptId unknown: $errId."
  }
  if (-not $sliceReceiptIds.ContainsKey($fixId)) {
    Add-Issue $issues "correctionScenario.correctionReceiptId unknown: $fixId."
  }
  if ($errId -eq $fixId -and -not [string]::IsNullOrWhiteSpace($errId)) {
    Add-Issue $issues "correctionScenario must use a NEW correction receipt distinct from the erroneous receipt."
  }
  if ($receiptById.ContainsKey($fixId)) {
    $fixReceipt = $receiptById[$fixId]
    if (-not (Test-HasNonEmptyField -Record $fixReceipt -Field "correctsReceipt") -or [string]$fixReceipt.correctsReceipt -ne $errId) {
      Add-Issue $issues "Correction receipt $fixId must declare correctsReceipt=$errId."
    }
    if ($fixReceipt.priorReceiptsUnchanged -isnot [bool] -or -not $fixReceipt.priorReceiptsUnchanged) {
      Add-Issue $issues "Correction receipt $fixId must declare priorReceiptsUnchanged=true."
    }
    if ([string]$fixReceipt.com_evidence_refs -notmatch [regex]::Escape("corrects:$errId") -and [string]$fixReceipt.com_evidence_refs -notmatch [regex]::Escape($errId)) {
      Add-Issue $issues "Correction receipt $fixId evidence_refs must reference the erroneous receipt $errId."
    }
    $fixOccurred = Get-ComparableInstant -Value $fixReceipt.com_occurred_at
    if ($receiptById.ContainsKey($errId)) {
      $errOccurred = Get-ComparableInstant -Value $receiptById[$errId].com_occurred_at
      if ($null -ne $fixOccurred -and $null -ne $errOccurred -and $fixOccurred -le $errOccurred) {
        Add-Issue $issues "Correction receipt $fixId must occur strictly after erroneous receipt $errId."
      }
      if ($receiptById[$errId].com_append_only_locked -isnot [bool] -or -not $receiptById[$errId].com_append_only_locked) {
        Add-Issue $issues "Erroneous receipt $errId must remain com_append_only_locked=true (original unedited)."
      }
    }
  }
  $corrWorkItem = [string]$corr.workItem
  if ($corrWorkItem -ne "CWI-LOCAL-QUEUE-CORR-001") {
    Add-Issue $issues "correctionScenario.workItem must be CWI-LOCAL-QUEUE-CORR-001, found: $corrWorkItem."
  }
  if (-not (Test-HasNonEmptyField -Record $corr -Field "note")) {
    Add-Issue $issues "correctionScenario must carry a non-empty note describing append-only correction semantics."
  }
}

# Live writes deferred — every work item needs a deferred gate entry
$deferred = @($run.liveWritesDeferred | Where-Object { $null -ne $_ })
if ($deferred.Count -lt 3) {
  Add-Issue $issues "liveWritesDeferred must include at least one entry per Work Item plus ledger, found $($deferred.Count)."
}
$deferredTargets = @()
foreach ($entry in $deferred) {
  if (-not (Test-HasNonEmptyField -Record $entry -Field "target")) {
    Add-Issue $issues "Deferred live-write entry must name its target."
  }
  if (-not (Test-HasNonEmptyField -Record $entry -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred live-write entry for $($entry.target) must describe deferredUpdate."
  }
  elseif ([string]$entry.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred live-write entry for $($entry.target) must state the mutation is receipt-gated."
  }
  if (-not (Test-HasNonEmptyField -Record $entry -Field "receiptGate")) {
    Add-Issue $issues "Deferred live-write entry for $($entry.target) must name a receiptGate."
  }
  $deferredTargets += [string]$entry.target
  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($entry.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "Deferred live-write entry must not carry live-write marker field '$liveWriteField'."
    }
  }
}
foreach ($itemId in @($sliceWorkItemIds.Keys)) {
  if ($deferredTargets -notcontains $itemId) {
    Add-Issue $issues "Missing liveWritesDeferred entry for Work Item $itemId."
  }
}

# Acceptance mapping for both ACs
foreach ($criterion in @(1, 2)) {
  $mapping = @($slice.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
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

# Tripwire: raw slice text must mention the OK-required correction linkage literally
if ($rawSliceText -notmatch "correctsReceipt") {
  Add-Issue $issues "Slice must carry correctsReceipt on the correction receipt so correction semantics are machine-checkable."
}
if ($rawSliceText -notmatch '"priorReceiptsUnchanged"\s*:\s*true') {
  Add-Issue $issues "Slice must declare priorReceiptsUnchanged true for append-only correction evidence."
}

if ($issues.Count -gt 0) {
  Write-Host "Receipt-backed state changes slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Receipt-backed state changes slice validation succeeded."
Write-Host "Work Items: $($workItems.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Transition chains: $($chains.Count)"
Write-Host "Deferred live writes: $($deferred.Count)"
Write-Host "RECEIPT_BACKED_STATE_CHANGES_SLICE_VALIDATE_OK"
