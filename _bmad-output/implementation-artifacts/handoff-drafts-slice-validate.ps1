param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$DraftSlicePath = "$PSScriptRoot\handoff-drafts-slice.json",
  [string]$ManualSlicePath = "$PSScriptRoot\manual-source-record-slice.json",
  [string]$OutlookSlicePath = "$PSScriptRoot\outlook-source-reference-slice.json",
  [string]$Story13ExtractionPath = "$PSScriptRoot\proposed-work-item-extraction-slice.json",
  [string]$Story14ExtractionPath = "$PSScriptRoot\zero-multi-item-extraction-slice.json",
  [string]$Story15DriftPath = "$PSScriptRoot\source-drift-supersession-slice.json",
  [string]$Story22ApprovalPath = "$PSScriptRoot\approval-boundaries-slice.json",
  [string]$Story23StatePath = "$PSScriptRoot\receipt-backed-state-changes-slice.json",
  [string]$Story24IdempotentPath = "$PSScriptRoot\idempotent-mutations-slice.json",
  [string]$Story25AutoPath = "$PSScriptRoot\auto-creation-policy-slice.json",
  [string]$Story26FailurePath = "$PSScriptRoot\failure-policy-denial-slice.json",
  [string]$Story21ShellPath = "$PSScriptRoot\work-item-execution-shell-slice.json",
  [string]$Story31BriefPath = "$PSScriptRoot\minion-brief-slice.json",
  [string]$Story32DelegationPath = "$PSScriptRoot\delegation-support-slice.json",
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
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$Field,
    [Parameter(Mandatory = $true)][string]$Subject
  )

  if (-not ($Record.PSObject.Properties.Name -contains $Field)) {
    Add-Issue $Issues "$Subject must declare boolean field: $Field."
    return
  }
  if ($Record.$Field -isnot [bool] -or -not $Record.$Field) {
    Add-Issue $Issues "$Subject $Field must be strict boolean true, found: $($Record.$Field)."
  }
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
      Add-Issue $Issues "$Subject ${Field} must be ISO 8601 with an explicit UTC offset so draft ordering is not host-timezone dependent, found: $rawValue."
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
    Add-Issue $Issues "$Subject ${Field} must be ISO 8601 with an explicit UTC offset so draft ordering is not host-timezone dependent, found: $rawValue."
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
    Write-Host "Handoff drafts slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

foreach ($path in @($ManifestPath, $DraftSlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $Story15DriftPath, $Story22ApprovalPath, $Story23StatePath, $Story24IdempotentPath, $Story25AutoPath, $Story26FailurePath, $Story21ShellPath, $Story31BriefPath, $Story32DelegationPath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required handoff drafts validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$draft = Read-JsonInput -Path $DraftSlicePath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$story15Drift = Read-JsonInput -Path $Story15DriftPath
$story22Approval = Read-JsonInput -Path $Story22ApprovalPath
$story23State = Read-JsonInput -Path $Story23StatePath
$story24Idempotent = Read-JsonInput -Path $Story24IdempotentPath
$story25Auto = Read-JsonInput -Path $Story25AutoPath
$story26Failure = Read-JsonInput -Path $Story26FailurePath
$story21Shell = Read-JsonInput -Path $Story21ShellPath
$story31Brief = Read-JsonInput -Path $Story31BriefPath
$story32Delegation = Read-JsonInput -Path $Story32DelegationPath
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath
$rawSliceText = Get-Content -LiteralPath $DraftSlicePath -Raw
$issues = [System.Collections.Generic.List[string]]::new()

$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$evidenceRoles = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilreceiptsource" -ColumnName "com_evidence_role"

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_councilreceiptsource.com_evidence_role"; Values = $evidenceRoles }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

if ($receiptVerbs -notcontains "policy_denied") {
  Add-Issue $issues "Manifest com_receiptverb is missing the policy_denied verb required for the Story 2.6 failure vocabulary reuse."
}
if ($receiptVerbs -notcontains "approved") {
  Add-Issue $issues "Manifest com_receiptverb is missing the approved verb required for the approved-outbound scenario."
}
if ($receiptVerbs -notcontains "external_action_requested" -or $receiptVerbs -notcontains "external_action_completed") {
  Add-Issue $issues "Manifest com_receiptverb is missing external_action_requested/external_action_completed; the no-outbound-without-approval proof depends on their absence being meaningful."
}
if ($evidenceRoles -notcontains "approval") {
  Add-Issue $issues "Manifest com_councilreceiptsource.com_evidence_role is missing: approval."
}
if ($evidenceRoles -notcontains "failure_evidence") {
  Add-Issue $issues "Manifest com_councilreceiptsource.com_evidence_role is missing: failure_evidence."
}

if ($draft.storyKey -ne "3-3-prepare-internal-handoff-and-external-reply-drafts") {
  Add-Issue $issues "Draft slice storyKey must be 3-3-prepare-internal-handoff-and-external-reply-drafts."
}
if ([string]$draft.status -notmatch "^local-contract") {
  Add-Issue $issues "Draft slice status must declare local contract evidence, found: $($draft.status)."
}

foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "requiresExplicitHumanApprovalForExecution", "sourceRecordsRemainSeparate", "receiptsAreLocalContractEvidenceOnly", "noOutboundWithoutApproval", "draftsAreDraftOnlyUntilApproved", "approvalsAuthorizeOnlyDeclaredDraftScope", "receiptsAreAppendOnlyCorrectionsAreNewReceipts", "noWorkItemStateChangeInThisSlice")) {
  if (-not ($draft.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Draft slice must declare guard: $guard."
  }
}
if ($draft.guards.PSObject.Properties.Name -contains "noReceiptCreationInThisSlice") {
  Add-Issue $issues "Draft slice must not declare noReceiptCreationInThisSlice; draft/preparation/denial/approval receipts are the sanctioned Story 3.3 deliverable."
}
foreach ($guardProperty in @($draft.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Draft guard must be boolean true: $($guardProperty.Name)."
  }
}

# --- Load sibling-slice IDs for cross-slice collision and linkage checks -----------------

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

# Superseding CSR from Story 1.5 is also a valid prior source for linkage, but it is a drift-slice artifact;
# include it so a draft may legally link to it if needed (none do in this slice, but the loader stays general).
$story15SupersedingIds = @()
if ($null -ne $story15Drift.driftRun -and $null -ne $story15Drift.driftRun.supersessions) {
  foreach ($sup in @($story15Drift.driftRun.supersessions | Where-Object { $null -ne $_ })) {
    if ($null -ne $sup.supersedingRecord) {
      $sid = [string]$sup.supersedingRecord.com_council_source_record_id
      if (-not [string]::IsNullOrWhiteSpace($sid) -and -not $knownPriorSourceIds.Contains($sid)) {
        $story15SupersedingIds += $sid
        $priorSourcesById[$sid] = $sup.supersedingRecord
      }
    }
  }
}
$linkableSourceIds = @($knownPriorSourceIds + $story15SupersedingIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)

$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$knownWorkItems = @($story13Items + $story14Items)
$knownWorkItemIds = @($knownWorkItems | ForEach-Object { [string]$_.com_council_work_item_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

# Collect IDs created by sibling slices (CWI-LOCAL-*, CR-LOCAL-*, CSR-*, CWD-LOCAL-*) for cross-slice collision checks.
# Story hard rule: new CR-LOCAL-* ids unique across ALL slices, so the inventory spans every sibling slice on disk,
# including the Epic-3 siblings (minion-brief, delegation-support) — not just Epic-1/Epic-2.
$siblingSliceFiles = @(
  @{ Name = "manual-source-record-slice.json"; Text = (Get-Content -LiteralPath $ManualSlicePath -Raw) },
  @{ Name = "outlook-source-reference-slice.json"; Text = (Get-Content -LiteralPath $OutlookSlicePath -Raw) },
  @{ Name = "proposed-work-item-extraction-slice.json"; Text = (Get-Content -LiteralPath $Story13ExtractionPath -Raw) },
  @{ Name = "zero-multi-item-extraction-slice.json"; Text = (Get-Content -LiteralPath $Story14ExtractionPath -Raw) },
  @{ Name = "source-drift-supersession-slice.json"; Text = (Get-Content -LiteralPath $Story15DriftPath -Raw) },
  @{ Name = "approval-boundaries-slice.json"; Text = (Get-Content -LiteralPath $Story22ApprovalPath -Raw) },
  @{ Name = "receipt-backed-state-changes-slice.json"; Text = (Get-Content -LiteralPath $Story23StatePath -Raw) },
  @{ Name = "idempotent-mutations-slice.json"; Text = (Get-Content -LiteralPath $Story24IdempotentPath -Raw) },
  @{ Name = "auto-creation-policy-slice.json"; Text = (Get-Content -LiteralPath $Story25AutoPath -Raw) },
  @{ Name = "failure-policy-denial-slice.json"; Text = (Get-Content -LiteralPath $Story26FailurePath -Raw) },
  @{ Name = "work-item-execution-shell-slice.json"; Text = (Get-Content -LiteralPath $Story21ShellPath -Raw) },
  @{ Name = "minion-brief-slice.json"; Text = (Get-Content -LiteralPath $Story31BriefPath -Raw) },
  @{ Name = "delegation-support-slice.json"; Text = (Get-Content -LiteralPath $Story32DelegationPath -Raw) }
)
$siblingCwiIds = [System.Collections.Generic.HashSet[string]]::new()
$siblingCrIds = [System.Collections.Generic.HashSet[string]]::new()
$siblingCsrIds = [System.Collections.Generic.HashSet[string]]::new()
$siblingCwdIds = [System.Collections.Generic.HashSet[string]]::new()
$siblingRunIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($sibling in $siblingSliceFiles) {
  foreach ($m in [regex]::Matches($sibling.Text, 'CWI-LOCAL-[A-Z0-9-]+')) { [void]$siblingCwiIds.Add($m.Value) }
  foreach ($m in [regex]::Matches($sibling.Text, 'CR-LOCAL-[A-Z0-9-]+')) { [void]$siblingCrIds.Add($m.Value) }
  foreach ($m in [regex]::Matches($sibling.Text, 'CSR-[A-Z0-9-]+')) { [void]$siblingCsrIds.Add($m.Value) }
  foreach ($m in [regex]::Matches($sibling.Text, 'CWD-LOCAL-[A-Z0-9-]+')) { [void]$siblingCwdIds.Add($m.Value) }
  foreach ($m in [regex]::Matches($sibling.Text, '"runId"\s*:\s*"([^"]+)"')) { [void]$siblingRunIds.Add($m.Groups[1].Value) }
}
$demoReceiptIds = @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$demoWorkItemIds = @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

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
if ($linkableSourceIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be loaded from the Story 1.1/1.2/1.4/1.5 slices; draft linkage checks would silently no-op."
}
if ($knownWorkItemIds.Count -eq 0) {
  Add-Issue $issues "No Work Item IDs could be loaded from the Story 1.3/1.4 slices; draft linkage checks would silently no-op."
}
if ($siblingCwiIds.Count -eq 0 -or $siblingCrIds.Count -eq 0 -or $siblingCsrIds.Count -eq 0) {
  Add-Issue $issues "Sibling slice ID sets are empty; cross-slice id uniqueness checks would silently no-op."
}
if ($siblingRunIds.Count -eq 0) {
  Add-Issue $issues "No sibling runIds could be harvested from sibling slices; runId collision checks would silently no-op."
}
if ($demoReceiptIds.Count -eq 0) {
  Add-Issue $issues "No reserved receipt IDs could be loaded from state-transition-demo-evidence.json; receipt collision checks would silently no-op."
}

# --- Draft run block ---------------------------------------------------------------------------------

$run = $draft.draftRun
if ($null -eq $run) {
  Add-Issue $issues "Draft slice must carry a draftRun block."
  Write-Host "Handoff drafts slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Draft run must declare a runId."
}
elseif ($siblingRunIds.Contains([string]$run.runId)) {
  Add-Issue $issues "Draft run must use a new local runId, not a sibling-slice runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Draft run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Draft run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Draft run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "zero-multi-item-extraction-slice.json")) {
  if (@($run.inputSourceRecordsFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Draft run must reference $inputSlice as an input source slice."
  }
}
foreach ($inputSlice in @("proposed-work-item-extraction-slice.json", "zero-multi-item-extraction-slice.json")) {
  if (@($run.inputWorkItemsFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Draft run must reference $inputSlice as an input work-item slice."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Draft run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("draftsAreDraftOnlyUntilApproved", "noOutboundWithoutApproval", "approvalsAuthorizeOnlyDeclaredDraftScope", "unapprovedOutboundSendIsPolicyDenied", "approvalOfOneDraftDoesNotReleaseAnother", "liveExternalSendReceiptGatedToEpic2", "liveWorkItemStateChangeReceiptGatedToStory23", "receiptsAppendOnlyCorrectionsAreNewReceipts")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Draft run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Draft run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# --- Failure code vocabulary (reuses 2.6 shape) -------------------------------------------------------

$failureVocab = $run.failureCodeVocabulary
if ($null -eq $failureVocab) {
  Add-Issue $issues "Draft run must declare a failureCodeVocabulary block reusing the Story 2.6 failure code shape."
}
else {
  if (-not (Test-HasNonEmptyField -Record $failureVocab -Field "basis")) {
    Add-Issue $issues "Draft run failureCodeVocabulary must carry a non-empty basis explaining the 2.6 vocabulary reuse."
  }
  elseif ([string]$failureVocab.basis -notmatch "2\.6|Story 2\.6") {
    Add-Issue $issues "Draft run failureCodeVocabulary.basis must reference Story 2.6 as the reused vocabulary basis."
  }
  $codes = @($failureVocab.codes | Where-Object { $null -ne $_ })
  if ($codes.Count -eq 0) {
    Add-Issue $issues "Draft run failureCodeVocabulary must declare at least one code; outbound_send_without_approval is required."
  }
  $seenCodes = @{}
  foreach ($code in $codes) {
    $codeVal = [string]$code.code
    $subject = "Failure code $codeVal"
    if ([string]::IsNullOrWhiteSpace($codeVal)) {
      Add-Issue $issues "Draft failure code must declare a non-empty code."
      continue
    }
    if ($seenCodes.ContainsKey($codeVal)) {
      Add-Issue $issues "Duplicate draft failure code: $codeVal."
    }
    else {
      $seenCodes[$codeVal] = $true
    }
    foreach ($field in @("kind", "definition")) {
      if (-not (Test-HasNonEmptyField -Record $code -Field $field)) {
        Add-Issue $issues "$subject must carry a non-empty $field."
      }
    }
    if ($code.kind -ne "policy_denial") {
      Add-Issue $issues "$subject kind must be policy_denial for Story 3.3 outbound-without-approval denials, found: $($code.kind)."
    }
    if ($code.retryAllowed -isnot [bool]) {
      Add-Issue $issues "$subject retryAllowed must be strict boolean, found: $($code.retryAllowed)."
    }
    if ($code.humanReviewRequired -isnot [bool]) {
      Add-Issue $issues "$subject humanReviewRequired must be strict boolean, found: $($code.humanReviewRequired)."
    }
  }
  if (-not $seenCodes.ContainsKey("outbound_send_without_approval")) {
    Add-Issue $issues "Draft run failureCodeVocabulary must declare the code outbound_send_without_approval."
  }
  else {
    $obCode = $codes | Where-Object { [string]$_.code -eq "outbound_send_without_approval" } | Select-Object -First 1
    if ($obCode.kind -ne "policy_denial") {
      Add-Issue $issues "Failure code outbound_send_without_approval must be kind policy_denial, found: $($obCode.kind)."
    }
    if ($obCode.retryAllowed -isnot [bool] -or $obCode.retryAllowed) {
      Add-Issue $issues "Failure code outbound_send_without_approval must have retryAllowed=false (strict boolean)."
    }
    if ($obCode.humanReviewRequired -isnot [bool]) {
      Add-Issue $issues "Failure code outbound_send_without_approval humanReviewRequired must be strict boolean, found: $($obCode.humanReviewRequired)."
    }
  }
}

# --- Drafts -------------------------------------------------------------------------------------------

$drafts = @($run.drafts | Where-Object { $null -ne $_ })
if ($drafts.Count -lt 2) {
  Add-Issue $issues "Draft slice must include at least two drafts (one internal handoff and one external reply)."
}

$requiredDraftFields = @("draftId", "draftKind", "com_name", "linkedWorkItem", "linkedSourceRecord", "draftBodyRef", "draftOnly", "outboundApproved", "releasable", "draftPreparedReceipt", "rationale")

$seenDraftIds = @{}
$draftIds = [System.Collections.Generic.List[string]]::new()
$internalHandoffCount = 0
$externalReplyCount = 0
$approvedDraftCount = 0
$deniedDraftCount = 0
$approvedExternalReplyCount = 0
$deniedExternalReplyCount = 0

foreach ($dr in $drafts) {
  $draftId = [string]$dr.draftId
  $subject = "Draft $draftId"

  foreach ($field in $requiredDraftFields) {
    if (-not (Test-HasNonEmptyField -Record $dr -Field $field)) {
      Add-Issue $issues "$subject missing required field: $field."
    }
  }

  if ([string]::IsNullOrWhiteSpace($draftId)) {
    Add-Issue $issues "Draft must declare a draftId."
    continue
  }
  if (-not ($draftId -match "^CWD-LOCAL-")) {
    Add-Issue $issues "$subject must use Council draft CWD-LOCAL-* identity."
  }
  if ($seenDraftIds.ContainsKey($draftId)) {
    Add-Issue $issues "Duplicate draft ID in slice: $draftId."
  }
  else {
    $seenDraftIds[$draftId] = $true
  }
  $draftIds.Add($draftId) | Out-Null

  # Cross-slice id uniqueness: CWD-LOCAL-* is a fresh namespace; no sibling should already use these ids.
  if ($siblingCwdIds.Contains($draftId)) {
    Add-Issue $issues "$subject collides with a draft ID already used in a sibling slice."
  }
  if ($siblingCwiIds.Contains($draftId) -or $siblingCrIds.Contains($draftId) -or $siblingCsrIds.Contains($draftId)) {
    Add-Issue $issues "$subject collides with an existing CWI/CR/CSR id namespace in a sibling slice."
  }

  if ($dr.draftKind -eq "internal_handoff") {
    $internalHandoffCount += 1
  }
  elseif ($dr.draftKind -eq "external_reply") {
    $externalReplyCount += 1
  }
  else {
    Add-Issue $issues "$subject draftKind must be internal_handoff or external_reply, found: $($dr.draftKind)."
  }

  $linkedWorkItem = [string]$dr.linkedWorkItem
  if ([string]::IsNullOrWhiteSpace($linkedWorkItem)) {
    Add-Issue $issues "$subject must name a linkedWorkItem."
  }
  elseif ($knownWorkItemIds -notcontains $linkedWorkItem) {
    Add-Issue $issues "$subject linkedWorkItem must reference a sibling-slice CWI id, found: $linkedWorkItem."
  }

  $linkedSource = [string]$dr.linkedSourceRecord
  if ([string]::IsNullOrWhiteSpace($linkedSource)) {
    Add-Issue $issues "$subject must name a linkedSourceRecord."
  }
  elseif ($linkableSourceIds -notcontains $linkedSource) {
    Add-Issue $issues "$subject linkedSourceRecord must reference a sibling-slice CSR id, found: $linkedSource."
  }

  # Strict booleans on the draft-only / approval / releasable triad.
  Test-StrictBooleanTrue -Issues $issues -Record $dr -Field "draftOnly" -Subject $subject
  if ($dr.outboundApproved -isnot [bool]) {
    Add-Issue $issues "$subject outboundApproved must be strict boolean, found: $($dr.outboundApproved)."
  }
  if ($dr.releasable -isnot [bool]) {
    Add-Issue $issues "$subject releasable must be strict boolean, found: $($dr.releasable)."
  }

  # Mutual consistency: releasable requires outboundApproved AND an approval receipt scoping this draft.
  if ($dr.releasable -is [bool] -and $dr.releasable) {
    if (-not ($dr.outboundApproved -is [bool] -and $dr.outboundApproved)) {
      Add-Issue $issues "$subject releasable=true requires outboundApproved=true, found outboundApproved=$($dr.outboundApproved)."
    }
    if ([string]::IsNullOrWhiteSpace([string]$dr.approvalReceipt)) {
      Add-Issue $issues "$subject releasable=true requires a non-null approvalReceipt naming the approving receipt."
    }
    $approvedDraftCount += 1
    # AC3: only an external_reply draft may be released (the story approves an external reply send).
    if ($dr.draftKind -eq "external_reply") {
      $approvedExternalReplyCount += 1
    }
    else {
      Add-Issue $issues "$subject releasable=true requires draftKind external_reply (AC3 approves an outbound external reply), found: $($dr.draftKind)."
    }
  }
  else {
    # Unreleased draft: outboundApproved must be false and approvalReceipt must be null/empty.
    if ($dr.outboundApproved -is [bool] -and $dr.outboundApproved) {
      Add-Issue $issues "$subject outboundApproved=true is inconsistent with releasable=false; approval must mark the draft releasable."
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$dr.approvalReceipt)) {
      Add-Issue $issues "$subject must not carry an approvalReceipt while releasable=false; approval authorizes release."
    }
  }

  # draftOnly must stay true even when approved/releasable (draft-only is a hard boundary).
  if ($dr.draftOnly -is [bool] -and -not $dr.draftOnly) {
    Add-Issue $issues "$subject draftOnly must stay true even after approval; drafts are never sent in this slice."
  }

  if (-not [string]::IsNullOrWhiteSpace([string]$dr.denialReceipt)) {
    $deniedDraftCount += 1
    # AC2: the denied draft is an attempted external send, so it must be an external_reply.
    if ($dr.draftKind -eq "external_reply") {
      $deniedExternalReplyCount += 1
    }
    else {
      Add-Issue $issues "$subject carrying a denialReceipt requires draftKind external_reply (AC2 denies an attempted outbound send), found: $($dr.draftKind)."
    }
  }
}

if ($internalHandoffCount -lt 1) {
  Add-Issue $issues "Draft slice must include at least one internal_handoff draft (AC1)."
}
if ($externalReplyCount -lt 1) {
  Add-Issue $issues "Draft slice must include at least one external_reply draft (AC1)."
}
if ($approvedExternalReplyCount -lt 1) {
  Add-Issue $issues "Draft slice must include at least one approved/releasable external_reply draft (AC3)."
}
if ($deniedExternalReplyCount -lt 1) {
  Add-Issue $issues "Draft slice must include at least one external_reply draft carrying a denialReceipt (AC2 unapproved-outbound scenario)."
}

# At least one approved draft and at least one unreleased draft must coexist (approval authorizes ONLY that draft).
$unreleasedDraftCount = 0
foreach ($dr in $drafts) {
  if ($dr.releasable -isnot [bool] -or -not $dr.releasable) {
    $unreleasedDraftCount += 1
  }
}
if ($approvedDraftCount -ge 1 -and $unreleasedDraftCount -lt 1) {
  Add-Issue $issues "Approved-outbound scenario requires at least one other draft to stay unreleased (AC3: approval authorizes ONLY that draft)."
}

# --- Receipts -----------------------------------------------------------------------------------------

$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 5) {
  Add-Issue $issues "Draft slice must include at least five receipts (draft-create x3, denial, approval)."
}
$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique
$sliceReceiptIds = @{}
$seenIdempotencyKeys = @{}
$receiptById = @{}
foreach ($receipt in $receipts) {
  $receiptId = [string]$receipt.com_receipt_id
  $subject = "Receipt $receiptId"

  foreach ($field in $receiptRequiredFields) {
    if (-not (Test-HasNonEmptyField -Record $receipt -Field $field)) {
      Add-Issue $issues "$subject missing required manifest receipt field: $field."
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
      $receiptById[$receiptId] = $receipt
    }
    # Cross-slice uniqueness: no sibling slice (or demo reserved ids) may already use this CR-LOCAL-* id.
    if ($siblingCrIds.Contains($receiptId)) {
      Add-Issue $issues "$subject collides with a receipt ID already used in a sibling slice."
    }
    if ($demoReceiptIds -contains $receiptId) {
      Add-Issue $issues "$subject collides with a reserved state-transition-demo receipt ID."
    }
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

  # Local contract evidence only: no live-write marker fields.
  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 3.3 receipts are local contract evidence only."
    }
  }
  # No external_action_requested or external_action_completed receipts: drafts are never sent in this slice.
  if ($receipt.com_verb -eq "external_action_requested" -or $receipt.com_verb -eq "external_action_completed") {
    Add-Issue $issues "$subject must not use verb $($receipt.com_verb); drafts are never sent in this slice and the live send is deferred."
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write", "no_outbound_action")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 3.3 receipts are local contract evidence only."
      }
    }
  }
}

# Required receipt ids for the three ACs.
foreach ($expectedReceiptId in @("CR-LOCAL-HANDOFF-DRAFT-CREATED-001", "CR-LOCAL-REPLY-DRAFT-CREATED-001", "CR-LOCAL-REPLY-DRAFT-CREATED-002", "CR-LOCAL-OUTBOUND-DENIED-001", "CR-LOCAL-OUTBOUND-APPROVED-001")) {
  if (-not $sliceReceiptIds.ContainsKey($expectedReceiptId)) {
    Add-Issue $issues "Draft slice must include receipt $expectedReceiptId."
  }
}

# --- Denial receipt (AC2) reuses the 2.6 failure field set -------------------------------------------

$denialReceipt = $receiptById["CR-LOCAL-OUTBOUND-DENIED-001"]
if ($null -ne $denialReceipt) {
  $subject = "Receipt CR-LOCAL-OUTBOUND-DENIED-001"
  if ($denialReceipt.com_verb -ne "policy_denied") {
    Add-Issue $issues "$subject must use verb policy_denied for the unapproved-outbound denial, found: $($denialReceipt.com_verb)."
  }
  if ($denialReceipt.com_result -ne "rejected") {
    Add-Issue $issues "$subject must use result rejected for a policy denial, found: $($denialReceipt.com_result)."
  }
  # 2.6 failure field set.
  foreach ($field in @("attemptedAction", "com_failure_code", "retryAllowed", "humanReviewRequired")) {
    if (-not ($denialReceipt.PSObject.Properties.Name -contains $field)) {
      Add-Issue $issues "$subject must carry the Story 2.6 failure field: $field."
    }
    else {
      if ($field -eq "attemptedAction" -and -not (Test-HasNonEmptyField -Record $denialReceipt -Field $field)) {
        Add-Issue $issues "$subject attemptedAction must be non-empty."
      }
      if ($field -eq "com_failure_code" -and -not (Test-HasNonEmptyField -Record $denialReceipt -Field $field)) {
        Add-Issue $issues "$subject com_failure_code must be non-empty."
      }
      elseif ($field -eq "com_failure_code") {
        if (-not $seenCodes.ContainsKey([string]$denialReceipt.com_failure_code)) {
          Add-Issue $issues "$subject com_failure_code must be declared in failureCodeVocabulary.codes, found: $($denialReceipt.com_failure_code)."
        }
      }
      if ($field -eq "retryAllowed" -and $denialReceipt.retryAllowed -isnot [bool]) {
        Add-Issue $issues "$subject retryAllowed must be strict boolean, found: $($denialReceipt.retryAllowed)."
      }
      if ($field -eq "humanReviewRequired" -and $denialReceipt.humanReviewRequired -isnot [bool]) {
        Add-Issue $issues "$subject humanReviewRequired must be strict boolean, found: $($denialReceipt.humanReviewRequired)."
      }
    }
  }
  if ($denialReceipt.retryAllowed -is [bool] -and $denialReceipt.retryAllowed) {
    Add-Issue $issues "$subject retryAllowed must be false for a policy denial (non-retryable without a policy change or approval)."
  }
  if (-not (Test-HasNonEmptyField -Record $denialReceipt -Field "com_failure_code") -or [string]$denialReceipt.com_failure_code -ne "outbound_send_without_approval") {
    Add-Issue $issues "$subject com_failure_code must be outbound_send_without_approval, found: $($denialReceipt.com_failure_code)."
  }
  # Finding 6: the receipt's retryAllowed / humanReviewRequired must equal the values declared for
  # its failure code in failureCodeVocabulary (mirrors the Story 2.6 hardened binding). Otherwise the
  # vocabulary is free decoration and the slice can game its own dictionary on the review field.
  if ($null -ne $obCode) {
    if ($denialReceipt.retryAllowed -is [bool] -and $obCode.retryAllowed -is [bool] -and $denialReceipt.retryAllowed -ne $obCode.retryAllowed) {
      Add-Issue $issues "$subject retryAllowed ($($denialReceipt.retryAllowed)) must match the value declared for code 'outbound_send_without_approval' in failureCodeVocabulary ($($obCode.retryAllowed))."
    }
    if ($denialReceipt.humanReviewRequired -is [bool] -and $obCode.humanReviewRequired -is [bool] -and $denialReceipt.humanReviewRequired -ne $obCode.humanReviewRequired) {
      Add-Issue $issues "$subject humanReviewRequired ($($denialReceipt.humanReviewRequired)) must match the value declared for code 'outbound_send_without_approval' in failureCodeVocabulary ($($obCode.humanReviewRequired))."
    }
  }
  if ([string]$denialReceipt.com_policy_flags -notmatch "policy_denied") {
    Add-Issue $issues "$subject com_policy_flags must declare policy_denied."
  }
}

# --- Approval receipts (AC3) scope names exactly one draft id ----------------------------------------
# Finding 1: the scope discipline is applied to EVERY approval receipt (com_verb=approved), not only a
# hard-coded id. A second half-valid approval cannot independently release other drafts because every
# releasable draft is bound to a fully-scoped approval whose approvedDraftId names it (global invariant).

$approvalReceipts = @($receipts | Where-Object { $_.com_verb -eq "approved" })
if ($approvalReceipts.Count -lt 1) {
  Add-Issue $issues "Draft slice must include at least one approved (com_verb=approved) receipt (AC3 approved-outbound scenario)."
}
$approvalScopedDraftIds = @{}
foreach ($apprReceipt in $approvalReceipts) {
  $apprId = [string]$apprReceipt.com_receipt_id
  $subject = "Receipt $apprId"
  if ($apprReceipt.com_actor_type -ne "human") {
    Add-Issue $issues "$subject actor type must be human (Doug) for an approval, found: $($apprReceipt.com_actor_type)."
  }
  if (-not (Test-HasNonEmptyField -Record $apprReceipt -Field "approvedScope")) {
    Add-Issue $issues "$subject must carry a non-empty approvedScope naming the one draft this approval authorizes."
  }
  if (-not (Test-HasNonEmptyField -Record $apprReceipt -Field "approvedDraftId")) {
    Add-Issue $issues "$subject must carry a non-empty approvedDraftId naming the one draft this approval authorizes."
  }
  else {
    $approvedDraftId = [string]$apprReceipt.approvedDraftId
    if (-not $seenDraftIds.ContainsKey($approvedDraftId)) {
      Add-Issue $issues "$subject approvedDraftId must reference a draft in this slice, found: $approvedDraftId."
    }
    $approvedDraft = $drafts | Where-Object { [string]$_.draftId -eq $approvedDraftId } | Select-Object -First 1
    if ($null -ne $approvedDraft) {
      if ($approvedDraft.draftKind -ne "external_reply") {
        Add-Issue $issues "$subject approvedDraftId ($approvedDraftId) must be an external_reply draft (AC3 approves an outbound external reply), found: $($approvedDraft.draftKind)."
      }
      if (-not ($approvedDraft.outboundApproved -is [bool] -and $approvedDraft.outboundApproved)) {
        Add-Issue $issues "Draft $approvedDraftId must have outboundApproved=true after approval receipt $apprId."
      }
      if (-not ($approvedDraft.releasable -is [bool] -and $approvedDraft.releasable)) {
        Add-Issue $issues "Draft $approvedDraftId must have releasable=true after approval receipt $apprId."
      }
      if ([string]$approvedDraft.approvalReceipt -ne $apprId) {
        Add-Issue $issues "Draft $approvedDraftId approvalReceipt must name $apprId, found: $($approvedDraft.approvalReceipt)."
      }
      # approvedDraftId must appear in the approvedScope text (scope names that draft id).
      if (Test-HasNonEmptyField -Record $apprReceipt -Field "approvedScope") {
        if ([string]$apprReceipt.approvedScope -notmatch [regex]::Escape($approvedDraftId)) {
          Add-Issue $issues "$subject approvedScope must name the approved draft id $approvedDraftId within its text."
        }
      }
    }
    if ($approvalScopedDraftIds.ContainsKey($approvedDraftId)) {
      Add-Issue $issues "$subject approvedDraftId ($approvedDraftId) is already scoped by another approval receipt ($($approvalScopedDraftIds[$approvedDraftId])); an approval must authorize exactly one draft and no two approvals may scope the same draft."
    }
    else {
      $approvalScopedDraftIds[$approvedDraftId] = $apprId
    }
  }
  if (@($apprReceipt.outOfScopeDraftIds | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -lt 1) {
    Add-Issue $issues "$subject must list at least one outOfScopeDraftIds entry proving approval authorizes ONLY that draft."
  }
  else {
    foreach ($outId in @($apprReceipt.outOfScopeDraftIds | Where-Object { $null -ne $_ })) {
      $outIdStr = [string]$outId
      if (-not $seenDraftIds.ContainsKey($outIdStr)) {
        Add-Issue $issues "$subject outOfScopeDraftIds must reference a draft in this slice, found: $outIdStr."
      }
      $outDraft = $drafts | Where-Object { [string]$_.draftId -eq $outIdStr } | Select-Object -First 1
      if ($null -ne $outDraft) {
        if ($outDraft.releasable -is [bool] -and $outDraft.releasable) {
          Add-Issue $issues "Out-of-scope draft $outIdStr must remain unreleased (releasable=false) after approval of $($apprReceipt.approvedDraftId)."
        }
        if ($outDraft.outboundApproved -is [bool] -and $outDraft.outboundApproved) {
          Add-Issue $issues "Out-of-scope draft $outIdStr must stay outboundApproved=false after approval of $($apprReceipt.approvedDraftId)."
        }
      }
    }
    # The approved draft must NOT appear in the out-of-scope list.
    if (@($apprReceipt.outOfScopeDraftIds | Where-Object { [string]$_ -eq [string]$apprReceipt.approvedDraftId }).Count -gt 0) {
      Add-Issue $issues "$subject approvedDraftId must not also appear in outOfScopeDraftIds."
    }
  }
}

# Global invariant (Finding 1): every releasable draft must be authorized by a fully-scoped approval
# receipt whose approvedDraftId names it. No releasable draft may escape the scope discipline.
foreach ($dr in $drafts) {
  if ($dr.releasable -is [bool] -and $dr.releasable) {
    if (-not $approvalScopedDraftIds.ContainsKey([string]$dr.draftId)) {
      Add-Issue $issues "Releasable draft $($dr.draftId) must be bound to a fully-scoped approval receipt (approvedDraftId=$($dr.draftId)); a releasable draft may not escape AC3 scope discipline."
    }
  }
}

# --- Draft-prepared receipt back-references ------------------------------------------------------------

foreach ($dr in $drafts) {
  $draftId = [string]$dr.draftId
  $subject = "Draft $draftId"
  $preparedId = [string]$dr.draftPreparedReceipt
  if ([string]::IsNullOrWhiteSpace($preparedId)) {
    Add-Issue $issues "$subject must name a draftPreparedReceipt."
  }
  elseif (-not $sliceReceiptIds.ContainsKey($preparedId)) {
    Add-Issue $issues "$subject draftPreparedReceipt references an unknown receipt: $preparedId."
  }
  else {
    $preparedReceipt = $receiptById[$preparedId]
    if ($preparedReceipt.com_verb -ne "proposed") {
      Add-Issue $issues "$subject draftPreparedReceipt ($preparedId) must use verb proposed for draft preparation, found: $($preparedReceipt.com_verb)."
    }
    if ($preparedReceipt.com_result -ne "accepted") {
      Add-Issue $issues "$subject draftPreparedReceipt ($preparedId) must use result accepted, found: $($preparedReceipt.com_result)."
    }
    # The prepared receipt's after-state must name this draft id (receipt binds to its draft).
    if (Test-HasNonEmptyField -Record $preparedReceipt -Field "com_after_state") {
      if ([string]$preparedReceipt.com_after_state -notmatch [regex]::Escape($draftId)) {
        Add-Issue $issues "$subject draftPreparedReceipt ($preparedId) com_after_state must name the draft id $draftId."
      }
    }
  }

  if (-not [string]::IsNullOrWhiteSpace([string]$dr.approvalReceipt)) {
    $apprId = [string]$dr.approvalReceipt
    if (-not $sliceReceiptIds.ContainsKey($apprId)) {
      Add-Issue $issues "$subject approvalReceipt references an unknown receipt: $apprId."
    }
    else {
      $apprReceipt = $receiptById[$apprId]
      if ($apprReceipt.com_verb -ne "approved") {
        Add-Issue $issues "$subject approvalReceipt ($apprId) must use verb approved, found: $($apprReceipt.com_verb)."
      }
      if ($apprReceipt.PSObject.Properties.Name -contains "approvedDraftId" -and [string]$apprReceipt.approvedDraftId -ne $draftId) {
        Add-Issue $issues "$subject approvalReceipt ($apprId) approvedDraftId must name this draft, found: $($apprReceipt.approvedDraftId)."
      }
    }
  }

  if (-not [string]::IsNullOrWhiteSpace([string]$dr.denialReceipt)) {
    $denId = [string]$dr.denialReceipt
    if (-not $sliceReceiptIds.ContainsKey($denId)) {
      Add-Issue $issues "$subject denialReceipt references an unknown receipt: $denId."
    }
    else {
      $denReceipt = $receiptById[$denId]
      if ($denReceipt.com_verb -ne "policy_denied") {
        Add-Issue $issues "$subject denialReceipt ($denId) must use verb policy_denied, found: $($denReceipt.com_verb)."
      }
    }
  }
}

# --- Receipt source links -----------------------------------------------------------------------------

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
  $linkSourceId = [string]$link.com_source_record
  if ([string]::IsNullOrWhiteSpace($linkSourceId) -or $linkableSourceIds -notcontains $linkSourceId) {
    Add-Issue $issues "$linkSubject must bind a sibling-slice Source Record, found: $linkSourceId."
  }
  if ($evidenceRoles -notcontains $link.com_evidence_role) {
    Add-Issue $issues "$linkSubject evidence role is not in manifest vocabulary: $($link.com_evidence_role)."
  }
}
foreach ($receiptId in @($sliceReceiptIds.Keys)) {
  if (@($links | Where-Object { $_.com_receipt -eq $receiptId }).Count -lt 1) {
    Add-Issue $issues "Receipt $receiptId must be bound to its source evidence by at least one receipt source link."
  }
}
# Denial receipt must bind to failure_evidence role; approval receipt must bind to approval role.
if ($null -ne $receiptById["CR-LOCAL-OUTBOUND-DENIED-001"]) {
  $denialLinks = @($links | Where-Object { $_.com_receipt -eq "CR-LOCAL-OUTBOUND-DENIED-001" })
  if ($denialLinks.Count -lt 1 -or @($denialLinks | Where-Object { $_.com_evidence_role -eq "failure_evidence" }).Count -lt 1) {
    Add-Issue $issues "Receipt CR-LOCAL-OUTBOUND-DENIED-001 must be bound to its source by a failure_evidence receipt source link."
  }
}
if ($null -ne $receiptById["CR-LOCAL-OUTBOUND-APPROVED-001"]) {
  $apprLinks = @($links | Where-Object { $_.com_receipt -eq "CR-LOCAL-OUTBOUND-APPROVED-001" })
  if ($apprLinks.Count -lt 1 -or @($apprLinks | Where-Object { $_.com_evidence_role -eq "approval" }).Count -lt 1) {
    Add-Issue $issues "Receipt CR-LOCAL-OUTBOUND-APPROVED-001 must be bound to its source by an approval receipt source link."
  }
}
# Draft-prepared receipts must bind to the supporting role (preparation is not approval evidence).
foreach ($preparedId in @("CR-LOCAL-HANDOFF-DRAFT-CREATED-001", "CR-LOCAL-REPLY-DRAFT-CREATED-001", "CR-LOCAL-REPLY-DRAFT-CREATED-002")) {
  if ($sliceReceiptIds.ContainsKey($preparedId)) {
    $preparedLinks = @($links | Where-Object { $_.com_receipt -eq $preparedId })
    if ($preparedLinks.Count -lt 1 -or @($preparedLinks | Where-Object { $_.com_evidence_role -eq "supporting" }).Count -lt 1) {
      Add-Issue $issues "Receipt $preparedId must be bound to its source by a supporting receipt source link."
    }
  }
}

# --- Outbound denials (AC2) --------------------------------------------------------------------------

$outboundDenials = @($run.outboundDenials | Where-Object { $null -ne $_ })
if ($outboundDenials.Count -lt 1) {
  Add-Issue $issues "Draft slice must include at least one outboundDenials entry (AC2 unapproved-outbound scenario)."
}
$denialByReceiptDraft = @{}
foreach ($denial in $outboundDenials) {
  $subject = "Outbound denial $($denial.receipt)"
  if (-not (Test-HasNonEmptyField -Record $denial -Field "receipt") -or -not $sliceReceiptIds.ContainsKey([string]$denial.receipt)) {
    Add-Issue $issues "$subject must name a slice receipt."
    continue
  }
  $denReceipt = $receiptById[[string]$denial.receipt]
  if ($denReceipt.com_verb -ne "policy_denied") {
    Add-Issue $issues "$subject must reference a policy_denied receipt, found verb: $($denReceipt.com_verb)."
  }
  if (-not (Test-HasNonEmptyField -Record $denial -Field "deniedDraft") -or -not $seenDraftIds.ContainsKey([string]$denial.deniedDraft)) {
    Add-Issue $issues "$subject must name a draft in this slice (deniedDraft)."
  }
  else {
    $deniedDraftObj = $drafts | Where-Object { [string]$_.draftId -eq [string]$denial.deniedDraft } | Select-Object -First 1
    if ($null -ne $deniedDraftObj) {
      # Finding 4: the denied draft is an attempted external send, so it must be an external_reply.
      if ($deniedDraftObj.draftKind -ne "external_reply") {
        Add-Issue $issues "$subject deniedDraft must be an external_reply draft (AC2 denies an attempted outbound send), found: $($deniedDraftObj.draftKind)."
      }
      if ($deniedDraftObj.outboundApproved -is [bool] -and $deniedDraftObj.outboundApproved) {
        Add-Issue $issues "$subject deniedDraft must have outboundApproved=false, found true."
      }
      if ($deniedDraftObj.releasable -is [bool] -and $deniedDraftObj.releasable) {
        Add-Issue $issues "$subject deniedDraft must have releasable=false, found true."
      }
      # Finding 3: join the denial graph — the draft carrying the denialReceipt pointer must be the
      # same draft this outboundDenials entry describes, and must point back at this denial receipt.
      if ([string]$deniedDraftObj.denialReceipt -ne [string]$denial.receipt) {
        Add-Issue $issues "$subject deniedDraft ($($denial.deniedDraft)) denialReceipt must name this denial's receipt ($($denial.receipt)), found: $($deniedDraftObj.denialReceipt); the denial graph must be joined."
      }
      # The denial receipt's attemptedAction must name the denied draft (receipt binds to its subject).
      if (Test-HasNonEmptyField -Record $denReceipt -Field "attemptedAction") {
        if ([string]$denReceipt.attemptedAction -notmatch [regex]::Escape([string]$denial.deniedDraft)) {
          Add-Issue $issues "$subject denial receipt attemptedAction must name the denied draft $($denial.deniedDraft)."
        }
      }
      # Finding 2: demote the self-asserting booleans to consequences of structural facts. The slice's
      # declared booleans must equal the values derived from the draft's actual flags, not free assertions.
      if ($denial.noOutboundWithoutApproval -isnot [bool]) {
        Add-Issue $issues "$subject noOutboundWithoutApproval must be strict boolean, found: $($denial.noOutboundWithoutApproval)."
      }
      elseif ($denial.noOutboundWithoutApproval -ne ($deniedDraftObj.outboundApproved -isnot [bool] -or -not $deniedDraftObj.outboundApproved)) {
        Add-Issue $issues "$subject noOutboundWithoutApproval ($($denial.noOutboundWithoutApproval)) must equal (deniedDraft.outboundApproved==false), derived from the draft's actual flag."
      }
      if ($denial.draftRemainsDraftOnly -isnot [bool]) {
        Add-Issue $issues "$subject draftRemainsDraftOnly must be strict boolean, found: $($denial.draftRemainsDraftOnly)."
      }
      elseif ($denial.draftRemainsDraftOnly -ne ($deniedDraftObj.draftOnly -is [bool] -and $deniedDraftObj.draftOnly)) {
        Add-Issue $issues "$subject draftRemainsDraftOnly ($($denial.draftRemainsDraftOnly)) must equal (deniedDraft.draftOnly==true), derived from the draft's actual flag."
      }
    }
    $denialByReceiptDraft["$($denial.receipt)|$($denial.deniedDraft)"] = $true
  }
  # Finding 2: outboundOccurred is structurally false because the slice emits no external_action receipts
  # at all (the global verb ban tripwire below). The boolean is a decoration of that structural fact.
  if ($denial.outboundOccurred -isnot [bool] -or $denial.outboundOccurred) {
    Add-Issue $issues "$subject outboundOccurred must be strict boolean false; no outbound action occurred in this slice."
  }
}
# Finding 3: bidirectional denial-graph join — every draft carrying a denialReceipt must have a matching
# outboundDenials entry (receipt + deniedDraft) describing that same draft, and vice-versa.
foreach ($dr in $drafts) {
  $denId = [string]$dr.denialReceipt
  if (-not [string]::IsNullOrWhiteSpace($denId)) {
    $key = "$denId|$([string]$dr.draftId)"
    if (-not $denialByReceiptDraft.ContainsKey($key)) {
      Add-Issue $issues "Draft $($dr.draftId) carries denialReceipt $denId but no outboundDenials entry joins it (receipt=$denId, deniedDraft=$($dr.draftId)); the denial graph is not joined."
    }
  }
}

# --- Approved outbound scopes (AC3) ------------------------------------------------------------------

$approvedScopes = @($run.approvedOutboundScopes | Where-Object { $null -ne $_ })
if ($approvedScopes.Count -lt 1) {
  Add-Issue $issues "Draft slice must include at least one approvedOutboundScopes entry (AC3 approved-outbound scenario)."
}
# Finding 1: every fully-scoped approval receipt must have exactly one approvedOutboundScopes entry, and
# vice-versa — the scope trace is bound to a real approval, not a free-floating declaration.
$scopeReceiptIds = @{}
foreach ($scope in $approvedScopes) {
  $subject = "Approved outbound scope $($scope.receipt)"
  if (-not (Test-HasNonEmptyField -Record $scope -Field "receipt") -or -not $sliceReceiptIds.ContainsKey([string]$scope.receipt)) {
    Add-Issue $issues "$subject must name a slice receipt."
    continue
  }
  $scopeReceiptIds[[string]$scope.receipt] = $true
  $apprReceipt = $receiptById[[string]$scope.receipt]
  if ($apprReceipt.com_verb -ne "approved") {
    Add-Issue $issues "$subject must reference an approved receipt, found verb: $($apprReceipt.com_verb)."
  }
  if (-not (Test-HasNonEmptyField -Record $scope -Field "approvedDraft") -or -not $seenDraftIds.ContainsKey([string]$scope.approvedDraft)) {
    Add-Issue $issues "$subject must name a draft in this slice (approvedDraft)."
  }
  else {
    $approvedDraftObj = $drafts | Where-Object { [string]$_.draftId -eq [string]$scope.approvedDraft } | Select-Object -First 1
    if ($null -ne $approvedDraftObj) {
      if ($approvedDraftObj.draftKind -ne "external_reply") {
        Add-Issue $issues "$subject approvedDraft must be an external_reply draft (AC3), found: $($approvedDraftObj.draftKind)."
      }
      if (-not ($approvedDraftObj.outboundApproved -is [bool] -and $approvedDraftObj.outboundApproved)) {
        Add-Issue $issues "$subject approvedDraft must have outboundApproved=true."
      }
      if (-not ($approvedDraftObj.releasable -is [bool] -and $approvedDraftObj.releasable)) {
        Add-Issue $issues "$subject approvedDraft must have releasable=true."
      }
    }
    # The scope's approvedDraft must equal the approval receipt's approvedDraftId (scope trace is bound to the receipt).
    if ((Test-HasNonEmptyField -Record $apprReceipt -Field "approvedDraftId") -and [string]$apprReceipt.approvedDraftId -ne [string]$scope.approvedDraft) {
      Add-Issue $issues "$subject approvedDraft ($($scope.approvedDraft)) must equal the approval receipt's approvedDraftId ($($apprReceipt.approvedDraftId))."
    }
  }
  $releasedIds = @($scope.releasedDraftIds | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
  $unreleasedIds = @($scope.unreleasedDraftIds | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
  if ($releasedIds.Count -ne 1) {
    Add-Issue $issues "$subject releasedDraftIds must list exactly one draft (the approved one), found $($releasedIds.Count)."
  }
  elseif ($releasedIds[0] -ne [string]$scope.approvedDraft) {
    Add-Issue $issues "$subject releasedDraftIds must equal the approvedDraft, found: $($releasedIds[0])."
  }
  if ($unreleasedIds.Count -lt 1) {
    Add-Issue $issues "$subject unreleasedDraftIds must list at least one other draft that stays unreleased (AC3: approval authorizes ONLY that draft)."
  }
  # The released draft must NOT also appear in the unreleased list (a draft cannot be both released and held).
  if (($releasedIds | Where-Object { $unreleasedIds -contains $_ }).Count -gt 0) {
    Add-Issue $issues "$subject releasedDraftIds and unreleasedDraftIds must be disjoint; a draft cannot be both released and unreleased under one approval."
  }
  foreach ($uId in $unreleasedIds) {
    if (-not $seenDraftIds.ContainsKey($uId)) {
      Add-Issue $issues "$subject unreleasedDraftIds must reference drafts in this slice, found: $uId."
      continue
    }
    $uDraft = $drafts | Where-Object { [string]$_.draftId -eq $uId } | Select-Object -First 1
    if ($null -ne $uDraft) {
      if ($uDraft.releasable -is [bool] -and $uDraft.releasable) {
        Add-Issue $issues "$subject unreleasedDraft $uId must have releasable=false."
      }
      if ($uDraft.outboundApproved -is [bool] -and $uDraft.outboundApproved) {
        Add-Issue $issues "$subject unreleasedDraft $uId must have outboundApproved=false; approval authorizes ONLY the approved draft."
      }
    }
  }
  if ($scope.outboundOccurred -isnot [bool] -or $scope.outboundOccurred) {
    Add-Issue $issues "$subject outboundOccurred must be strict boolean false; the live send is deferred."
  }
  Test-StrictBooleanTrue -Issues $issues -Record $scope -Field "liveSendDeferredToEpic2" -Subject $subject
}
# Bidirectional bind: every approval receipt has exactly one scope entry and every scope entry references an approval receipt.
foreach ($apprReceipt in $approvalReceipts) {
  $apprId = [string]$apprReceipt.com_receipt_id
  if (-not $scopeReceiptIds.ContainsKey($apprId)) {
    Add-Issue $issues "Approval receipt $apprId must have a matching approvedOutboundScopes entry; the scope trace is not optional."
  }
}

# --- No-outbound-without-approval proof (AC2 guard) --------------------------------------------------
# Finding 2: the per-draft `value:true` booleans and free-text proof must be decorations of structural
# negative evidence, not self-assertions. The structural fact is that the slice emits ZERO external_action
# receipts (verified by the global verb ban tripwire below and re-derived here per draft). Each proof's
# `value` must equal the structurally-derived value, and the proof text must be consistent with the
# draft's actual approval/denial state (not just name the banned verbs).

$extActionReceipts = @($receipts | Where-Object { $_.com_verb -eq "external_action_requested" -or $_.com_verb -eq "external_action_completed" })
$noOutboundProof = @($run.noOutboundWithoutApprovalProof | Where-Object { $null -ne $_ })
if ($noOutboundProof.Count -lt $drafts.Count) {
  Add-Issue $issues "noOutboundWithoutApprovalProof must bind every draft to a guard entry; found $($noOutboundProof.Count) for $($drafts.Count) drafts."
}
$proofDraftIds = @{}
foreach ($proof in $noOutboundProof) {
  $proofDraftId = [string]$proof.draft
  $subject = "No-outbound-without-approval proof $proofDraftId"
  if ([string]::IsNullOrWhiteSpace($proofDraftId) -or -not $seenDraftIds.ContainsKey($proofDraftId)) {
    Add-Issue $issues "$subject must reference a draft in this slice."
    continue
  }
  if ($proofDraftIds.ContainsKey($proofDraftId)) {
    Add-Issue $issues "Duplicate no-outbound-without-approval proof for draft: $proofDraftId."
  }
  else {
    $proofDraftIds[$proofDraftId] = $true
  }
  if ($proof.guard -ne "noOutboundWithoutApproval") {
    Add-Issue $issues "$subject guard must be noOutboundWithoutApproval, found: $($proof.guard)."
  }
  # Derive the expected value from structure: no external_action receipt in the slice may reference this draft.
  $proofDraft = $drafts | Where-Object { [string]$_.draftId -eq $proofDraftId } | Select-Object -First 1
  $refsThisDraft = @($extActionReceipts | Where-Object {
    ([string]$_.com_evidence_refs -match [regex]::Escape($proofDraftId)) -or
    ([string]$_.attemptedAction -match [regex]::Escape($proofDraftId)) -or
    ([string]$_.com_after_state -match [regex]::Escape($proofDraftId))
  })
  $derivedValue = ($refsThisDraft.Count -eq 0)
  if ($proof.value -isnot [bool]) {
    Add-Issue $issues "$subject value must be strict boolean, found: $($proof.value)."
  }
  elseif ($proof.value -ne $derivedValue) {
    Add-Issue $issues "$subject value ($($proof.value)) must equal the structurally-derived value ($($derivedValue): no external_action receipt references this draft); the guard boolean is a decoration of the structural negative evidence, not a self-assertion."
  }
  if (-not (Test-HasNonEmptyField -Record $proof -Field "proof")) {
    Add-Issue $issues "$subject must carry a non-empty proof rationale."
  }
  else {
    # The proof must mention the absence of external_action_requested / external_action_completed receipts.
    if ([string]$proof.proof -notmatch "external_action_requested|external_action_completed") {
      Add-Issue $issues "$subject proof must cite the absence of external_action_requested/external_action_completed receipts as the negative evidence."
    }
    # The proof text must be consistent with the draft's actual state (not a free assertion).
    if ($null -ne $proofDraft) {
      if (($proofDraft.releasable -is [bool] -and $proofDraft.releasable) -and -not [string]::IsNullOrWhiteSpace([string]$proofDraft.approvalReceipt)) {
        if ([string]$proof.proof -notmatch [regex]::Escape([string]$proofDraft.approvalReceipt)) {
          Add-Issue $issues "$subject proof must reference the draft's approval receipt ($($proofDraft.approvalReceipt)) since the draft is releasable; the proof must be consistent with the draft's actual approval state."
        }
      }
      elseif (-not [string]::IsNullOrWhiteSpace([string]$proofDraft.denialReceipt)) {
        if ([string]$proof.proof -notmatch [regex]::Escape([string]$proofDraft.denialReceipt)) {
          Add-Issue $issues "$subject proof must reference the draft's denial receipt ($($proofDraft.denialReceipt)) since the draft was denied; the proof must be consistent with the draft's actual denial state."
        }
      }
      else {
        # Unapproved, not denied: the proof must state the draft is unapproved (outboundApproved=false).
        if ([string]$proof.proof -notmatch "outboundApproved\s*=\s*false|unapproved|outboundApproved false") {
          Add-Issue $issues "$subject proof must state that the draft is outboundApproved=false (unapproved, not denied); the proof must be consistent with the draft's actual unapproved state."
        }
      }
    }
  }
}
foreach ($draftId in @($draftIds)) {
  if (-not $proofDraftIds.ContainsKey($draftId)) {
    Add-Issue $issues "Draft $draftId must be covered by a noOutboundWithoutApprovalProof entry."
  }
}
# Hard tripwire: no receipt in this slice may use external_action_requested or external_action_completed.
$extActionReceipts = @($receipts | Where-Object { $_.com_verb -eq "external_action_requested" -or $_.com_verb -eq "external_action_completed" })
if ($extActionReceipts.Count -gt 0) {
  Add-Issue $issues "Slice must contain NO external_action_requested/external_action_completed receipts; drafts are never sent in this slice. Found: $(($extActionReceipts | ForEach-Object { $_.com_receipt_id }) -join ', ')."
}

# --- Deferred outbound actions & work-item state changes ---------------------------------------------

$deferredOutbound = @($run.deferredOutboundActions | Where-Object { $null -ne $_ })
if ($deferredOutbound.Count -lt 1) {
  Add-Issue $issues "Draft slice must declare at least one deferredOutboundActions entry; the live send is receipt-gated."
}
foreach ($deferred in $deferredOutbound) {
  $subject = "Deferred outbound action $($deferred.draft)"
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "draft") -or -not $seenDraftIds.ContainsKey([string]$deferred.draft)) {
    Add-Issue $issues "$subject must name a draft in this slice."
    continue
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredAction")) {
    Add-Issue $issues "$subject must carry a non-empty deferredAction."
  }
  elseif ([string]$deferred.deferredAction -notmatch "receipt") {
    Add-Issue $issues "$subject deferredAction must state that the live send/mutation is receipt-gated."
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "receiptGatedTo")) {
    Add-Issue $issues "$subject must declare receiptGatedTo."
  }
}
# The approved (releasable) draft must have a deferred entry proving the live send is not executed here.
foreach ($dr in $drafts) {
  if ($dr.releasable -is [bool] -and $dr.releasable) {
    $hasDeferred = $deferredOutbound | Where-Object { [string]$_.draft -eq [string]$dr.draftId }
    if (-not $hasDeferred -or -not (Test-HasNonEmptyField -Record $hasDeferred -Field "deferredAction")) {
      Add-Issue $issues "Approved/releasable draft $($dr.draftId) must have a deferredOutboundActions entry proving the live send is not executed in this slice."
    }
  }
}

$workItemStateDeferred = @($run.workItemStateChangesDeferred | Where-Object { $null -ne $_ })
$knownDeferredWorkItemIds = @()
foreach ($deferred in $workItemStateDeferred) {
  $wId = [string]$deferred.workItem
  $subject = "Deferred Work Item state change $wId"
  if ([string]::IsNullOrWhiteSpace($wId)) {
    Add-Issue $issues "$subject must name its workItem."
    continue
  }
  $knownDeferredWorkItemIds += $wId
  if ($knownWorkItemIds -notcontains $wId) {
    Add-Issue $issues "$subject references an unknown Work Item: $wId."
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "$subject must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "$subject deferredUpdate must state that any state move is receipt-gated."
  }
}
# Every Work Item linked from a draft must have a deferred state-change entry.
foreach ($dr in $drafts) {
  $linkedWId = [string]$dr.linkedWorkItem
  if (-not [string]::IsNullOrWhiteSpace($linkedWId) -and $knownWorkItemIds -contains $linkedWId) {
    if ($knownDeferredWorkItemIds -notcontains $linkedWId) {
      Add-Issue $issues "Work Item $linkedWId linked by draft $($dr.draftId) must have a workItemStateChangesDeferred entry; state moves are receipt-gated."
    }
  }
}

# --- Acceptance mapping -------------------------------------------------------------------------------
# Finding 9: a non-whitespace string was enough to rubber-stamp AC coverage. Bind each localEvidence
# string to the actual slice graph: it must contain at least one resolvable identifier (a slice receipt
# id, a known prior Source Record id, or a known prior Work Item id) OR a dotted path into a real slice
# property. Bare assertions with no anchor fail.

$validSlicePathTokens = @(
  "draftRun.drafts", "draftRun.receipts", "draftRun.receiptSourceLinks", "draftRun.outboundDenials",
  "draftRun.approvedOutboundScopes", "draftRun.noOutboundWithoutApprovalProof", "draftRun.deferredOutboundActions",
  "draftRun.workItemStateChangesDeferred", "draftRun.failureCodeVocabulary", "draftRun.decisionPolicy",
  "draftRun.inputSourceRecordsFrom", "draftRun.inputWorkItemsFrom", "guards.", "acceptanceMapping.",
  "drafts", "receipts", "receiptSourceLinks", "outboundDenials", "approvedOutboundScopes",
  "noOutboundWithoutApprovalProof", "deferredOutboundActions", "workItemStateChangesDeferred",
  "failureCodeVocabulary", "decisionPolicy"
)
foreach ($criterion in @(1, 2, 3)) {
  $mapping = @($draft.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
  if (-not $mapping) {
    Add-Issue $issues "Missing acceptance mapping for AC $criterion."
    continue
  }
  $evidenceStrings = @($mapping.localEvidence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($evidenceStrings.Count -lt 1) {
    Add-Issue $issues "Acceptance mapping for AC $criterion must list non-empty localEvidence."
  }
  if (-not (Test-HasNonEmptyField -Record $mapping -Field "tenantEvidenceRequired")) {
    Add-Issue $issues "Acceptance mapping for AC $criterion must state tenantEvidenceRequired."
  }
  foreach ($evidence in $evidenceStrings) {
    $text = [string]$evidence
    $resolved = $false
    foreach ($rid in @($sliceReceiptIds.Keys)) {
      if ($text -match [regex]::Escape($rid)) { $resolved = $true; break }
    }
    if (-not $resolved) {
      foreach ($sid in $linkableSourceIds) {
        if ($text -match [regex]::Escape($sid)) { $resolved = $true; break }
      }
    }
    if (-not $resolved) {
      foreach ($wid in $knownWorkItemIds) {
        if ($text -match [regex]::Escape($wid)) { $resolved = $true; break }
      }
    }
    if (-not $resolved) {
      foreach ($token in $validSlicePathTokens) {
        if ($text -match [regex]::Escape($token)) { $resolved = $true; break }
      }
    }
    if (-not $resolved) {
      $preview = $text.Substring(0, [Math]::Min(80, $text.Length))
      Add-Issue $issues "Acceptance mapping for AC $criterion localEvidence must anchor to a resolvable slice identifier or a real slice path; unanchored string: '$preview...'."
    }
  }
}

# --- Final report -------------------------------------------------------------------------------------

if ($issues.Count -gt 0) {
  Write-Host "Handoff drafts slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Handoff drafts slice validation succeeded."
Write-Host "Drafts: $($drafts.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "Outbound denials: $($outboundDenials.Count)"
Write-Host "Approved outbound scopes: $($approvedScopes.Count)"
Write-Host "HANDOFF_DRAFTS_SLICE_VALIDATE_OK"
