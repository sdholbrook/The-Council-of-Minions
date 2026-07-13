param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$PolicySlicePath = "$PSScriptRoot\auto-creation-policy-slice.json",
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

  if ($null -eq $Record) { return $false }
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
    return $null
  }
  $parsed = [decimal]0
  if (-not [decimal]::TryParse([string]$Record.$Field, [System.Globalization.NumberStyles]::Number, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
    Add-Issue $Issues "$Subject ${Field} must be numeric, found: $($Record.$Field)."
    return $null
  }
  if ($parsed -lt 0 -or $parsed -gt 1) {
    Add-Issue $Issues "$Subject ${Field} must be between 0 and 1, found: $parsed."
    return $null
  }
  return $parsed
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
    return
  }
  $rawValue = $Record.$Field
  if ($rawValue -is [datetime]) {
    if ($rawValue.Kind -eq [System.DateTimeKind]::Unspecified) {
      Add-Issue $Issues "$Subject ${Field} must be ISO 8601 with an explicit UTC offset, found: $rawValue."
    }
    return
  }
  $parsed = [datetimeoffset]::MinValue
  if (-not [datetimeoffset]::TryParse([string]$rawValue, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
    Add-Issue $Issues "$Subject ${Field} must be an ISO 8601 timestamp, found: $rawValue."
    return
  }
  if ([string]$rawValue -notmatch "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$") {
    Add-Issue $Issues "$Subject ${Field} must be ISO 8601 with an explicit UTC offset, found: $rawValue."
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
    Write-Host "Auto-creation policy slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

foreach ($path in @($ManifestPath, $PolicySlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $Story15DriftPath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required auto-creation policy validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$policy = Read-JsonInput -Path $PolicySlicePath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$story15Drift = Read-JsonInput -Path $Story15DriftPath
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath
$issues = [System.Collections.Generic.List[string]]::new()

# --- Manifest vocabulary ---
$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$workItemTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemtype"
$stateGroups = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemstategroup"
$riskClasses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_riskclass"
$sourceSystems = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_sourcesystem"
$evidenceRoles = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilreceiptsource" -ColumnName "com_evidence_role"

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_workitemtype"; Values = $workItemTypes },
    @{ Name = "com_workitemstategroup"; Values = $stateGroups },
    @{ Name = "com_riskclass"; Values = $riskClasses },
    @{ Name = "com_sourcesystem"; Values = $sourceSystems },
    @{ Name = "com_councilreceiptsource.com_evidence_role"; Values = $evidenceRoles }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

if ($receiptVerbs -notcontains "proposed") {
  Add-Issue $issues "Manifest com_receiptverb is missing: proposed."
}
if ($receiptVerbs -notcontains "policy_denied") {
  Add-Issue $issues "Manifest com_receiptverb is missing: policy_denied."
}
if ($workItemTypes -notcontains "follow_up") {
  Add-Issue $issues "Manifest com_workitemtype is missing: follow_up."
}
if ($workItemTypes -notcontains "meeting_action") {
  Add-Issue $issues "Manifest com_workitemtype is missing: meeting_action."
}

# --- com_auto_creation_policy_result column vocabulary ---
$workItemTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilworkitem" } | Select-Object -First 1
$autoCreationColumn = @($workItemTable.columns) | Where-Object { $_.name -eq "com_auto_creation_policy_result" } | Select-Object -First 1
$autoCreationValues = @($autoCreationColumn.values | Where-Object { $null -ne $_ })
if ($autoCreationValues.Count -eq 0) {
  Add-Issue $issues "Manifest com_councilworkitem.com_auto_creation_policy_result vocabulary is missing or empty."
}
foreach ($requiredValue in @("not_evaluated", "auto_created", "proposal_only", "policy_denied")) {
  if ($autoCreationValues -notcontains $requiredValue) {
    Add-Issue $issues "Manifest com_auto_creation_policy_result is missing value: $requiredValue."
  }
}

# --- Slice metadata ---
if ($policy.storyKey -ne "2-5-apply-safe-auto-creation-policy") {
  Add-Issue $issues "Policy slice storyKey must be 2-5-apply-safe-auto-creation-policy, found: $($policy.storyKey)."
}
if ([string]$policy.status -notmatch "^local-contract") {
  Add-Issue $issues "Policy slice status must declare local contract evidence, found: $($policy.status)."
}

# --- Guards ---
foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "requiresExplicitHumanApprovalForExecution", "sourceRecordsRemainSeparate", "meaningGraphDoesNotOwnWorkflowState", "dataverseRowsNotUsedAsCouncilIdentity", "receiptsAreLocalContractEvidenceOnly", "autoCreationSeparateFromApprovedExternalAction", "onlyLowRiskFollowUpAndMeetingActionAutoCreate", "deniedCandidatesStayProposedOnly", "noExternalActionFromAutoCreation", "siblingWorkItemsNotModifiedInThisSlice")) {
  if (-not ($policy.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Policy slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($policy.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Policy guard must be boolean true: $($guardProperty.Name)."
  }
}

# --- Cross-slice ID collection ---
$manualSources = @($manualSlice.manualCapture.sampleRecords | Where-Object { $null -ne $_ })
$outlookSources = @($outlookSlice.outlookCapture.sampleRecords | Where-Object { $null -ne $_ })
$story14EmbeddedSources = @($story14Extraction.extractionRun.embeddedSampleSourceRecords | Where-Object { $null -ne $_ })

$priorSourceIds = @{}
foreach ($record in @($manualSources + $outlookSources + $story14EmbeddedSources)) {
  $recordId = [string]$record.com_council_source_record_id
  if ([string]::IsNullOrWhiteSpace($recordId)) { continue }
  if (-not $priorSourceIds.ContainsKey($recordId)) {
    $priorSourceIds[$recordId] = $true
  }
}
$knownPriorSourceIds = @($priorSourceIds.Keys)

$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$siblingWorkItemIds = @(
  @($story13Items + $story14Items | ForEach-Object { [string]$_.com_council_work_item_id }) |
  Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

$siblingWorkItemTypes = @{}
foreach ($siblingItem in @($story13Items + $story14Items)) {
  $siblingId = [string]$siblingItem.com_council_work_item_id
  if ([string]::IsNullOrWhiteSpace($siblingId)) { continue }
  if (-not $siblingWorkItemTypes.ContainsKey($siblingId)) {
    $siblingWorkItemTypes[$siblingId] = [string]$siblingItem.com_type
  }
}

$story15Receipts = @($story15Drift.driftRun.receipts | Where-Object { $null -ne $_ })
$siblingReceiptIds = @($story15Receipts | ForEach-Object { [string]$_.com_receipt_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$story15SupersedingSources = @($story15Drift.driftRun.supersessions | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.supersedingRecord.com_council_source_record_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$siblingSourceIds = @(
  @($story15SupersedingSources) +
  @($story15Drift.driftRun.supersessions | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.supersededSourceRecord } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
) | Sort-Object -Unique

$demoWorkItemIds = @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$demoReceiptIds = @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

$allSiblingWorkItemIds = @($siblingWorkItemIds + $demoWorkItemIds) | Sort-Object -Unique
$allSiblingReceiptIds = @($siblingReceiptIds + $demoReceiptIds) | Sort-Object -Unique
$allSiblingSourceIds = @($knownPriorSourceIds + $siblingSourceIds) | Sort-Object -Unique

# --- Slice loads sanity ---
foreach ($sliceLoad in @(
    @{ Name = "manual-source-record-slice sampleRecords"; Count = $manualSources.Count },
    @{ Name = "outlook-source-reference-slice sampleRecords"; Count = $outlookSources.Count },
    @{ Name = "zero-multi-item-extraction-slice embeddedSampleSourceRecords"; Count = $story14EmbeddedSources.Count },
    @{ Name = "proposed-work-item-extraction-slice proposedWorkItems"; Count = $story13Items.Count },
    @{ Name = "zero-multi-item-extraction-slice proposedWorkItems"; Count = $story14Items.Count },
    @{ Name = "source-drift-supersession-slice receipts"; Count = $story15Receipts.Count }
  )) {
  if ($sliceLoad.Count -eq 0) {
    Add-Issue $issues "No records loaded from $($sliceLoad.Name); its cross-slice checks would silently no-op."
  }
}
if ($allSiblingWorkItemIds.Count -eq 0) {
  Add-Issue $issues "No sibling Work Item IDs could be loaded; cross-slice collision checks would silently no-op."
}
if ($allSiblingReceiptIds.Count -eq 0) {
  Add-Issue $issues "No sibling receipt IDs could be loaded; cross-slice collision checks would silently no-op."
}
if ($allSiblingSourceIds.Count -eq 0) {
  Add-Issue $issues "No sibling Source Record IDs could be loaded; cross-slice collision checks would silently no-op."
}

# --- Policy run block ---
$run = $policy.policyRun
if ($null -eq $run) {
  Add-Issue $issues "Policy slice must carry a policyRun block."
  Write-Host "Auto-creation policy slice validation failed:"
  foreach ($issue in $issues) { Write-Host "- $issue" }
  exit 1
}
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Policy run must declare a runId."
}
elseif (@([string]$story13Extraction.extractionRun.runId, [string]$story14Extraction.extractionRun.runId, [string]$story15Drift.driftRun.runId) -contains [string]$run.runId) {
  Add-Issue $issues "Policy run must use a new local runId, not a sibling runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Policy run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Policy run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Policy run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("proposed-work-item-extraction-slice.json", "zero-multi-item-extraction-slice.json")) {
  if (@($run.inputWorkItemsFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Policy run must reference $inputSlice as an input."
  }
}

# --- Policy thresholds ---
$thresholds = $run.policyThresholds
if ($null -eq $thresholds) {
  Add-Issue $issues "Policy run must declare a policyThresholds block."
}
else {
  $thresholdMap = @{
    sourceIdentificationConfidenceMin = "source_identification_confidence"
    typeConfidenceMin = "type_confidence"
    lowRiskClassConfidenceMin = "low_risk_classification_confidence"
    ownerConfidenceMin = "owner_confidence"
    nextActionConfidenceMin = "next_action_confidence"
  }
  $thresholdMinsParsed = @{}
  foreach ($thresholdName in @($thresholdMap.Keys)) {
    if (-not ($thresholds.PSObject.Properties.Name -contains $thresholdName)) {
      Add-Issue $issues "Policy thresholds must declare: $thresholdName."
      continue
    }
    $parsed = [decimal]0
    if (-not [decimal]::TryParse([string]$thresholds.$thresholdName, [System.Globalization.NumberStyles]::Number, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
      Add-Issue $issues "Policy threshold $thresholdName must be numeric, found: $($thresholds.$thresholdName)."
    }
    elseif ($parsed -lt 0 -or $parsed -gt 1) {
      Add-Issue $issues "Policy threshold $thresholdName must be in [0,1], found: $parsed."
    }
    else {
      $thresholdMinsParsed[$thresholdMap[$thresholdName]] = $parsed
    }
  }

  $allowedTypes = @($thresholds.allowedAutoCreateTypes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($allowedTypes.Count -lt 2) {
    Add-Issue $issues "Policy thresholds allowedAutoCreateTypes must include at least follow_up and meeting_action."
  }
  foreach ($requiredType in @("follow_up", "meeting_action")) {
    if ($allowedTypes -notcontains $requiredType) {
      Add-Issue $issues "Policy thresholds allowedAutoCreateTypes must include: $requiredType."
    }
  }
  foreach ($allowedType in $allowedTypes) {
    if ($workItemTypes -notcontains $allowedType) {
      Add-Issue $issues "Policy thresholds allowedAutoCreateTypes value is not in manifest com_workitemtype vocabulary: $allowedType."
    }
  }

  $lowRiskClasses = @($thresholds.lowRiskClasses | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($lowRiskClasses.Count -eq 0) {
    Add-Issue $issues "Policy thresholds must declare at least one lowRiskClass."
  }
  foreach ($lowRiskClass in $lowRiskClasses) {
    if ($riskClasses -notcontains $lowRiskClass) {
      Add-Issue $issues "Policy thresholds lowRiskClasses value is not in manifest com_riskclass vocabulary: $lowRiskClass."
    }
  }
}

# --- Decision policy ---
$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Policy run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("onlyLowRiskFollowUpAndMeetingActionAutoCreate", "autoCreationSeparateFromApprovedExternalAction", "deniedCandidatesStayProposedOnly", "noExternalActionFromAutoCreation", "nonAllowedTypesStayProposalOnly", "receiptsAreLocalContractEvidenceOnly", "liveDataverseCreateReceiptGatedToEpic2")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Policy run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Policy run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# --- Candidates ---
$candidates = @($run.candidates | Where-Object { $null -ne $_ })
if ($candidates.Count -ne 4) {
  Add-Issue $issues "Policy slice must include exactly four candidates (2 auto-created, 2 denied), found: $($candidates.Count)."
}

$workItemTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilworkitem" } | Select-Object -First 1
$manifestRequiredWorkItemFields = @(@($workItemTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredWorkItemFields.Count -eq 0) {
  Add-Issue $issues "No required Work Item columns could be derived from manifest com_councilworkitem; required-field checks would silently no-op."
}

$sliceWorkItemIds = @{}
$autoCreatedItems = @()
$deniedItems = @()
$candidateResults = @{}
$candidateEvalValues = @{}

foreach ($candidate in $candidates) {
  $candidateId = [string]$candidate.com_council_work_item_id
  $subject = "Candidate $candidateId"

  foreach ($field in $manifestRequiredWorkItemFields) {
    if (-not (Test-HasNonEmptyField -Record $candidate -Field $field)) {
      Add-Issue $issues "$subject missing required manifest Work Item field: $field."
    }
  }

  if ([string]::IsNullOrWhiteSpace($candidateId)) {
    Add-Issue $issues "Candidate must declare com_council_work_item_id."
    continue
  }
  if ($candidateId -notmatch "^CWI-") {
    Add-Issue $issues "$subject must use Council-level CWI-* identity."
  }
  if ($sliceWorkItemIds.ContainsKey($candidateId)) {
    Add-Issue $issues "Duplicate candidate ID in slice: $candidateId."
  }
  else {
    $sliceWorkItemIds[$candidateId] = $true
  }
  if ($allSiblingWorkItemIds -contains $candidateId) {
    Add-Issue $issues "$subject collides with a sibling Work Item ID from Story 1.3/1.4/demo."
  }

  if ($workItemTypes -notcontains $candidate.com_type) {
    Add-Issue $issues "$subject com_type is not in manifest com_workitemtype vocabulary: $($candidate.com_type)."
  }
  if ($stateGroups -notcontains $candidate.com_state_group) {
    Add-Issue $issues "$subject com_state_group is not in manifest com_workitemstategroup vocabulary: $($candidate.com_state_group)."
  }
  if ($riskClasses -notcontains $candidate.com_risk_class) {
    Add-Issue $issues "$subject com_risk_class is not in manifest com_riskclass vocabulary: $($candidate.com_risk_class)."
  }

  $sourceId = [string]$candidate.com_primary_source_record
  if ([string]::IsNullOrWhiteSpace($sourceId)) {
    Add-Issue $issues "$subject must declare com_primary_source_record."
  }
  elseif ($allSiblingSourceIds -notcontains $sourceId) {
    Add-Issue $issues "$subject com_primary_source_record references an unknown Source Record: $sourceId."
  }

  if ($autoCreationValues -notcontains $candidate.com_auto_creation_policy_result) {
    Add-Issue $issues "$subject com_auto_creation_policy_result is not in manifest vocabulary: $($candidate.com_auto_creation_policy_result)."
  }

  if ($candidate.com_approval_required -isnot [bool] -or -not $candidate.com_approval_required) {
    Add-Issue $issues "$subject com_approval_required must be strict boolean true; auto-creation never bypasses approval for external action."
  }

  $eval = $candidate.policyEvaluation
  if ($null -eq $eval) {
    Add-Issue $issues "$subject must carry a policyEvaluation block."
    continue
  }

  $evalFields = @(
    "source_identification_confidence",
    "type_confidence",
    "low_risk_classification_confidence",
    "owner_confidence",
    "next_action_confidence"
  )

  $evalValues = @{}
  foreach ($evalField in $evalFields) {
    $parsed = Test-ConfidenceInRange -Issues $issues -Record $eval -Field $evalField -Subject "$subject policyEvaluation"
    if ($null -ne $parsed) {
      $evalValues[$evalField] = $parsed
    }
  }
  $candidateEvalValues[$candidateId] = $evalValues

  if (-not (Test-HasNonEmptyField -Record $eval -Field "policy_rationale")) {
    Add-Issue $issues "$subject policyEvaluation must carry a non-empty policy_rationale."
  }

  $evalRiskClass = [string]$eval.evaluated_risk_class
  if ($riskClasses -notcontains $evalRiskClass) {
    Add-Issue $issues "$subject policyEvaluation evaluated_risk_class is not in manifest com_riskclass vocabulary: $evalRiskClass."
  }
  elseif ($evalRiskClass -ne [string]$candidate.com_risk_class) {
    Add-Issue $issues "$subject policyEvaluation evaluated_risk_class must match the candidate com_risk_class ($($candidate.com_risk_class)), found: $evalRiskClass."
  }

  if ($eval.type_allowed_for_auto_create -isnot [bool]) {
    Add-Issue $issues "$subject policyEvaluation type_allowed_for_auto_create must be strict boolean."
  }

  $result = [string]$candidate.com_auto_creation_policy_result
  $candidateResults[$candidateId] = $result

  if ($result -eq "auto_created") {
    $autoCreatedItems += $candidate

    if ($allowedTypes -notcontains $candidate.com_type) {
      Add-Issue $issues "$subject is auto_created but its type ($($candidate.com_type)) is not in allowedAutoCreateTypes; only follow_up and meeting_action may auto-create."
    }
    if ($lowRiskClasses -notcontains $evalRiskClass) {
      Add-Issue $issues "$subject is auto_created but evaluated_risk_class ($evalRiskClass) is not in lowRiskClasses; only low-risk items may auto-create."
    }
    if ($candidate.com_state_group -ne "proposed") {
      Add-Issue $issues "$subject auto_created item must stay in proposed state group, found: $($candidate.com_state_group)."
    }
    if ($eval.type_allowed_for_auto_create -isnot [bool] -or -not $eval.type_allowed_for_auto_create) {
      Add-Issue $issues "$subject is auto_created but policyEvaluation.type_allowed_for_auto_create is not strict boolean true."
    }
    foreach ($evalField in $evalFields) {
      if ($evalValues.ContainsKey($evalField) -and $thresholdMinsParsed.ContainsKey($evalField)) {
        $minValue = $thresholdMinsParsed[$evalField]
        if ($evalValues[$evalField] -lt $minValue) {
          Add-Issue $issues "$subject is auto_created but $evalField ($($evalValues[$evalField])) is below the policy minimum ($minValue)."
        }
      }
    }
    if ($eval.all_thresholds_met -isnot [bool] -or -not $eval.all_thresholds_met) {
      Add-Issue $issues "$subject is auto_created but policyEvaluation.all_thresholds_met is not strict boolean true."
    }
    if ($eval.decision -ne "auto_created") {
      Add-Issue $issues "$subject is auto_created but policyEvaluation.decision is '$($eval.decision)'; must be 'auto_created'."
    }
  }
  elseif ($result -eq "policy_denied") {
    $deniedItems += $candidate

    if ($candidate.com_state_group -ne "proposed") {
      Add-Issue $issues "$subject policy_denied item must stay in proposed state group (proposed-only), found: $($candidate.com_state_group)."
    }
    if (-not (Test-HasNonEmptyField -Record $eval -Field "policy_rationale")) {
      Add-Issue $issues "$subject policy_denied item must carry a non-empty policy_rationale."
    }
    if ($eval.all_thresholds_met -isnot [bool] -or $eval.all_thresholds_met) {
      Add-Issue $issues "$subject is policy_denied but policyEvaluation.all_thresholds_met is not strict boolean false; a denial must record that thresholds were not all met."
    }
    if ($eval.decision -ne "policy_denied") {
      Add-Issue $issues "$subject is policy_denied but policyEvaluation.decision is '$($eval.decision)'; must be 'policy_denied'."
    }
  }
  else {
    Add-Issue $issues "$subject com_auto_creation_policy_result must be auto_created or policy_denied for Story 2.5, found: $result."
  }

  if (-not (Test-HasNonEmptyField -Record $candidate -Field "com_policy_flags")) {
    Add-Issue $issues "$subject must carry a non-empty com_policy_flags."
  }
  else {
    foreach ($requiredFlag in @("no_external_action", "local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$candidate.com_policy_flags -notmatch [regex]::Escape($requiredFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredFlag; Story 2.5 candidates are local contract evidence only with no external action or tenant write."
      }
    }
    if ($result -eq "auto_created" -and [string]$candidate.com_policy_flags -notmatch "auto_created") {
      Add-Issue $issues "$subject is auto_created but com_policy_flags does not declare auto_created."
    }
    if ($result -eq "policy_denied" -and [string]$candidate.com_policy_flags -notmatch "policy_denied") {
      Add-Issue $issues "$subject is policy_denied but com_policy_flags does not declare policy_denied."
    }
  }
}

# --- Exactly 2 auto-created (1 follow_up + 1 meeting_action) ---
if ($autoCreatedItems.Count -ne 2) {
  Add-Issue $issues "Policy slice must include exactly two auto-created candidates, found: $($autoCreatedItems.Count)."
}
$autoFollowUp = @($autoCreatedItems | Where-Object { $_.com_type -eq "follow_up" })
$autoMeetingAction = @($autoCreatedItems | Where-Object { $_.com_type -eq "meeting_action" })
if ($autoFollowUp.Count -ne 1) {
  Add-Issue $issues "Policy slice must include exactly one auto-created follow_up candidate, found: $($autoFollowUp.Count)."
}
if ($autoMeetingAction.Count -ne 1) {
  Add-Issue $issues "Policy slice must include exactly one auto-created meeting_action candidate, found: $($autoMeetingAction.Count)."
}

# --- Exactly 2 denied (1 confidence, 1 risk-class), classified by VALUE not self-authored tags ---
if ($deniedItems.Count -ne 2) {
  Add-Issue $issues "Policy slice must include exactly two denied candidates, found: $($deniedItems.Count)."
}
$confidenceDenied = @()
$riskDenied = @()
foreach ($denied in $deniedItems) {
  $deniedId = [string]$denied.com_council_work_item_id
  $subject = "Denied candidate $deniedId"
  $eval = $denied.policyEvaluation
  if ($null -eq $eval) {
    Add-Issue $issues "$subject has no policyEvaluation; cannot classify denial reason by value."
    continue
  }

  $dEvalValues = $candidateEvalValues[$deniedId]
  if ($null -eq $dEvalValues) { $dEvalValues = @{} }

  # Identification confidence fields (excludes low_risk_classification_confidence, which is the risk-class classifier's own metric and a corollary of the risk-class check, not an independent identification threshold).
  $identificationConfidenceFields = @(
    "source_identification_confidence",
    "type_confidence",
    "owner_confidence",
    "next_action_confidence"
  )

  # Genuine identification-confidence failure: at least one identification confidence value is strictly below its declared minimum.
  $hasConfidenceFailure = $false
  $failingFields = @()
  foreach ($evalField in $identificationConfidenceFields) {
    if ($dEvalValues.ContainsKey($evalField) -and $thresholdMinsParsed.ContainsKey($evalField)) {
      if ($dEvalValues[$evalField] -lt $thresholdMinsParsed[$evalField]) {
        $hasConfidenceFailure = $true
        $failingFields += $evalField
      }
    }
  }

  # Genuine risk-class failure: evaluated_risk_class is not in lowRiskClasses.
  $deniedRiskClass = [string]$eval.evaluated_risk_class
  $hasRiskFailure = (-not [string]::IsNullOrWhiteSpace($deniedRiskClass)) -and ($lowRiskClasses -notcontains $deniedRiskClass)

  # Each denied candidate must fail exactly one distinct policy reason.
  if ($hasConfidenceFailure -and -not $hasRiskFailure) {
    $confidenceDenied += $denied
  }
  elseif ($hasRiskFailure -and -not $hasConfidenceFailure) {
    $riskDenied += $denied
  }
  elseif ($hasConfidenceFailure -and $hasRiskFailure) {
    Add-Issue $issues "$subject fails BOTH a confidence threshold ($($failingFields -join ', ')) and the low-risk-class check; each denied candidate must fail exactly one distinct policy reason."
  }
  else {
    Add-Issue $issues "$subject is policy_denied but no policyEvaluation value actually fails any declared threshold or the low-risk-class check; the denial is not justified by evidence."
  }

  # The self-authored failure tags must agree with the computed failure reason.
  if ($hasConfidenceFailure) {
    if (-not (Test-HasNonEmptyField -Record $eval -Field "failing_thresholds")) {
      Add-Issue $issues "$subject fails confidence threshold(s) ($($failingFields -join ', ')) by value but policyEvaluation.failing_thresholds is absent or empty."
    }
    else {
      $declaredFailing = @($eval.failing_thresholds | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      foreach ($ff in $failingFields) {
        if ($declaredFailing -notcontains $ff) {
          Add-Issue $issues "$subject policyEvaluation.failing_thresholds must list the actually-failing field: $ff."
        }
      }
    }
  }
  if ($hasRiskFailure) {
    if (-not (Test-HasNonEmptyField -Record $eval -Field "failing_check") -or [string]$eval.failing_check -notmatch "risk_class") {
      Add-Issue $issues "$subject fails the low-risk-class check by value but policyEvaluation.failing_check is absent or does not name risk_class."
    }
  }

  # Rationale must reference the actual failing evidence, not just be non-empty prose.
  if (Test-HasNonEmptyField -Record $eval -Field "policy_rationale") {
    $rationale = [string]$eval.policy_rationale
    if ($hasConfidenceFailure) {
      foreach ($ff in $failingFields) {
        $actualValue = $dEvalValues[$ff]
        $minValue = $thresholdMinsParsed[$ff]
        if ($rationale -notmatch [regex]::Escape([string]$actualValue)) {
          Add-Issue $issues "$subject policy_rationale must reference the actual failing $ff value ($actualValue); found rationale does not cite it."
        }
        if ($rationale -notmatch [regex]::Escape([string]$minValue)) {
          Add-Issue $issues "$subject policy_rationale must reference the $ff policy minimum ($minValue); found rationale does not cite it."
        }
      }
    }
    if ($hasRiskFailure) {
      if ($rationale -notmatch [regex]::Escape($deniedRiskClass)) {
        Add-Issue $issues "$subject policy_rationale must reference the evaluated_risk_class ($deniedRiskClass); found rationale does not cite it."
      }
      $referencesLowRisk = $false
      if ($rationale -match "low.risk") { $referencesLowRisk = $true }
      foreach ($lrc in $lowRiskClasses) {
        if ($rationale -match [regex]::Escape([string]$lrc)) { $referencesLowRisk = $true }
      }
      if (-not $referencesLowRisk) {
        Add-Issue $issues "$subject policy_rationale must reference the low-risk-class set or the term 'low-risk'; found rationale does not."
      }
    }
  }
}
if ($confidenceDenied.Count -ne 1) {
  Add-Issue $issues "Policy slice must include exactly one denied candidate whose policyEvaluation confidence value is genuinely below its declared minimum (with risk class still low-risk), found: $($confidenceDenied.Count)."
}
if ($riskDenied.Count -ne 1) {
  Add-Issue $issues "Policy slice must include exactly one denied candidate whose evaluated_risk_class is genuinely not in lowRiskClasses (with all confidences meeting their minimums), found: $($riskDenied.Count)."
}
# The two denied candidates must be distinct items with distinct denial reasons.
if ($confidenceDenied.Count -eq 1 -and $riskDenied.Count -eq 1) {
  if ([string]$confidenceDenied[0].com_council_work_item_id -eq [string]$riskDenied[0].com_council_work_item_id) {
    Add-Issue $issues "The confidence-denied and risk-denied candidates must be distinct Work Items; found both reasons on the same id."
  }
}

# --- No non-allowed type is auto_created (exhaustive check within slice) ---
foreach ($candidate in $candidates) {
  if ([string]$candidate.com_auto_creation_policy_result -eq "auto_created") {
    if ($allowedTypes -notcontains $candidate.com_type) {
      Add-Issue $issues "Candidate $($candidate.com_council_work_item_id) is auto_created with type $($candidate.com_type) which is not in allowedAutoCreateTypes; only follow_up and meeting_action may auto-create."
    }
  }
}

# --- Sibling proposal-only items ---
$siblingProposalOnly = @($run.siblingProposalOnlyItems | Where-Object { $null -ne $_ })
if ($siblingProposalOnly.Count -lt 1) {
  Add-Issue $issues "Policy slice must list sibling proposal-only items of non-allowed types."
}
foreach ($entry in $siblingProposalOnly) {
  $siblingId = [string]$entry.workItem
  $subject = "Sibling proposal-only item $siblingId"
  if ([string]::IsNullOrWhiteSpace($siblingId)) {
    Add-Issue $issues "Sibling proposal-only entry must name its workItem."
    continue
  }
  if ($allSiblingWorkItemIds -notcontains $siblingId) {
    Add-Issue $issues "$subject references an unknown sibling Work Item."
  }
  if (-not (Test-HasNonEmptyField -Record $entry -Field "note")) {
    Add-Issue $issues "$subject must carry a non-empty note."
  }
  # The referenced sibling must actually be of a type outside allowedAutoCreateTypes (proven from the sibling slice, not just asserted in prose).
  if ($siblingWorkItemTypes.ContainsKey($siblingId)) {
    $siblingType = $siblingWorkItemTypes[$siblingId]
    if ($workItemTypes -notcontains $siblingType) {
      Add-Issue $issues "$subject references a sibling whose com_type '$siblingType' is not in manifest com_workitemtype vocabulary."
    }
    if ($allowedTypes -contains $siblingType) {
      Add-Issue $issues "$subject references a sibling of type '$siblingType' which IS in allowedAutoCreateTypes; a proposal-only sibling must be a non-allowed type by evidence, not just by note."
    }
  }
  else {
    Add-Issue $issues "$subject references a sibling Work Item whose com_type could not be harvested from Story 1.3/1.4 slices; the non-allowed-type claim must be proven from sibling slice data, not just prose."
  }
  foreach ($mutationField in @("com_state_group", "com_auto_creation_policy_result")) {
    if ($entry.PSObject.Properties.Name -contains $mutationField) {
      Add-Issue $issues "$subject must not apply '$mutationField' in-slice; sibling items are referenced only, never modified."
    }
  }
}

# --- Receipts ---
$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 4) {
  Add-Issue $issues "Policy slice must include at least four receipts (2 auto-create, 2 policy-deny)."
}

$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_work_item", "com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique

$sliceReceiptIds = @{}
$seenIdempotencyKeys = @{}
$receiptsByWorkItem = @{}
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
    if ($allSiblingReceiptIds -contains $receiptId) {
      Add-Issue $issues "$subject collides with a sibling receipt ID from Story 1.5/demo."
    }
  }

  if ($receiptVerbs -notcontains $receipt.com_verb) {
    Add-Issue $issues "$subject verb is not in manifest com_receiptverb vocabulary: $($receipt.com_verb)."
  }
  elseif ($receipt.com_verb -ne "proposed" -and $receipt.com_verb -ne "policy_denied") {
    Add-Issue $issues "$subject must use verb proposed or policy_denied for Story 2.5, found: $($receipt.com_verb)."
  }
  if ($actorTypes -notcontains $receipt.com_actor_type) {
    Add-Issue $issues "$subject actor type is not in manifest com_actortype vocabulary: $($receipt.com_actor_type)."
  }
  if ($receiptResults -notcontains $receipt.com_result) {
    Add-Issue $issues "$subject result is not in manifest com_receiptresult vocabulary: $($receipt.com_result)."
  }
  Test-IsoTimestamp -Issues $issues -Record $receipt -Field "com_occurred_at" -Subject $subject

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
  $null = Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 2.5 receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write", "no_external_action")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 2.5 receipts are local contract evidence only with no external action."
      }
    }
  }

  $workItemId = [string]$receipt.com_work_item
  if (-not [string]::IsNullOrWhiteSpace($workItemId)) {
    if (-not $sliceWorkItemIds.ContainsKey($workItemId)) {
      Add-Issue $issues "$subject com_work_item references an unknown candidate Work Item: $workItemId."
    }
    else {
      if (-not $receiptsByWorkItem.ContainsKey($workItemId)) {
        $receiptsByWorkItem[$workItemId] = @()
      }
      $receiptsByWorkItem[$workItemId] += $receipt
    }
  }

  if ($receipt.com_verb -eq "proposed") {
    if ($receipt.com_result -ne "accepted") {
      Add-Issue $issues "$subject with verb proposed must have result accepted for auto-creation, found: $($receipt.com_result)."
    }
    if ([string]$receipt.com_after_state -ne "auto_created") {
      Add-Issue $issues "$subject with verb proposed must have com_after_state auto_created, found: $($receipt.com_after_state)."
    }
    if ([string]$receipt.com_policy_flags -notmatch "auto_created") {
      Add-Issue $issues "$subject with verb proposed must declare auto_created in com_policy_flags."
    }
  }
  elseif ($receipt.com_verb -eq "policy_denied") {
    if ($receipt.com_result -ne "rejected") {
      Add-Issue $issues "$subject with verb policy_denied must have result rejected, found: $($receipt.com_result)."
    }
    if ([string]$receipt.com_after_state -ne "proposal_only") {
      Add-Issue $issues "$subject with verb policy_denied must have com_after_state proposal_only, found: $($receipt.com_after_state)."
    }
    if ([string]$receipt.com_policy_flags -notmatch "policy_denied") {
      Add-Issue $issues "$subject with verb policy_denied must declare policy_denied in com_policy_flags."
    }
  }
}

foreach ($expectedReceiptId in @("CR-LOCAL-AUTO-CREATE-001", "CR-LOCAL-AUTO-CREATE-002", "CR-LOCAL-POLICY-DENY-001", "CR-LOCAL-POLICY-DENY-002")) {
  if (-not $sliceReceiptIds.ContainsKey($expectedReceiptId)) {
    Add-Issue $issues "Policy slice must include receipt $expectedReceiptId."
  }
}

# --- 1:1 receipt <-> candidate binding with result agreement (AC3) ---
$receiptOwners = @{}
foreach ($receipt in $receipts) {
  $receiptId = [string]$receipt.com_receipt_id
  $workItemId = [string]$receipt.com_work_item
  if (-not [string]::IsNullOrWhiteSpace($workItemId) -and $sliceWorkItemIds.ContainsKey($workItemId)) {
    $receiptOwners[$receiptId] = $workItemId
  }
}
# No two distinct candidate ids may be served by the same receipt (a receipt has exactly one com_work_item by manifest, but assert it here too).
foreach ($candidate in $candidates) {
  $cid = [string]$candidate.com_council_work_item_id
  if ([string]::IsNullOrWhiteSpace($cid)) { continue }
  $cResult = [string]$candidate.com_auto_creation_policy_result
  $cReceipts = @($receiptsByWorkItem[$cid] | Where-Object { $null -ne $_ })
  if ($cReceipts.Count -lt 1) {
    Add-Issue $issues "Candidate $cid must be backed by at least one receipt whose com_work_item references it; found 0."
    continue
  }
  $hasAgreeingReceipt = $false
  foreach ($r in $cReceipts) {
    $rSubject = "Receipt $([string]$r.com_receipt_id) for candidate $cid"
    $agrees = $true
    if ($cResult -eq "auto_created") {
      if ([string]$r.com_verb -ne "proposed") { $agrees = $false }
      if ([string]$r.com_result -ne "accepted") { $agrees = $false }
      if ([string]$r.com_after_state -ne "auto_created") { $agrees = $false }
      if ([string]$r.com_policy_flags -notmatch "auto_created") { $agrees = $false }
    }
    elseif ($cResult -eq "policy_denied") {
      if ([string]$r.com_verb -ne "policy_denied") { $agrees = $false }
      if ([string]$r.com_result -ne "rejected") { $agrees = $false }
      if ([string]$r.com_after_state -ne "proposal_only") { $agrees = $false }
      if ([string]$r.com_policy_flags -notmatch "policy_denied") { $agrees = $false }
    }
    if ($agrees) { $hasAgreeingReceipt = $true }
  }
  if (-not $hasAgreeingReceipt) {
    Add-Issue $issues "Candidate $cid (com_auto_creation_policy_result=$cResult) must have at least one receipt whose verb/result/com_after_state/com_policy_flags agree with that result; no agreeing receipt found."
  }
}
# Every receipt must reference a candidate (no orphan receipts pointing nowhere or to a denied candidate under an auto-created receipt shape).
foreach ($receipt in $receipts) {
  $receiptId = [string]$receipt.com_receipt_id
  $workItemId = [string]$receipt.com_work_item
  if ([string]::IsNullOrWhiteSpace($workItemId) -or -not $sliceWorkItemIds.ContainsKey($workItemId)) {
    Add-Issue $issues "Receipt $receiptId com_work_item must reference a candidate in this slice; found: $workItemId."
  }
}

# --- Receipt source links ---
$links = @($run.receiptSourceLinks | Where-Object { $null -ne $_ })
$linkedReceiptIds = @{}
foreach ($link in $links) {
  $linkSubject = "Receipt source link $($link.com_name)"
  if (-not (Test-HasNonEmptyField -Record $link -Field "com_name")) {
    Add-Issue $issues "Receipt source link must carry a non-empty com_name."
  }
  $linkReceiptId = [string]$link.com_receipt
  if ([string]::IsNullOrWhiteSpace($linkReceiptId) -or -not $sliceReceiptIds.ContainsKey($linkReceiptId)) {
    Add-Issue $issues "$linkSubject references unknown receipt: $linkReceiptId."
    continue
  }
  $linkedReceiptIds[$linkReceiptId] = $true
  $linkSourceId = [string]$link.com_source_record
  if ([string]::IsNullOrWhiteSpace($linkSourceId) -or $allSiblingSourceIds -notcontains $linkSourceId) {
    Add-Issue $issues "$linkSubject must bind a known sibling Source Record, found: $linkSourceId."
  }
  if ($evidenceRoles -notcontains $link.com_evidence_role) {
    Add-Issue $issues "$linkSubject evidence role is not in manifest vocabulary: $($link.com_evidence_role)."
  }
}
foreach ($receiptId in @($sliceReceiptIds.Keys)) {
  if (-not $linkedReceiptIds.ContainsKey($receiptId)) {
    Add-Issue $issues "Receipt $receiptId must be bound to its source evidence by at least one receipt source link."
  }
}

# --- Live creates deferred ---
$liveCreatesDeferred = @($run.liveCreatesDeferred | Where-Object { $null -ne $_ })
foreach ($deferred in $liveCreatesDeferred) {
  $deferredId = [string]$deferred.workItem
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "workItem")) {
    Add-Issue $issues "Deferred live create must name its workItem."
  }
  elseif (-not $sliceWorkItemIds.ContainsKey($deferredId)) {
    Add-Issue $issues "Deferred live create references an unknown Work Item: $deferredId."
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred live create for $deferredId must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred live create for $deferredId must state that the live mutation is receipt-gated."
  }
}
foreach ($autoCreated in $autoCreatedItems) {
  $autoId = [string]$autoCreated.com_council_work_item_id
  $deferred = $liveCreatesDeferred | Where-Object { [string]$_.workItem -eq $autoId } | Select-Object -First 1
  if (-not $deferred) {
    Add-Issue $issues "Missing deferred live create entry for auto-created Work Item $autoId."
  }
}

# --- Acceptance mapping ---
foreach ($criterion in @(1, 2, 3)) {
  $mapping = @($policy.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
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

# --- Final ---
if ($issues.Count -gt 0) {
  Write-Host "Auto-creation policy slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Auto-creation policy slice validation succeeded."
Write-Host "Auto-created candidates: $($autoCreatedItems.Count)"
Write-Host "Denied candidates: $($deniedItems.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "AUTO_CREATION_POLICY_SLICE_VALIDATE_OK"
