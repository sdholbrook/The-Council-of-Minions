param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$ApprovalSlicePath = "$PSScriptRoot\approval-boundaries-slice.json",
  [string]$ManualSlicePath = "$PSScriptRoot\manual-source-record-slice.json",
  [string]$OutlookSlicePath = "$PSScriptRoot\outlook-source-reference-slice.json",
  [string]$Story13ExtractionPath = "$PSScriptRoot\proposed-work-item-extraction-slice.json",
  [string]$Story14ExtractionPath = "$PSScriptRoot\zero-multi-item-extraction-slice.json",
  [string]$DriftSlicePath = "$PSScriptRoot\source-drift-supersession-slice.json",
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
    Write-Host "Approval boundaries slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

function Collect-Ids {
  param(
    [Parameter(Mandatory = $true)]$Node,
    [Parameter(Mandatory = $true)][string]$Pattern
  )

  $ids = [System.Collections.Generic.List[string]]::new()
  if ($null -eq $Node) {
    return @($ids)
  }
  $json = ConvertTo-Json $Node -Depth 20 -Compress
  $matches = [regex]::Matches($json, $Pattern)
  foreach ($m in $matches) {
    $ids.Add($m.Value) | Out-Null
  }
  @($ids)
}

foreach ($path in @($ManifestPath, $ApprovalSlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $DriftSlicePath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required approval boundaries validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$approval = Read-JsonInput -Path $ApprovalSlicePath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$driftSlice = Read-JsonInput -Path $DriftSlicePath
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath
$rawSliceText = Get-Content -LiteralPath $ApprovalSlicePath -Raw
$issues = [System.Collections.Generic.List[string]]::new()

$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$workItemTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemtype"
$workItemStateGroups = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemstategroup"
$riskClasses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_riskclass"
$dataBoundaryPolicies = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_databoundarypolicy"
$evidenceRoles = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilreceiptsource" -ColumnName "com_evidence_role"
$workItemUrgency = @("low", "normal", "high", "critical", "unknown")

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_workitemtype"; Values = $workItemTypes },
    @{ Name = "com_workitemstategroup"; Values = $workItemStateGroups },
    @{ Name = "com_riskclass"; Values = $riskClasses },
    @{ Name = "com_databoundarypolicy"; Values = $dataBoundaryPolicies },
    @{ Name = "com_councilreceiptsource.com_evidence_role"; Values = $evidenceRoles }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

foreach ($verb in @("proposed", "approved")) {
  if ($receiptVerbs -notcontains $verb) {
    Add-Issue $issues "Manifest com_receiptverb is missing the approval-boundary verb: $verb."
  }
}
if ($evidenceRoles -notcontains "approval") {
  Add-Issue $issues "Manifest com_councilreceiptsource.com_evidence_role is missing: approval."
}

# Cross-slice ID collection for collision tripwires.
$siblingSlices = @($manualSlice, $outlookSlice, $story13Extraction, $story14Extraction, $driftSlice)
$priorCwiIds = [System.Collections.Generic.HashSet[string]]::new()
$priorCrIds = [System.Collections.Generic.HashSet[string]]::new()
$priorCsrIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($slice in $siblingSlices) {
  foreach ($id in (Collect-Ids -Node $slice -Pattern "CWI-[A-Za-z0-9-]+")) { [void]$priorCwiIds.Add($id) }
  foreach ($id in (Collect-Ids -Node $slice -Pattern "CR-[A-Za-z0-9-]+")) { [void]$priorCrIds.Add($id) }
  foreach ($id in (Collect-Ids -Node $slice -Pattern "CSR-[A-Za-z0-9-]+")) { [void]$priorCsrIds.Add($id) }
}
foreach ($id in @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
  [void]$priorCrIds.Add([string]$id)
}
foreach ($id in @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
  [void]$priorCwiIds.Add([string]$id)
}
$priorRunIds = @(
  [string]$story13Extraction.extractionRun.runId,
  [string]$story14Extraction.extractionRun.runId,
  [string]$driftSlice.driftRun.runId
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$priorSourceIds = @($priorCsrIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($priorSourceIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be loaded from sibling slices; cross-slice source-reference checks would silently no-op."
}
if ($priorCwiIds.Count -eq 0) {
  Add-Issue $issues "No Work Item IDs could be loaded from sibling slices; cross-slice collision checks would silently no-op."
}
if ($priorCrIds.Count -eq 0) {
  Add-Issue $issues "No Receipt IDs could be loaded from sibling slices; cross-slice collision checks would silently no-op."
}

# Slice header.
if ($approval.storyKey -ne "2-2-enforce-human-approval-boundaries") {
  Add-Issue $issues "Approval slice storyKey must be 2-2-enforce-human-approval-boundaries."
}
if ([string]$approval.status -notmatch "^local-contract") {
  Add-Issue $issues "Approval slice status must declare local contract evidence, found: $($approval.status)."
}

# Guards.
$requiredGuards = @(
  "noTenantWrites",
  "noOutboundAction",
  "noApprovalExecution",
  "requiresExplicitHumanApprovalForExecution",
  "approvalsAuthorizeOnlyDeclaredScope",
  "highRiskClassesStayProposedUntilApproved",
  "outOfScopeActionsRequireSeparateApproval",
  "noExternalActionBeforeApproval",
  "receiptsAreLocalContractEvidenceOnly",
  "receiptsAppendOnly",
  "noStateChangeExecutionInThisSlice"
)
foreach ($guard in $requiredGuards) {
  if (-not ($approval.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Approval slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($approval.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Approval guard must be boolean true: $($guardProperty.Name)."
  }
}

$run = $approval.approvalBoundariesRun
if ($null -eq $run) {
  Add-Issue $issues "Approval slice must carry an approvalBoundariesRun block."
  Write-Host "Approval boundaries slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

# Run header.
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Approval run must declare a runId."
}
elseif ($priorRunIds -contains [string]$run.runId) {
  Add-Issue $issues "Approval run must use a new local runId, not a sibling slice runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Approval run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Approval run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Approval run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "proposed-work-item-extraction-slice.json", "zero-multi-item-extraction-slice.json")) {
  if (@($run.inputSourceRecordsFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Approval run must reference $inputSlice as an input."
  }
}

# Decision policy.
$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Approval run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("highRiskClassesRequireExplicitApproval", "approvalsAuthorizeOnlyDeclaredScope", "outOfScopeActionRequiresSeparateApproval", "noExternalActionBeforeApproval", "receiptsAreLocalContractEvidenceOnly", "liveMutationAndExternalActionReceiptGatedToEpic2")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Approval run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Approval run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# Candidate Work Items — one per high-risk class.
$requiredRiskClasses = @(
  "decision",
  "delegation",
  "risk",
  "sensitive",
  "outbound",
  "memory_promotion",
  "skill_authority_expansion",
  "tenant_affecting"
)

$workItemTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilworkitem" } | Select-Object -First 1
$manifestRequiredWorkItemFields = @(@($workItemTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredWorkItemFields.Count -eq 0) {
  Add-Issue $issues "No required Work Item columns could be derived from manifest com_councilworkitem; candidate field checks would silently no-op."
}
$candidateWorkItemRequiredFields = @($manifestRequiredWorkItemFields + @("riskClassLabel", "noPreApprovalExternalAction", "externalActionGuard")) | Sort-Object -Unique

$candidates = @($run.candidateWorkItems | Where-Object { $null -ne $_ })
if ($candidates.Count -ne 8) {
  Add-Issue $issues "Approval slice must include exactly 8 candidate Work Items (one per high-risk class), found $($candidates.Count)."
}

$seenCandidateIds = @{}
$seenRiskClassLabels = @{}
$seenCandidateIdempotency = @{}
foreach ($candidate in $candidates) {
  $candidateId = [string]$candidate.com_council_work_item_id
  $subject = "Candidate Work Item $candidateId"
  $riskLabel = [string]$candidate.riskClassLabel

  foreach ($field in $candidateWorkItemRequiredFields) {
    if (-not (Test-HasNonEmptyField -Record $candidate -Field $field)) {
      Add-Issue $issues "$subject missing required field: $field."
    }
  }

  if ([string]::IsNullOrWhiteSpace($candidateId)) {
    Add-Issue $issues "Candidate Work Item must declare com_council_work_item_id."
  }
  else {
    if ($candidateId -notmatch "^CWI-") {
      Add-Issue $issues "$subject must use Council-level CWI-* identity."
    }
    if ($seenCandidateIds.ContainsKey($candidateId)) {
      Add-Issue $issues "Duplicate candidate Work Item ID in slice: $candidateId."
    }
    else {
      $seenCandidateIds[$candidateId] = $true
    }
    if ($priorCwiIds.Contains($candidateId)) {
      Add-Issue $issues "$subject collides with an existing CWI id from a sibling slice or demo evidence."
    }
  }

  if ($requiredRiskClasses -notcontains $riskLabel) {
    Add-Issue $issues "$subject riskClassLabel must be one of the eight high-risk classes, found: $riskLabel."
  }
  else {
    if ($seenRiskClassLabels.ContainsKey($riskLabel)) {
      Add-Issue $issues "Duplicate high-risk class in candidates: $riskLabel; each class must appear exactly once."
    }
    else {
      $seenRiskClassLabels[$riskLabel] = $true
    }
  }

  if ($workItemTypes -notcontains [string]$candidate.com_type) {
    Add-Issue $issues "$subject com_type is not in manifest com_workitemtype vocabulary, found: $($candidate.com_type)."
  }
  if ($riskClasses -notcontains [string]$candidate.com_risk_class) {
    Add-Issue $issues "$subject com_risk_class is not in manifest com_riskclass vocabulary, found: $($candidate.com_risk_class)."
  }
  if ($workItemStateGroups -notcontains [string]$candidate.com_state_group) {
    Add-Issue $issues "$subject com_state_group is not in manifest com_workitemstategroup vocabulary, found: $($candidate.com_state_group)."
  }
  elseif ([string]$candidate.com_state_group -ne "proposed") {
    Add-Issue $issues "$subject must stay proposed until explicitly approved, found com_state_group: $($candidate.com_state_group)."
  }
  if ($workItemUrgency -notcontains [string]$candidate.com_urgency) {
    Add-Issue $issues "$subject com_urgency is not in manifest urgency vocabulary, found: $($candidate.com_urgency)."
  }

  if ($candidate.com_approval_required -isnot [bool] -or -not $candidate.com_approval_required) {
    Add-Issue $issues "$subject com_approval_required must be strict boolean true."
  }
  if ($candidate.noPreApprovalExternalAction -isnot [bool] -or -not $candidate.noPreApprovalExternalAction) {
    Add-Issue $issues "$subject noPreApprovalExternalAction must be strict boolean true; no external action may have occurred before approval."
  }
  if (-not (Test-HasNonEmptyField -Record $candidate -Field "externalActionGuard")) {
    Add-Issue $issues "$subject must carry a non-empty externalActionGuard rationale proving no pre-approval external action occurred."
  }

  if (Test-HasNonEmptyField -Record $candidate -Field "com_owner_candidate_confidence") {
    Test-ConfidenceInRange -Issues $issues -Record $candidate -Field "com_owner_candidate_confidence" -Subject $subject | Out-Null
  }
}

foreach ($missingClass in @($requiredRiskClasses | Where-Object { -not $seenRiskClassLabels.ContainsKey($_) })) {
  Add-Issue $issues "Approval slice must include a candidate Work Item for high-risk class: $missingClass."
}
if (@($seenRiskClassLabels.Keys).Count -gt 8) {
  Add-Issue $issues "Approval slice must include at most one candidate per high-risk class."
}

# Approved Work Items.
$approvedItems = @($run.approvedWorkItems | Where-Object { $null -ne $_ })
if ($approvedItems.Count -ne 1) {
  Add-Issue $issues "Approval slice must include exactly one approved Work Item, found $($approvedItems.Count)."
}

$approvedItemIds = @{}
foreach ($approved in $approvedItems) {
  $approvedId = [string]$approved.com_council_work_item_id
  $subject = "Approved Work Item $approvedId"

  foreach ($field in $candidateWorkItemRequiredFields) {
    if (-not (Test-HasNonEmptyField -Record $approved -Field $field)) {
      Add-Issue $issues "$subject missing required field: $field."
    }
  }

  if ([string]::IsNullOrWhiteSpace($approvedId)) {
    Add-Issue $issues "Approved Work Item must declare com_council_work_item_id."
  }
  else {
    if ($approvedId -notmatch "^CWI-") {
      Add-Issue $issues "$subject must use Council-level CWI-* identity."
    }
    if ($approvedItemIds.ContainsKey($approvedId)) {
      Add-Issue $issues "Duplicate approved Work Item ID in slice: $approvedId."
    }
    else {
      $approvedItemIds[$approvedId] = $true
    }
    if ($priorCwiIds.Contains($approvedId)) {
      Add-Issue $issues "$subject collides with an existing CWI id from a sibling slice or demo evidence."
    }
    if ($seenCandidateIds.ContainsKey($approvedId)) {
      Add-Issue $issues "$subject duplicates a candidate Work Item id in this slice; the approved item must be a distinct id."
    }
  }

  if ($workItemStateGroups -notcontains [string]$approved.com_state_group) {
    Add-Issue $issues "$subject com_state_group is not in manifest vocabulary, found: $($approved.com_state_group)."
  }
  elseif ([string]$approved.com_state_group -ne "approved") {
    Add-Issue $issues "$subject must be in the approved state group to prove an approval was applied, found: $($approved.com_state_group)."
  }
  if ($approved.com_approval_required -isnot [bool] -or -not $approved.com_approval_required) {
    Add-Issue $issues "$subject com_approval_required must be strict boolean true; approval was required for this high-risk item."
  }

  $approvalRecord = $approved.approvalRecord
  if ($null -eq $approvalRecord) {
    Add-Issue $issues "$subject must carry an approvalRecord."
  }
  else {
    foreach ($field in @("approvedScope", "authorizedTransition", "actorType", "actorId", "authorityBasis", "outOfScopeActions")) {
      if (-not (Test-HasNonEmptyField -Record $approvalRecord -Field $field)) {
        Add-Issue $issues "$subject approvalRecord must carry a non-empty ${field}."
      }
    }
    if ([string]$approvalRecord.actorType -ne "human") {
      Add-Issue $issues "$subject approvalRecord actorType must be human, found: $($approvalRecord.actorType)."
    }
    if ([string]$approvalRecord.actorId -ne "Doug") {
      Add-Issue $issues "$subject approvalRecord actorId must be Doug (human approval), found: $($approvalRecord.actorId)."
    }
    if ($null -ne $approvalRecord.outOfScopeActions -and @($approvalRecord.outOfScopeActions).Count -lt 1) {
      Add-Issue $issues "$subject approvalRecord outOfScopeActions must list at least one action not authorized by this approval."
    }
    $approvalReceiptId = [string]$approvalRecord.approvalReceipt
    if ([string]::IsNullOrWhiteSpace($approvalReceiptId)) {
      Add-Issue $issues "$subject approvalRecord must name its backing approvalReceipt."
    }
    else {
      $script:pendingApprovalReceiptId = $approvalReceiptId
    }
  }
}

# Deferred actions — the second desired action requires a separate approval.
$deferredActions = @($run.deferredActions | Where-Object { $null -ne $_ })
if ($deferredActions.Count -lt 1) {
  Add-Issue $issues "Approval slice must include at least one deferred action proving a second action requires separate approval."
}
$deferredWorkItemIds = @{}
foreach ($deferred in $deferredActions) {
  $deferredWorkItem = [string]$deferred.workItem
  $subject = "Deferred action $deferredWorkItem"
  if ([string]::IsNullOrWhiteSpace($deferredWorkItem)) {
    Add-Issue $issues "Deferred action must name its workItem."
  }
  elseif (-not $approvedItemIds.ContainsKey($deferredWorkItem)) {
    Add-Issue $issues "$subject must target the approved Work Item (out-of-scope action on the same item), found: $deferredWorkItem."
  }
  else {
    $deferredWorkItemIds[$deferredWorkItem] = $true
  }
  foreach ($field in @("deferredAction", "requiredSeparateApproval", "rationale")) {
    if (-not (Test-HasNonEmptyField -Record $deferred -Field $field)) {
      Add-Issue $issues "$subject must carry a non-empty ${field}."
    }
  }
  if ([string]$deferred.requiredSeparateApproval -notmatch "not\s+granted") {
    Add-Issue $issues "$subject requiredSeparateApproval must explicitly state the separate approval is NOT granted in this slice, found: $($deferred.requiredSeparateApproval)."
  }
  if ($deferred.stateChangeInThisSlice -isnot [bool] -or $deferred.stateChangeInThisSlice) {
    Add-Issue $issues "$subject stateChangeInThisSlice must be strict boolean false; the out-of-scope action is deferred, not executed."
  }
}
foreach ($approvedId in @($approvedItemIds.Keys)) {
  if (-not $deferredWorkItemIds.ContainsKey($approvedId)) {
    Add-Issue $issues "Approved Work Item $approvedId must have a deferred second action proving a separate approval is required."
  }
}

# Receipts.
$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique

$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 2) {
  Add-Issue $issues "Approval slice must include at least two receipts (proposed and approved) for the approved item."
}

$sliceReceiptIds = @{}
$sliceReceiptsById = @{}
$seenIdempotencyKeys = @{}
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
      $sliceReceiptsById[$receiptId] = $receipt
    }
    if ($priorCrIds.Contains($receiptId)) {
      Add-Issue $issues "$subject collides with an existing CR id from a sibling slice or demo evidence."
    }
  }

  if ($receiptVerbs -notcontains [string]$receipt.com_verb) {
    Add-Issue $issues "$subject verb is not in manifest com_receiptverb vocabulary: $($receipt.com_verb)."
  }
  if ($actorTypes -notcontains [string]$receipt.com_actor_type) {
    Add-Issue $issues "$subject actor type is not in manifest com_actortype vocabulary: $($receipt.com_actor_type)."
  }
  elseif ([string]$receipt.com_actor_type -ne "human") {
    Add-Issue $issues "$subject actor type must be human for an approval event, found: $($receipt.com_actor_type)."
  }
  if ([string]$receipt.com_actor_id -ne "Doug") {
    Add-Issue $issues "$subject actor id must be Doug (human approval), found: $($receipt.com_actor_id)."
  }
  if ($receiptResults -notcontains [string]$receipt.com_result) {
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
    Add-Issue $issues "$subject com_append_only_locked must be strict boolean true (append-only)."
  }
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject | Out-Null

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; approval receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write", "no_outbound_action")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; approval receipts are local contract evidence only."
      }
    }
  }
}

# The approval record must reference a real receipt in this slice, and that receipt must be an "approved" verb.
if ($null -ne $script:pendingApprovalReceiptId) {
  if (-not $sliceReceiptIds.ContainsKey($script:pendingApprovalReceiptId)) {
    Add-Issue $issues "Approved Work Item approvalRecord references an unknown receipt: $script:pendingApprovalReceiptId."
  }
  else {
    $approvalReceipt = $sliceReceiptsById[$script:pendingApprovalReceiptId]
    if ([string]$approvalReceipt.com_verb -ne "approved") {
      Add-Issue $issues "Receipt $script:pendingApprovalReceiptId backing the approval record must use verb approved, found: $($approvalReceipt.com_verb)."
    }
    if ([string]$approvalReceipt.com_before_state -ne "proposed") {
      Add-Issue $issues "Receipt $script:pendingApprovalReceiptId com_before_state must be proposed, found: $($approvalReceipt.com_before_state)."
    }
    if ([string]$approvalReceipt.com_after_state -ne "approved") {
      Add-Issue $issues "Receipt $script:pendingApprovalReceiptId com_after_state must be approved, found: $($approvalReceipt.com_after_state)."
    }
  }
}

# Append-only chain on the approved item: a proposed receipt must precede the approved receipt.
$approvedWorkItemId = @($approvedItemIds.Keys) | Select-Object -First 1
if ($null -ne $approvedWorkItemId) {
  $approvedItemReceipts = @($receipts | Where-Object { [string]$_.com_work_item -eq $approvedWorkItemId })
  $proposedReceipt = @($approvedItemReceipts | Where-Object { [string]$_.com_verb -eq "proposed" }) | Select-Object -First 1
  $approvedReceipt = @($approvedItemReceipts | Where-Object { [string]$_.com_verb -eq "approved" }) | Select-Object -First 1
  if ($null -eq $proposedReceipt) {
    Add-Issue $issues "Approved Work Item $approvedWorkItemId must have a proposed receipt preceding its approval (append-only chain)."
  }
  if ($null -eq $approvedReceipt) {
    Add-Issue $issues "Approved Work Item $approvedWorkItemId must have an approved receipt recording the approval event."
  }
  if ($null -ne $proposedReceipt -and $null -ne $approvedReceipt) {
    $proposedAt = Get-ComparableInstant $proposedReceipt.com_occurred_at
    $approvedAt = Get-ComparableInstant $approvedReceipt.com_occurred_at
    if ($null -ne $proposedAt -and $null -ne $approvedAt -and $approvedAt -le $proposedAt) {
      Add-Issue $issues "Approved receipt must occur after the proposed receipt (append-only ordering), proposed: $($proposedReceipt.com_occurred_at), approved: $($approvedReceipt.com_occurred_at)."
    }
  }
}

# Receipt source links.
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
  if ([string]::IsNullOrWhiteSpace($linkSourceId) -or -not $priorCsrIds.Contains($linkSourceId)) {
    Add-Issue $issues "$linkSubject must bind an existing Source Record from a sibling slice, found: $linkSourceId."
  }
  if ($evidenceRoles -notcontains [string]$link.com_evidence_role) {
    Add-Issue $issues "$linkSubject evidence role is not in manifest vocabulary: $($link.com_evidence_role)."
  }
  elseif ([string]$link.com_evidence_role -ne "approval") {
    Add-Issue $issues "$linkSubject must use the approval evidence role, found: $($link.com_evidence_role)."
  }
}
foreach ($receiptId in @($sliceReceiptIds.Keys)) {
  if (@($links | Where-Object { [string]$_.com_receipt -eq $receiptId }).Count -lt 1) {
    Add-Issue $issues "Receipt $receiptId must be bound to its source evidence by at least one approval receipt source link."
  }
}

# No-pre-approval external action proof block.
$proofEntries = @($run.noPreApprovalExternalActionProof | Where-Object { $null -ne $_ })
if ($proofEntries.Count -ne 8) {
  Add-Issue $issues "noPreApprovalExternalActionProof must include exactly one entry per high-risk class (8), found $($proofEntries.Count)."
}
$proofByWorkItem = @{}
$proofByRiskClass = @{}
foreach ($proof in $proofEntries) {
  $proofWorkItem = [string]$proof.workItem
  $proofRiskLabel = [string]$proof.riskClassLabel
  $subject = "No-pre-approval proof $proofWorkItem"
  if ([string]::IsNullOrWhiteSpace($proofWorkItem) -or -not $seenCandidateIds.ContainsKey($proofWorkItem)) {
    Add-Issue $issues "$subject must reference a candidate Work Item in this slice."
  }
  else {
    if ($proofByWorkItem.ContainsKey($proofWorkItem)) {
      Add-Issue $issues "$subject duplicates a proof entry for $proofWorkItem."
    }
    else {
      $proofByWorkItem[$proofWorkItem] = $true
    }
    $candidate = @($candidates | Where-Object { [string]$_.com_council_work_item_id -eq $proofWorkItem }) | Select-Object -First 1
    if ($null -ne $candidate -and [string]$candidate.riskClassLabel -ne $proofRiskLabel) {
      Add-Issue $issues "$subject riskClassLabel must match the candidate's riskClassLabel ($($candidate.riskClassLabel)), found: $proofRiskLabel."
    }
  }
  if ($requiredRiskClasses -notcontains $proofRiskLabel) {
    Add-Issue $issues "$subject riskClassLabel must be one of the eight high-risk classes, found: $proofRiskLabel."
  }
  else {
    if ($proofByRiskClass.ContainsKey($proofRiskLabel)) {
      Add-Issue $issues "$subject duplicates a proof entry for risk class $proofRiskLabel."
    }
    else {
      $proofByRiskClass[$proofRiskLabel] = $true
    }
  }
  if ($proof.value -isnot [bool] -or -not $proof.value) {
    Add-Issue $issues "$subject value must be strict boolean true."
  }
  if (-not (Test-HasNonEmptyField -Record $proof -Field "proof")) {
    Add-Issue $issues "$subject must carry a non-empty proof rationale."
  }
}
foreach ($candidateId in @($seenCandidateIds.Keys)) {
  if (-not $proofByWorkItem.ContainsKey($candidateId)) {
    Add-Issue $issues "Candidate Work Item $candidateId must have a noPreApprovalExternalActionProof entry."
  }
}

# Deferred source updates / state changes must not apply mutation fields and must reference receipt gating.
$sourceUpdatesDeferred = @($run.sourceUpdatesDeferred | Where-Object { $null -ne $_ })
foreach ($deferred in $sourceUpdatesDeferred) {
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "sourceRecord")) {
    Add-Issue $issues "Deferred source update must name its sourceRecord."
  }
  elseif (-not $priorCsrIds.Contains([string]$deferred.sourceRecord)) {
    Add-Issue $issues "Deferred source update must name an existing Source Record from a sibling slice, found: $($deferred.sourceRecord)."
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred source update for $($deferred.sourceRecord) must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred source update for $($deferred.sourceRecord) must state the live mutation is receipt-gated."
  }
}

$workItemStateChangesDeferred = @($run.workItemStateChangesDeferred | Where-Object { $null -ne $_ })
foreach ($deferred in $workItemStateChangesDeferred) {
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "workItem")) {
    Add-Issue $issues "Deferred Work Item state change must name its workItem."
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred Work Item state change for $($deferred.workItem) must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred Work Item state change for $($deferred.workItem) must state any state move is receipt-gated."
  }
}

# No live-write marker fields anywhere in the slice's run block.
$forbiddenTopLevelFields = @("dataverseRowId", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt", "solutionPublishAt")
foreach ($forbiddenField in $forbiddenTopLevelFields) {
  if ($run.PSObject.Properties.Name -contains $forbiddenField) {
    Add-Issue $issues "Approval run must not carry live-write marker field '$forbiddenField'; this slice is local contract evidence only."
  }
}

# Acceptance mapping.
foreach ($criterion in @(1, 2, 3)) {
  $mapping = @($approval.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
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
  Write-Host "Approval boundaries slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Approval boundaries slice validation succeeded."
Write-Host "Candidate Work Items (high-risk classes): $($candidates.Count)"
Write-Host "Approved Work Items: $($approvedItems.Count)"
Write-Host "Deferred actions: $($deferredActions.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "No-pre-approval external action proofs: $($proofEntries.Count)"
Write-Host "APPROVAL_BOUNDARIES_SLICE_VALIDATE_OK"
