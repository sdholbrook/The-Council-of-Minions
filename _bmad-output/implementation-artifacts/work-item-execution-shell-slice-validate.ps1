param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$ShellSlicePath = "$PSScriptRoot\work-item-execution-shell-slice.json",
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

function Test-FieldPresent {
  param(
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$Field
  )

  # Present (declared) even when explicitly null. Used for "approved owner where known" semantics.
  @($Record.PSObject.Properties.Name) -contains $Field
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

function Test-NoPriorMutationFields {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$Subject
  )

  # Work Item state moves are receipt-gated to Story 2.3; this slice carries the creation shell only.
  foreach ($mutationField in @("com_state_group_changed_to", "liveWriteAt", "tenantWriteAt")) {
    if ($Record.PSObject.Properties.Name -contains $mutationField) {
      Add-Issue $Issues "$Subject must not carry live-write or in-slice state-change marker '$mutationField'; Story 2.1 records the creation shell only."
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
    Write-Host "Work item execution shell slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

foreach ($path in @($ManifestPath, $ShellSlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $DriftSlicePath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required work item execution shell validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$shell = Read-JsonInput -Path $ShellSlicePath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$drift = Read-JsonInput -Path $DriftSlicePath
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath
$rawSliceText = Get-Content -LiteralPath $ShellSlicePath -Raw
$issues = [System.Collections.Generic.List[string]]::new()

# Platform-id shapes that may NEVER serve as Work Item primary identity or leak into non-source-ref
# Work Item fields. GUID covers Dataverse row ids and Microsoft Graph activity/object ids; the Outlook
# message-id pattern covers Exchange/Outlook message id strings (AAMk-prefixed base64-ish tokens).
$guidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
$messageIdPattern = "^AAMk[A-Za-z0-9+/=_-]{10,}$"
# Unanchored variants for the isolation scan: a smuggled platform id may be embedded in prose, so
# the scan must match a platform-id-shaped token ANYWHERE in a non-carrier field value (not just a
# full-string match).
$platformIdScanPatterns = @(
  "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
  "AAMk[A-Za-z0-9+/=_-]{10,}"
)

$workItemTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemtype"
$stateGroups = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemstategroup"
$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$riskClasses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_riskclass"
$workItemSourceRoles = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilworkitemsource" -ColumnName "com_source_role"

foreach ($vocabulary in @(
    @{ Name = "com_workitemtype"; Values = $workItemTypes },
    @{ Name = "com_workitemstategroup"; Values = $stateGroups },
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_riskclass"; Values = $riskClasses },
    @{ Name = "com_councilworkitemsource.com_source_role"; Values = $workItemSourceRoles }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

foreach ($state in @("proposed", "approved", "blocked", "held", "in_review", "completed", "failed")) {
  if ($stateGroups -notcontains $state) {
    Add-Issue $issues "Manifest com_workitemstategroup is missing the required state group: $state."
  }
}
if ($receiptVerbs -notcontains "proposed") {
  Add-Issue $issues "Manifest com_receiptverb is missing the creation verb: proposed."
}
if ($workItemSourceRoles -notcontains "superseding") {
  Add-Issue $issues "Manifest com_councilworkitemsource.com_source_role is missing: superseding."
}

# Build the set of every manifest column name across all tables, so carrier-field allow-lists can
# be verified against real columns (no phantom field names widen a platform-id exemption).
$knownColumnNames = [System.Collections.Generic.HashSet[string]]::new()
foreach ($table in @($manifest.tables)) {
  foreach ($column in @($table.columns)) {
    $colName = [string]$column.name
    if (-not [string]::IsNullOrWhiteSpace($colName)) { [void]$knownColumnNames.Add($colName) }
  }
}
if ($knownColumnNames.Count -eq 0) {
  Add-Issue $issues "No columns could be derived from manifest tables; carrier-field validation would silently no-op."
}

if ($shell.storyKey -ne "2-1-maintain-the-work-item-execution-shell") {
  Add-Issue $issues "Shell slice storyKey must be 2-1-maintain-the-work-item-execution-shell."
}
if ([string]$shell.status -notmatch "^local-contract") {
  Add-Issue $issues "Shell slice status must declare local contract evidence, found: $($shell.status)."
}

foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "requiresExplicitHumanApprovalForExecution", "sourceRecordsRemainSeparate", "meaningGraphDoesNotOwnWorkflowState", "dataverseRowsNotUsedAsCouncilIdentity", "receiptsAreLocalContractEvidenceOnly", "primaryIdIsCouncilLevelNotPlatform", "noWorkItemStateChangeInThisSlice")) {
  if (-not ($shell.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Shell slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($shell.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Shell guard must be boolean true: $($guardProperty.Name)."
  }
}

# Harvest known sibling-slice Source Record IDs (top-level sample records + embedded + superseding).
$manualSources = @($manualSlice.manualCapture.sampleRecords | Where-Object { $null -ne $_ })
$outlookSources = @($outlookSlice.outlookCapture.sampleRecords | Where-Object { $null -ne $_ })
$story14EmbeddedSources = @($story14Extraction.extractionRun.embeddedSampleSourceRecords | Where-Object { $null -ne $_ })
$driftSupersedingSources = @($drift.driftRun.supersessions.supersedingRecord | Where-Object { $null -ne $_ })
$priorSourcesById = @{}
foreach ($record in @($manualSources + $outlookSources + $story14EmbeddedSources + $driftSupersedingSources)) {
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

# Harvest known sibling-slice Work Item IDs (for cross-slice ID-collision tripwires).
$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$siblingWorkItemIds = @($story13Items + $story14Items | ForEach-Object { [string]$_.com_council_work_item_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$demoWorkItemIds = @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

# Harvest known sibling-slice Receipt IDs (for cross-slice ID-collision tripwires).
$demoReceiptIds = @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

# All-slice raw-text harvest: the story's hard rule is "unique across ALL slices", not just the
# named sibling slices. Walk every *-slice.json in the implementation-artifacts dir (except this
# slice's own file), and collect every CWI-LOCAL-* / CR-LOCAL-* token mentioned anywhere in the
# raw JSON text. This catches ids embedded in proposedWorkItems, workItemsFlaggedForReview, evidence
# refs, idempotency keys, rationale prose, acceptanceMapping text, etc. — a superset of declared ids,
# which is the conservative set a new id must not collide with.
$allSliceWorkItemIds = [System.Collections.Generic.HashSet[string]]::new()
$allSliceReceiptIds = [System.Collections.Generic.HashSet[string]]::new()
$wiIdRegex = [regex]'CWI-LOCAL-[A-Za-z0-9_-]+'
$crIdRegex = [regex]'CR-LOCAL-[A-Za-z0-9_-]+'
$selfSliceBasename = (Split-Path -Leaf $ShellSlicePath)
$selfStoryKey = [string]$shell.storyKey
$selfStoryKeyRegex = [regex]'"storyKey"\s*:\s*"2-1-maintain-the-work-item-execution-shell"'
foreach ($sliceFile in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*-slice.json" -File)) {
  if ($sliceFile.Name -eq $selfSliceBasename) { continue }
  try {
    $rawText = Get-Content -LiteralPath $sliceFile.FullName -Raw
  }
  catch {
    Add-Issue $issues "Could not read sibling slice $($sliceFile.Name) for all-slice id harvest: $($_.Exception.Message)"
    continue
  }
  # Exclude this story's own slice even if it was copied/renamed into the dir, so the validator never
  # harvests its own ids as "sibling" ids (which would cause a false self-collision).
  if ($selfStoryKeyRegex.IsMatch($rawText)) { continue }
  foreach ($m in $wiIdRegex.Matches($rawText)) { [void]$allSliceWorkItemIds.Add($m.Value) }
  foreach ($m in $crIdRegex.Matches($rawText)) { [void]$allSliceReceiptIds.Add($m.Value) }
}

foreach ($sliceLoad in @(
    @{ Name = "manual-source-record-slice sampleRecords"; Count = $manualSources.Count },
    @{ Name = "outlook-source-reference-slice sampleRecords"; Count = $outlookSources.Count },
    @{ Name = "zero-multi-item-extraction-slice embeddedSampleSourceRecords"; Count = $story14EmbeddedSources.Count },
    @{ Name = "source-drift-supersession-slice superseding records"; Count = $driftSupersedingSources.Count },
    @{ Name = "proposed-work-item-extraction-slice proposedWorkItems"; Count = $story13Items.Count },
    @{ Name = "zero-multi-item-extraction-slice proposedWorkItems"; Count = $story14Items.Count }
  )) {
  if ($sliceLoad.Count -eq 0) {
    Add-Issue $issues "No records loaded from $($sliceLoad.Name); its cross-slice checks would silently no-op."
  }
}

if ($knownPriorSourceIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be loaded from the sibling slices; source-reference resolution checks would silently no-op."
}
if ($siblingWorkItemIds.Count -eq 0) {
  Add-Issue $issues "No sibling Work Item IDs could be loaded from the Story 1.3/1.4 slices; cross-slice ID-collision checks would silently no-op."
}
if ($demoReceiptIds.Count -eq 0) {
  Add-Issue $issues "No reserved receipt IDs could be loaded from state-transition-demo-evidence.json; receipt collision checks would silently no-op."
}
if ($allSliceWorkItemIds.Count -eq 0 -and $allSliceReceiptIds.Count -eq 0) {
  Add-Issue $issues "No CWI-LOCAL-* / CR-LOCAL-* ids could be harvested from any sibling *-slice.json; the all-slice uniqueness check would silently no-op."
}

$run = $shell.executionShell
if ($null -eq $run) {
  Add-Issue $issues "Shell slice must carry an executionShell block."
  Write-Host "Work item execution shell slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Shell run must declare a runId."
}
elseif (@([string]$story13Extraction.extractionRun.runId, [string]$story14Extraction.extractionRun.runId, [string]$drift.driftRun.runId) -contains [string]$run.runId) {
  Add-Issue $issues "Shell run must use a new local runId, not a sibling-slice runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Shell run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Shell run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Shell run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "zero-multi-item-extraction-slice.json", "source-drift-supersession-slice.json")) {
  if (@($run.inputSourceRecordsFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Shell run must reference $inputSlice as an input."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Shell run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("workItemIdentityIsCouncilLevelNotPlatform", "platformIdsOnlyInsideSourceReferences", "creationReceiptRequiredPerWorkItem", "stateTransitionsReceiptGatedToStory23", "queueViewExposesAllSevenStateGroups", "receiptsAreLocalContractEvidenceOnly")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Shell run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Shell run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# Derive manifest-required Work Item columns and pin the Council shell fields this story additionally requires.
$workItemTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilworkitem" } | Select-Object -First 1
$manifestRequiredWorkItemFields = @(@($workItemTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredWorkItemFields.Count -eq 0) {
  Add-Issue $issues "No required Work Item columns could be derived from manifest com_councilworkitem; required-field checks would silently no-op."
}
# Manifest-required columns, plus the Council shell fields Story 2.1 pins (owner candidate, approved owner,
# created receipt, and the NFR12 policy-flag declaration that is NOT optional on a Work Item).
$workItemRequiredFields = @($manifestRequiredWorkItemFields + @("com_owner_candidate", "com_approved_owner", "com_created_receipt", "com_policy_flags")) | Sort-Object -Unique

# Derive manifest-required Receipt columns and pin the Council receipt contract fields.
$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique

$workItems = @($run.workItems | Where-Object { $null -ne $_ })
if ($workItems.Count -lt 3) {
  Add-Issue $issues "Shell slice must include at least three Work Items covering different types, found $($workItems.Count)."
}

# Source-reference carrier fields that ARE permitted to hold Microsoft platform ids (NFR12 allows
# platform ids "only inside source references"). Read the declared allow-list from the slice's
# primaryIdentityProof so the isolation scan is bound to the actual receipts, not a hardcoded list.
$allowedPlatformIdCarrierFields = [System.Collections.Generic.HashSet[string]]::new()
$declaredCarrierFields = @($run.primaryIdentityProof.platformIdFieldsAllowedOnlyInSourceReferences | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($declaredCarrierFields.Count -eq 0) {
  Add-Issue $issues "primaryIdentityProof.platformIdFieldsAllowedOnlyInSourceReferences must declare a non-empty list of source-reference carrier fields; the platform-id isolation scan would otherwise be unboundable."
}
foreach ($carrier in $declaredCarrierFields) {
  [void]$allowedPlatformIdCarrierFields.Add([string]$carrier)
}

# Track computed (structural) NFR12 truths so the primaryIdentityProof booleans can be verified
# against reality rather than trusted as self-assertions.
$computedAllPrimaryIdsCouncilLevel = $true
$computedNoPrimaryIdGuidShaped = $true
$computedPlatformIdsIsolated = $true

$workItemIds = @{}
$workItemTypesSeen = @{}
$approvedOwnerPopulatedCount = 0
$queueGroupByItemId = @{}
foreach ($item in $workItems) {
  $itemId = [string]$item.com_council_work_item_id
  $subject = "Work Item $itemId"

  foreach ($field in $workItemRequiredFields) {
    if ($field -eq "com_approved_owner") {
      # Approved owner is "where known": the field must be declared (present), but may be null where unknown.
      if (-not (Test-FieldPresent -Record $item -Field $field)) {
        Add-Issue $issues "$subject missing required shell field (must be declared even when null where unknown): $field."
      }
      elseif (Test-HasNonEmptyField -Record $item -Field $field) {
        $approvedOwnerPopulatedCount += 1
      }
    }
    elseif (-not (Test-HasNonEmptyField -Record $item -Field $field)) {
      Add-Issue $issues "$subject missing required manifest/shell field: $field."
    }
  }

  if ([string]::IsNullOrWhiteSpace($itemId)) {
    Add-Issue $issues "Work Item must declare com_council_work_item_id."
    continue
  }
  if ($itemId -notmatch "^CWI-LOCAL-") {
    Add-Issue $issues "$subject must use Council-level CWI-LOCAL-* primary identity."
    $computedAllPrimaryIdsCouncilLevel = $false
  }
  if ($itemId -match $guidPattern) {
    Add-Issue $issues "$subject primary id must not be GUID-shaped; a Microsoft platform identifier may never serve as primary product identity (NFR12), found: $itemId."
    $computedNoPrimaryIdGuidShaped = $false
  }
  if ($workItemIds.ContainsKey($itemId)) {
    Add-Issue $issues "Duplicate Work Item ID in slice: $itemId."
  }
  else {
    $workItemIds[$itemId] = $item
  }
  if ($allSliceWorkItemIds.Contains($itemId)) {
    Add-Issue $issues "$subject collides with an existing CWI-LOCAL-* Work Item id harvested from a sibling *-slice.json; new ids must be unique across ALL slices."
  }
  if ($demoWorkItemIds -contains $itemId) {
    Add-Issue $issues "$subject collides with a reserved state-transition-demo Work Item ID."
  }

  if ($workItemTypes -notcontains [string]$item.com_type) {
    Add-Issue $issues "$subject com_type is not in manifest com_workitemtype vocabulary: $($item.com_type)."
  }
  else {
    $workItemTypesSeen[[string]$item.com_type] = $true
  }
  if ($stateGroups -notcontains [string]$item.com_state_group) {
    Add-Issue $issues "$subject com_state_group is not in manifest com_workitemstategroup vocabulary: $($item.com_state_group)."
  }
  elseif ([string]$item.com_state_group -ne "proposed") {
    Add-Issue $issues "$subject com_state_group must be proposed in Story 2.1; state transitions to other state groups are receipt-gated to Epic 2 Story 2.3, found: $($item.com_state_group)."
  }
  if ($riskClasses -notcontains [string]$item.com_risk_class) {
    Add-Issue $issues "$subject com_risk_class is not in manifest com_riskclass vocabulary: $($item.com_risk_class)."
  }
  if ($item.com_approval_required -isnot [bool] -or -not $item.com_approval_required) {
    Add-Issue $issues "$subject com_approval_required must be strict boolean true; Story 2.1 Work Items stay proposed until human approval."
  }
  if ([string]$item.com_semantic_contract_version -ne "2026-07-07") {
    Add-Issue $issues "$subject com_semantic_contract_version must be 2026-07-07."
  }

  $primarySourceId = [string]$item.com_primary_source_record
  if ([string]::IsNullOrWhiteSpace($primarySourceId)) {
    Add-Issue $issues "$subject must carry a non-empty com_primary_source_record."
  }
  elseif ($knownPriorSourceIds -notcontains $primarySourceId) {
    Add-Issue $issues "$subject com_primary_source_record must resolve to an existing CSR-* Source Record id from a sibling slice, found: $primarySourceId."
  }

  Test-ConfidenceInRange -Issues $issues -Record $item -Field "com_owner_candidate_confidence" -Subject $subject
  Test-NoPriorMutationFields -Issues $issues -Record $item -Subject $subject

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($item.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 2.1 Work Items are local contract evidence only."
    }
  }
  # com_policy_flags is a required field (enforced above) and must declare the NFR12 invariant token.
  if ([string]$item.com_policy_flags -notmatch [regex]::Escape("primary_id_is_council_level_not_platform")) {
    Add-Issue $issues "$subject com_policy_flags must declare primary_id_is_council_level_not_platform; NFR12 is a Story 2.1 shell invariant and is not optional."
  }

  # Platform-id isolation (NFR12): scan every string-valued Work Item field EXCEPT the declared
  # source-reference carrier fields, and reject any value whose shape matches a Microsoft platform
  # id (GUID / Dataverse row id / Graph activity id / Outlook message id). This proves platform ids
  # appear only inside source references, rather than self-asserting it via a boolean.
  foreach ($property in @($item.PSObject.Properties)) {
    if ($allowedPlatformIdCarrierFields -contains $property.Name) { continue }
    $value = $property.Value
    if ($null -eq $value -or $value -isnot [string]) { continue }
    foreach ($pattern in $platformIdScanPatterns) {
      if ($value -match $pattern) {
        Add-Issue $issues "$subject field '$($property.Name)' carries a Microsoft-platform-id-shaped value '$value'; platform ids may only appear inside source-reference carrier fields, never as Work Item identity or in shell prose (NFR12)."
        $computedPlatformIdsIsolated = $false
      }
    }
  }
}

if ($workItemTypesSeen.Count -lt 3) {
  Add-Issue $issues "Shell slice must cover at least three distinct com_workitemtype values, found $($workItemTypesSeen.Count) distinct types."
}
if ($approvedOwnerPopulatedCount -lt 1) {
  Add-Issue $issues "At least one Work Item must carry a non-empty com_approved_owner; the shell must prove the approved-owner field is populated where known."
}

# Work Item Source Links: each Work Item must be bound to its primary (or superseding) source.
$workItemSourceLinks = @($run.workItemSourceLinks | Where-Object { $null -ne $_ })
$linkByItemId = @{}
foreach ($link in $workItemSourceLinks) {
  $linkSubject = "Work Item source link $($link.com_name)"
  if (-not (Test-HasNonEmptyField -Record $link -Field "com_name")) {
    Add-Issue $issues "Work Item source link must carry a non-empty com_name."
  }
  $linkItemId = [string]$link.com_work_item
  $linkSourceId = [string]$link.com_source_record
  if ([string]::IsNullOrWhiteSpace($linkItemId) -or -not $workItemIds.ContainsKey($linkItemId)) {
    Add-Issue $issues "$linkSubject references an unknown Work Item: $linkItemId."
  }
  if ([string]::IsNullOrWhiteSpace($linkSourceId) -or $knownPriorSourceIds -notcontains $linkSourceId) {
    Add-Issue $issues "$linkSubject must bind a source that resolves to an existing CSR-* Source Record id from a sibling slice, found: $linkSourceId."
  }
  if ($workItemSourceRoles -notcontains [string]$link.com_source_role) {
    Add-Issue $issues "$linkSubject com_source_role is not in manifest vocabulary: $($link.com_source_role)."
  }
  if (-not [string]::IsNullOrWhiteSpace($linkItemId)) {
    $linkByItemId[$linkItemId] = $link
  }
  Test-ConfidenceInRange -Issues $issues -Record $link -Field "com_confidence" -Subject $linkSubject
}
foreach ($itemId in @($workItemIds.Keys)) {
  if (-not $linkByItemId.ContainsKey($itemId)) {
    Add-Issue $issues "Work Item $itemId must be bound to its source by a workItemSourceLinks entry."
  }
  else {
    $link = $linkByItemId[$itemId]
    if ([string]$link.com_source_record -ne [string]$workItemIds[$itemId].com_primary_source_record) {
      Add-Issue $issues "Work Item $itemId workItemSourceLinks entry must reference the same source as com_primary_source_record ($($workItemIds[$itemId].com_primary_source_record)), found: $($link.com_source_record)."
    }
  }
}

# Creation receipts: one per Work Item, verb proposed, full manifest + contract fields.
$receipts = @($run.creationReceipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt $workItems.Count) {
  Add-Issue $issues "Shell slice must include one creation receipt per Work Item; found $($receipts.Count) receipts for $($workItems.Count) Work Items."
}
$sliceReceiptIds = @{}
$seenIdempotencyKeys = @{}
$receiptByItemId = @{}
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
    if ($receiptId -notmatch "^CR-LOCAL-") {
      Add-Issue $issues "$subject must use Council-level CR-LOCAL-* identity (the hard rule), found: $receiptId."
    }
    if ($sliceReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "Duplicate receipt ID in slice: $receiptId."
    }
    else {
      $sliceReceiptIds[$receiptId] = $true
    }
    if ($demoReceiptIds -contains $receiptId) {
      Add-Issue $issues "$subject collides with a reserved state-transition-demo receipt ID."
    }
    if ($allSliceReceiptIds.Contains($receiptId)) {
      Add-Issue $issues "$subject collides with an existing CR-LOCAL-* receipt id harvested from a sibling *-slice.json; new ids must be unique across ALL slices."
    }
  }

  if ($receiptVerbs -notcontains $receipt.com_verb) {
    Add-Issue $issues "$subject verb is not in manifest com_receiptverb vocabulary: $($receipt.com_verb)."
  }
  elseif ($receipt.com_verb -ne "proposed") {
    Add-Issue $issues "$subject must use verb proposed for Story 2.1 creation receipts, found: $($receipt.com_verb)."
  }
  if ($actorTypes -notcontains $receipt.com_actor_type) {
    Add-Issue $issues "$subject actor type is not in manifest com_actortype vocabulary: $($receipt.com_actor_type)."
  }
  if ($receiptResults -notcontains $receipt.com_result) {
    Add-Issue $issues "$subject result is not in manifest com_receiptresult vocabulary: $($receipt.com_result)."
  }
  elseif ($receipt.com_result -ne "accepted") {
    Add-Issue $issues "$subject com_result must be accepted for creation receipts that bring a Work Item into existence, found: $($receipt.com_result)."
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

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 2.1 receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 2.1 receipts are local contract evidence only."
      }
    }
  }

  $receiptItemId = [string]$receipt.com_work_item
  if ([string]::IsNullOrWhiteSpace($receiptItemId) -or -not $workItemIds.ContainsKey($receiptItemId)) {
    Add-Issue $issues "$subject com_work_item must reference a known Work Item in this slice, found: $receiptItemId."
  }
  elseif ($receiptByItemId.ContainsKey($receiptItemId)) {
    Add-Issue $issues "Work Item $receiptItemId must have exactly one creation receipt; found more than one."
  }
  else {
    $receiptByItemId[$receiptItemId] = $receipt
  }
}

# Every Work Item must reference a creation receipt, and that receipt must exist and bind back to the Work Item.
foreach ($itemId in @($workItemIds.Keys)) {
  $createdReceiptId = [string]$workItemIds[$itemId].com_created_receipt
  if ([string]::IsNullOrWhiteSpace($createdReceiptId)) {
    Add-Issue $issues "Work Item $itemId must carry a non-empty com_created_receipt."
  }
  elseif (-not $sliceReceiptIds.ContainsKey($createdReceiptId)) {
    Add-Issue $issues "Work Item $itemId com_created_receipt must reference a creation receipt in this slice, found: $createdReceiptId."
  }
  elseif (-not $receiptByItemId.ContainsKey($itemId) -or [string]$receiptByItemId[$itemId].com_receipt_id -ne $createdReceiptId) {
    Add-Issue $issues "Work Item $itemId com_created_receipt must reference the creation receipt bound back to $itemId, found: $createdReceiptId."
  }
}

# queueView: all seven state groups present, each declared empty or populated consistently with work item state groups.
$queueView = $run.queueView
if ($null -eq $queueView) {
  Add-Issue $issues "Shell slice must carry a queueView block."
}
else {
  if ($null -eq $queueView.stateGroups) {
    Add-Issue $issues "Shell slice queueView must declare a stateGroups block."
  }
  else {
    $queueGroupByState = @{}
    foreach ($itemId in @($workItemIds.Keys)) {
      $stateGroup = [string]$workItemIds[$itemId].com_state_group
      if (-not [string]::IsNullOrWhiteSpace($stateGroup)) {
        if (-not $queueGroupByState.ContainsKey($stateGroup)) {
          $queueGroupByState[$stateGroup] = [System.Collections.Generic.List[string]]::new()
        }
        $queueGroupByState[$stateGroup].Add($itemId) | Out-Null
      }
    }
    foreach ($state in @("proposed", "approved", "blocked", "held", "in_review", "completed", "failed")) {
      $group = $queueView.stateGroups.PSObject.Properties | Where-Object { $_.Name -eq $state } | Select-Object -First 1
      if (-not $group) {
        Add-Issue $issues "Shell slice queueView.stateGroups must declare the state group: $state."
        continue
      }
      $groupValue = $group.Value
      if ($null -eq $groupValue) {
        Add-Issue $issues "Shell slice queueView.stateGroups.$state must be a non-null object with declaredEmpty and workItems."
        continue
      }
      $declaredEmpty = $groupValue.declaredEmpty
      if ($declaredEmpty -isnot [bool]) {
        Add-Issue $issues "Shell slice queueView.stateGroups.$state.declaredEmpty must be a strict boolean."
      }
      $queueItems = @(@($groupValue.workItems | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }))
      if ($declaredEmpty -eq $true) {
        if ($queueItems.Count -ne 0) {
          Add-Issue $issues "Shell slice queueView.stateGroups.$state is declaredEmpty but lists $($queueItems.Count) Work Items."
        }
        if ($queueGroupByState.ContainsKey($state) -and @($queueGroupByState[$state]).Count -gt 0) {
          Add-Issue $issues "Shell slice queueView.stateGroups.$state is declaredEmpty but $($queueGroupByState[$state].Count) Work Item(s) carry this state group."
        }
        if (-not (Test-HasNonEmptyField -Record $groupValue -Field "note")) {
          Add-Issue $issues "Shell slice queueView.stateGroups.$state must carry a non-empty note explaining why it is empty-but-declared."
        }
      }
      elseif ($declaredEmpty -eq $false) {
        if ($queueItems.Count -eq 0) {
          Add-Issue $issues "Shell slice queueView.stateGroups.$state is declared populated but lists no Work Items."
        }
        foreach ($listedId in $queueItems) {
          if (-not $workItemIds.ContainsKey($listedId)) {
            Add-Issue $issues "Shell slice queueView.stateGroups.$state lists an unknown Work Item: $listedId."
          }
          elseif ([string]$workItemIds[$listedId].com_state_group -ne $state) {
            Add-Issue $issues "Shell slice queueView.stateGroups.$state lists $listedId but its com_state_group is $($workItemIds[$listedId].com_state_group)."
          }
        }
        $expectedIds = @()
        if ($queueGroupByState.ContainsKey($state)) {
          $expectedIds = @($queueGroupByState[$state])
        }
        $missing = @($expectedIds | Where-Object { $queueItems -notcontains $_ })
        foreach ($missingId in $missing) {
          Add-Issue $issues "Shell slice queueView.stateGroups.$state must list Work Item $missingId (it carries this state group)."
        }
      }
    }
    # Reject any extra (non-manifest) state group keys.
    $allowedStates = @("proposed", "approved", "blocked", "held", "in_review", "completed", "failed")
    foreach ($groupProperty in @($queueView.stateGroups.PSObject.Properties)) {
      if ($allowedStates -notcontains $groupProperty.Name) {
        Add-Issue $issues "Shell slice queueView.stateGroups must not declare a non-manifest state group: $($groupProperty.Name)."
      }
    }
  }
}

# Primary identity proof: primary ids are Council-level, never GUID-shaped; platform ids only inside source references.
$primaryIdentityProof = $run.primaryIdentityProof
if ($null -eq $primaryIdentityProof) {
  Add-Issue $issues "Shell slice must carry a primaryIdentityProof block."
}
else {
  if (-not (Test-HasNonEmptyField -Record $primaryIdentityProof -Field "primaryIdPattern")) {
    Add-Issue $issues "primaryIdentityProof must declare a primaryIdPattern."
  }
  elseif ([string]$primaryIdentityProof.primaryIdPattern -ne "CWI-LOCAL-*") {
    Add-Issue $issues "primaryIdentityProof.primaryIdPattern must be CWI-LOCAL-*, found: $($primaryIdentityProof.primaryIdPattern)."
  }
  if ($primaryIdentityProof.primaryIdsAreCouncilLevelNotPlatform -isnot [bool] -or -not $primaryIdentityProof.primaryIdsAreCouncilLevelNotPlatform) {
    Add-Issue $issues "primaryIdentityProof.primaryIdsAreCouncilLevelNotPlatform must be strict boolean true."
  }
  elseif ($primaryIdentityProof.primaryIdsAreCouncilLevelNotPlatform -ne $computedAllPrimaryIdsCouncilLevel) {
    Add-Issue $issues "primaryIdentityProof.primaryIdsAreCouncilLevelNotPlatform is asserted as $($primaryIdentityProof.primaryIdsAreCouncilLevelNotPlatform) but the structural scan of Work Item primary ids computed $computedAllPrimaryIdsCouncilLevel; the proof must match the receipts."
  }
  if ($primaryIdentityProof.platformIdsAppearOnlyInsideSourceReferences -isnot [bool] -or -not $primaryIdentityProof.platformIdsAppearOnlyInsideSourceReferences) {
    Add-Issue $issues "primaryIdentityProof.platformIdsAppearOnlyInsideSourceReferences must be strict boolean true."
  }
  elseif ($primaryIdentityProof.platformIdsAppearOnlyInsideSourceReferences -ne $computedPlatformIdsIsolated) {
    Add-Issue $issues "primaryIdentityProof.platformIdsAppearOnlyInsideSourceReferences is asserted as $($primaryIdentityProof.platformIdsAppearOnlyInsideSourceReferences) but the structural platform-id isolation scan computed $computedPlatformIdsIsolated; the proof must match the receipts."
  }
  if ($primaryIdentityProof.noWorkItemPrimaryIdIsGuidShaped -isnot [bool] -or -not $primaryIdentityProof.noWorkItemPrimaryIdIsGuidShaped) {
    Add-Issue $issues "primaryIdentityProof.noWorkItemPrimaryIdIsGuidShaped must be strict boolean true."
  }
  elseif ($primaryIdentityProof.noWorkItemPrimaryIdIsGuidShaped -ne $computedNoPrimaryIdGuidShaped) {
    Add-Issue $issues "primaryIdentityProof.noWorkItemPrimaryIdIsGuidShaped is asserted as $($primaryIdentityProof.noWorkItemPrimaryIdIsGuidShaped) but the structural GUID scan computed $computedNoPrimaryIdGuidShaped; the proof must match the receipts."
  }
  # platformIdFieldsAllowedOnlyInSourceReferences: must be a non-empty array, and every declared
  # carrier field must actually exist as a known manifest Work Item / source-link column so a lying
  # slice cannot widen the exemption with a phantom field name.
  $carrierFields = @($primaryIdentityProof.PSObject.Properties | Where-Object { $_.Name -eq "platformIdFieldsAllowedOnlyInSourceReferences" })
  if ($carrierFields.Count -eq 0) {
    Add-Issue $issues "primaryIdentityProof must declare platformIdFieldsAllowedOnlyInSourceReferences so the platform-id isolation scan is bound to the actual carrier fields."
  }
  else {
    $carrierList = @($primaryIdentityProof.platformIdFieldsAllowedOnlyInSourceReferences | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($carrierList.Count -eq 0) {
      Add-Issue $issues "primaryIdentityProof.platformIdFieldsAllowedOnlyInSourceReferences must list at least one source-reference carrier field."
    }
    foreach ($carrier in $carrierList) {
      if ($knownColumnNames -notcontains [string]$carrier) {
        Add-Issue $issues "primaryIdentityProof.platformIdFieldsAllowedOnlyInSourceReferences lists an unknown column '$carrier'; carrier fields must be real manifest columns."
      }
    }
  }
  # primaryIdShape: must carry substantive content naming the invariant, not a one-character filler.
  if (-not (Test-HasNonEmptyField -Record $primaryIdentityProof -Field "primaryIdShape")) {
    Add-Issue $issues "primaryIdentityProof must carry a non-empty primaryIdShape."
  }
  else {
    $shape = [string]$primaryIdentityProof.primaryIdShape
    if ($shape.Length -lt 40) {
      Add-Issue $issues "primaryIdentityProof.primaryIdShape must carry substantive prose describing the primary-id invariant, found only $($shape.Length) characters."
    }
    foreach ($requiredToken in @("CWI-LOCAL", "GUID", "platform")) {
      if ($shape -notlike "*$requiredToken*") {
        Add-Issue $issues "primaryIdentityProof.primaryIdShape must reference the token '$requiredToken' so the proof is not a free-text placeholder."
      }
    }
  }
}

# Deferred Work Item state changes: every Work Item must have a deferred entry, and it must name the receipt gate.
$workItemStateChangesDeferred = @($run.workItemStateChangesDeferred | Where-Object { $null -ne $_ })
$deferredByItemId = @{}
foreach ($deferred in $workItemStateChangesDeferred) {
  Test-NoPriorMutationFields -Issues $issues -Record $deferred -Subject "Deferred Work Item state change $($deferred.workItem)"
  $deferredItemId = [string]$deferred.workItem
  if ([string]::IsNullOrWhiteSpace($deferredItemId) -or -not $workItemIds.ContainsKey($deferredItemId)) {
    Add-Issue $issues "Deferred Work Item state change must name a known Work Item in this slice, found: $deferredItemId."
  }
  else {
    if ($deferredByItemId.ContainsKey($deferredItemId)) {
      Add-Issue $issues "Duplicate deferred state-change entry for Work Item: $deferredItemId."
    }
    $deferredByItemId[$deferredItemId] = $deferred
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred Work Item state change for $deferredItemId must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred Work Item state change for $deferredItemId must state that any state move is receipt-gated."
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate") -or ([string]$deferred.deferredUpdate -notmatch "Story 2.3")) {
    Add-Issue $issues "Deferred Work Item state change for $deferredItemId must reference the Epic 2 Story 2.3 receipt gate."
  }
}
foreach ($itemId in @($workItemIds.Keys)) {
  if (-not $deferredByItemId.ContainsKey($itemId)) {
    Add-Issue $issues "Missing deferred Work Item state change entry for $itemId."
  }
}

foreach ($criterion in @(1, 2, 3)) {
  $mapping = @($shell.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
  if (-not $mapping) {
    Add-Issue $issues "Missing acceptance mapping for AC $criterion."
  }
  else {
    if (@($mapping.localEvidence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -lt 2) {
      Add-Issue $issues "Acceptance mapping for AC $criterion must list at least two non-empty localEvidence entries; a single bullet cannot prove a Slice-must-prove criterion."
    }
    if (-not (Test-HasNonEmptyField -Record $mapping -Field "tenantEvidenceRequired")) {
      Add-Issue $issues "Acceptance mapping for AC $criterion must state tenantEvidenceRequired."
    }
  }
}
# Reject extra/unknown acceptanceMapping criteria so the three Slice-must-prove items cannot be
# silently renumbered or padded.
foreach ($mapping in @($shell.acceptanceMapping)) {
  if (@(1, 2, 3) -notcontains [int]$mapping.acceptanceCriterion) {
    Add-Issue $issues "Acceptance mapping declares an unknown acceptanceCriterion $($mapping.acceptanceCriterion); Story 2.1 has exactly three Slice-must-prove criteria (1, 2, 3)."
  }
}

if ($issues.Count -gt 0) {
  Write-Host "Work item execution shell slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Work item execution shell slice validation succeeded."
Write-Host "Work Items: $($workItems.Count)"
Write-Host "Creation receipts: $($receipts.Count)"
Write-Host "Work Item source links: $($workItemSourceLinks.Count)"
Write-Host "Queue state groups declared: $((@($queueView.stateGroups.PSObject.Properties)).Count)"
Write-Host "WORK_ITEM_EXECUTION_SHELL_SLICE_VALIDATE_OK"
