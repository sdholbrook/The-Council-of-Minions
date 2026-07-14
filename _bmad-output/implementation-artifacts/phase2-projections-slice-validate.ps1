param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$SlicePath = "$PSScriptRoot\phase2-projections-slice.json",
  [string]$SemanticContractProjectionSlicePath = "$PSScriptRoot\semantic-contract-projection-slice.json",
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

function Get-ComparableInstant {
  param($Value)

  if ($null -eq $Value) { return $null }
  if ($Value -is [datetime]) {
    if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }
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
    Write-Host "Phase 2 projections slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

function Invoke-CollectSiblingIds {
  param(
    [Parameter(Mandatory = $false)][AllowNull()]$Node,
    [Parameter(Mandatory = $true)][hashtable]$WorkItems,
    [Parameter(Mandatory = $true)][hashtable]$Receipts,
    [Parameter(Mandatory = $true)][hashtable]$Keys,
    [Parameter(Mandatory = $true)][hashtable]$SourceRecords,
    [Parameter(Mandatory = $true)][hashtable]$RunIds,
    [Parameter(Mandatory = $true)][hashtable]$ProjectionIds
  )

  if ($null -eq $Node) { return }
  if ($Node -is [System.Collections.IList]) {
    foreach ($item in $Node) {
      Invoke-CollectSiblingIds -Node $item -WorkItems $WorkItems -Receipts $Receipts -Keys $Keys -SourceRecords $SourceRecords -RunIds $RunIds -ProjectionIds $ProjectionIds
    }
    return
  }
  if ($Node -is [pscustomobject]) {
    foreach ($prop in $Node.PSObject.Properties) {
      switch ($prop.Name) {
        "com_council_work_item_id" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $WorkItems[$id] = $true }
          break
        }
        "com_receipt_id" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $Receipts[$id] = $true }
          break
        }
        "com_idempotency_key" {
          $k = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($k)) { $Keys[$k] = $true }
          break
        }
        "com_council_source_record_id" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $SourceRecords[$id] = $true }
          break
        }
        "runId" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $RunIds[$id] = $true }
          break
        }
        "projectionId" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $ProjectionIds[$id] = $true }
          break
        }
        "workItemIds" {
          if ($prop.Value -is [System.Collections.IList]) {
            foreach ($v in $prop.Value) { $id = [string]$v; if (-not [string]::IsNullOrWhiteSpace($id)) { $WorkItems[$id] = $true } }
          }
          break
        }
        "receiptIds" {
          if ($prop.Value -is [System.Collections.IList]) {
            foreach ($v in $prop.Value) { $id = [string]$v; if (-not [string]::IsNullOrWhiteSpace($id)) { $Receipts[$id] = $true } }
          }
          break
        }
        default {
          Invoke-CollectSiblingIds -Node $prop.Value -WorkItems $WorkItems -Receipts $Receipts -Keys $Keys -SourceRecords $SourceRecords -RunIds $RunIds -ProjectionIds $ProjectionIds
        }
      }
    }
  }
}

function Test-NoAuthorityFields {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$Subject
  )

  $forbidden = @(
    "com_state_group",
    "com_approval_required",
    "com_approved_owner",
    "approved",
    "approvalStatus",
    "workflowState",
    "com_owner",
    "stateGroup",
    "com_status",
    "com_recordstatus",
    "recordStatus",
    "com_record_status",
    "com_review_state",
    "reviewState"
  )
  foreach ($field in $forbidden) {
    if ($Record.PSObject.Properties.Name -contains $field) {
      Add-Issue $Issues "$Subject must not claim workflow/approval authority via field '$field'; Phase-2 projections never own workflow state."
    }
  }
}

foreach ($path in @($ManifestPath, $SlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $Story15DriftPath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required Phase 2 projections validation input not found: $path"
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
$issues = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------------------
# Manifest vocabulary
# ---------------------------------------------------------------------------

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
  Add-Issue $issues "Manifest com_receiptverb is missing the premature-activation denial verb: policy_denied."
}
if ($receiptVerbs -notcontains "reviewed") {
  Add-Issue $issues "Manifest com_receiptverb is missing the deferred-plan catalog verb: reviewed."
}

# ---------------------------------------------------------------------------
# Slice identity and guards
# ---------------------------------------------------------------------------

if ($slice.storyKey -ne "5-6-manage-phase-2-knowledge-and-analytics-projections") {
  Add-Issue $issues "Phase 2 projections slice storyKey must be 5-6-manage-phase-2-knowledge-and-analytics-projections."
}
if ([string]$slice.status -notmatch "^local-contract") {
  Add-Issue $issues "Phase 2 projections slice status must declare local contract evidence, found: $($slice.status)."
}

$requiredGuards = @(
  "noTenantWrites",
  "noOutboundAction",
  "noApprovalExecution",
  "requiresExplicitHumanApprovalForExecution",
  "receiptsAreLocalContractEvidenceOnly",
  "phase2ProjectionsDeferredUntilMvpContractsStable",
  "projectionsNeverOwnWorkflowState",
  "prematureActivationPolicyDenied",
  "planesAreProjectionsOnly",
  "noCanonicalAuthoringInPlanes",
  "semanticContractProjectionCrossReferencedNotDuplicated",
  "noPhase2PlaneWriteInThisSlice"
)
foreach ($guard in $requiredGuards) {
  if (-not ($slice.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Phase 2 projections slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($slice.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Phase 2 projections guard must be boolean true: $($guardProperty.Name)."
  }
}

# ---------------------------------------------------------------------------
# Sibling source-record resolution (known CSR ids for receipt links)
# ---------------------------------------------------------------------------

$manualSources = @($manualSlice.manualCapture.sampleRecords | Where-Object { $null -ne $_ })
$outlookSources = @($outlookSlice.outlookCapture.sampleRecords | Where-Object { $null -ne $_ })
$story14EmbeddedSources = @($story14Extraction.extractionRun.embeddedSampleSourceRecords | Where-Object { $null -ne $_ })
$priorSourcesById = @{}
foreach ($record in @($manualSources + $outlookSources + $story14EmbeddedSources)) {
  $recordId = [string]$record.com_council_source_record_id
  if ([string]::IsNullOrWhiteSpace($recordId)) { continue }
  if (-not $priorSourcesById.ContainsKey($recordId)) {
    $priorSourcesById[$recordId] = $record
  }
}
foreach ($supersession in @($story15Drift.driftRun.supersessions | Where-Object { $null -ne $_ })) {
  $supersedingId = [string]$supersession.supersedingRecord.com_council_source_record_id
  if (-not [string]::IsNullOrWhiteSpace($supersedingId) -and -not $priorSourcesById.ContainsKey($supersedingId)) {
    $priorSourcesById[$supersedingId] = $supersession.supersedingRecord
  }
}
$knownSourceIds = @($priorSourcesById.Keys)

foreach ($sliceLoad in @(
    @{ Name = "manual-source-record-slice sampleRecords"; Count = $manualSources.Count },
    @{ Name = "outlook-source-reference-slice sampleRecords"; Count = $outlookSources.Count },
    @{ Name = "zero-multi-item-extraction-slice embeddedSampleSourceRecords"; Count = $story14EmbeddedSources.Count },
    @{ Name = "state-transition-demo-evidence presence"; Count = @($demoEvidence.receiptIds).Count }
  )) {
  if ($sliceLoad.Count -eq 0) {
    Add-Issue $issues "No records loaded from $($sliceLoad.Name); its cross-slice checks would silently no-op."
  }
}

# ---------------------------------------------------------------------------
# All-slice id harvest (live collision surface) — MINTED ids must be unique,
# REFERENCED ids must resolve. Harvest is LIVE from $PSScriptRoot, never a
# hardcoded id list.
# ---------------------------------------------------------------------------

$allSliceWorkItemIds = @{}
$allSliceReceiptIds = @{}
$allSliceIdempotencyKeys = @{}
$allSliceSourceIds = @{}
$allSliceRunIds = @{}
$allSliceProjectionIds = @{}
$selfSliceBasename = (Split-Path -Leaf $SlicePath)
$siblingSliceFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.json" -File |
  Where-Object { $_.Name -ne "dataverse-mvp-schema-manifest.json" -and $_.Name -ne $selfSliceBasename } |
  ForEach-Object { $_.FullName })
if ($siblingSliceFiles.Count -eq 0) {
  Add-Issue $issues "No sibling slice JSON files found in $PSScriptRoot; all-slice id-collision checks would silently no-op."
}
foreach ($siblingFile in $siblingSliceFiles) {
  $siblingJson = Read-JsonInput -Path $siblingFile
  Invoke-CollectSiblingIds -Node $siblingJson -WorkItems $allSliceWorkItemIds -Receipts $allSliceReceiptIds -Keys $allSliceIdempotencyKeys -SourceRecords $allSliceSourceIds -RunIds $allSliceRunIds -ProjectionIds $allSliceProjectionIds
}

if ($allSliceReceiptIds.Count -eq 0) {
  Add-Issue $issues "No CR-* ids harvested from sibling slices; receipt collision checks would silently no-op."
}
if ($allSliceSourceIds.Count -eq 0) {
  Add-Issue $issues "No CSR-* ids harvested from sibling slices; source-record collision checks would silently no-op."
}
if ($allSliceProjectionIds.Count -eq 0) {
  Add-Issue $issues "No projection ids harvested from sibling slices; projection cross-reference resolution checks would silently no-op."
}

# 4-5 cross-reference target: load when present (referenced, not duplicated).
$semanticSlicePresent = (Test-Path -LiteralPath $SemanticContractProjectionSlicePath)
$semanticProjectionIds = @{}
if ($semanticSlicePresent) {
  $semanticSlice = Read-JsonInput -Path $SemanticContractProjectionSlicePath
  if ($semanticSlice.storyKey -ne "4-5-project-the-semantic-contract-without-dual-authoring") {
    Add-Issue $issues "Referenced semantic-contract-projection-slice storyKey must be 4-5-project-the-semantic-contract-without-dual-authoring, found: $($semanticSlice.storyKey)."
  }
  foreach ($proj in @($semanticSlice.projectionRun.projectionManifest | Where-Object { $null -ne $_ })) {
    $projIdVal = [string]$proj.projectionId
    if (-not [string]::IsNullOrWhiteSpace($projIdVal)) { $semanticProjectionIds[$projIdVal] = $true }
  }
  if ($semanticProjectionIds.Count -eq 0) {
    Add-Issue $issues "Referenced 4-5 slice yielded no projection ids; cross-reference resolution checks would silently no-op."
  }
  if (-not ($semanticSlice.guards.PSObject.Properties.Name -contains "planesAreProjectionsOnly") -or $semanticSlice.guards.planesAreProjectionsOnly -isnot [bool] -or -not $semanticSlice.guards.planesAreProjectionsOnly) {
    Add-Issue $issues "Referenced 4-5 slice must guard planesAreProjectionsOnly=true (planes are projections only)."
  }
}
else {
  Add-Issue $issues "semantic-contract-projection-slice.json is referenced by every Phase-2 plan but is absent; 4-5 cross-reference resolution cannot proceed."
}

# ---------------------------------------------------------------------------
# Phase 2 projection run header
# ---------------------------------------------------------------------------

$run = $slice.phase2ProjectionRun
if ($null -eq $run) {
  Add-Issue $issues "Phase 2 projections slice must carry a phase2ProjectionRun block."
  $run = [pscustomobject]@{}
}

if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Phase 2 projection run must carry a non-empty runId."
}
elseif ($allSliceRunIds.ContainsKey([string]$run.runId)) {
  Add-Issue $issues "Phase 2 projection run runId collides with a runId harvested from a sibling slice: $($run.runId)."
}

if ($actorTypes -notcontains [string]$run.actorType) {
  Add-Issue $issues "Phase 2 projection run actorType is not in manifest com_actortype vocabulary: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis", "semanticContractVersion", "canonicalSource", "deferredUntil")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Phase 2 projection run must carry a non-empty ${field}."
  }
}
if ([string]$run.canonicalSource -ne "council-semantic-contract") {
  Add-Issue $issues "Phase 2 projection run canonicalSource must be 'council-semantic-contract', found: $($run.canonicalSource)."
}
if ([string]$run.deferredUntil -ne "mvp-contracts-stable") {
  Add-Issue $issues "Phase 2 projection run deferredUntil must be 'mvp-contracts-stable', found: $($run.deferredUntil)."
}
foreach ($expectedInput in @("dataverse-mvp-schema-manifest.json", "semantic-contract-projection-slice.json")) {
  if (@($run.inputVocabularyFrom) -notcontains $expectedInput) {
    Add-Issue $issues "Phase 2 projection run must reference $expectedInput as an input."
  }
}

$policy = $run.decisionPolicy
if ($null -eq $policy) {
  Add-Issue $issues "Phase 2 projection run must carry decisionPolicy."
}
else {
  foreach ($flag in @("phase2ProjectionsDeferredUntilMvpContractsStable", "projectionPlansNeverOwnWorkflowState", "prematureActivationYieldsPolicyDenial", "stabilityCriteriaMustBeNamedPerPlan", "planesAreProjectionsOnly", "semanticContractProjectionSliceReferencedNotDuplicated", "livePhase2PlaneWritesReceiptGated")) {
    if (-not ($policy.PSObject.Properties.Name -contains $flag) -or $policy.$flag -isnot [bool] -or -not $policy.$flag) {
      Add-Issue $issues "decisionPolicy.$flag must be strict boolean true."
    }
  }
}

# ---------------------------------------------------------------------------
# Projection plans — the three Phase-2 surfaces
# ---------------------------------------------------------------------------

$plans = @($run.projectionPlans | Where-Object { $null -ne $_ })
if ($plans.Count -ne 3) {
  Add-Issue $issues "Phase 2 projection run must catalog exactly three projection plans (Fabric knowledge, Copilot Studio surface, analytics), found $($plans.Count)."
}

$requiredPlanFields = @(
  "planId",
  "planName",
  "phase",
  "targetSurface",
  "deferredUntil",
  "triggeringStabilityCriteria",
  "ownsWorkflowState",
  "planRationale",
  "referencedSemanticContractProjectionSlice",
  "referencedProjectionIds",
  "plannedProjectionSurface",
  "liveWriteDeferredTo"
)

$expectedSurfaces = @("fabric-iq-ontology", "copilot-studio-surface", "analytics-warehouse")
$slicePlanIds = @{}
$seenPlanIds = @{}
$surfacesSeen = @{}
foreach ($plan in $plans) {
  $planId = [string]$plan.planId
  $subject = "Projection plan $planId"
  if ([string]::IsNullOrWhiteSpace($planId)) {
    Add-Issue $issues "Projection plan must carry a non-empty planId."
    $subject = "Projection plan (unnamed)"
  }
  else {
    if ($seenPlanIds.ContainsKey($planId)) {
      Add-Issue $issues "Duplicate planId in this slice: $planId."
    }
    else {
      $seenPlanIds[$planId] = $true
      $slicePlanIds[$planId] = $plan
    }
    # MINTED plan ids must be unique across ALL slices (plan ids are minted identifiers).
    if ($allSliceWorkItemIds.ContainsKey($planId) -or $allSliceReceiptIds.ContainsKey($planId) -or $allSliceSourceIds.ContainsKey($planId) -or $allSliceRunIds.ContainsKey($planId) -or $allSliceProjectionIds.ContainsKey($planId)) {
      Add-Issue $issues "$subject planId collides with an id harvested from a sibling slice (must be unique across all slices): $planId."
    }
  }

  foreach ($field in $requiredPlanFields) {
    if (-not (Test-HasNonEmptyField -Record $plan -Field $field)) {
      Add-Issue $issues "$subject missing required field: $field."
    }
  }

  # phase must be strict numeric integer 2 (not boolean, not string). ConvertFrom-Json
  # may yield [int] or [long] depending on engine; both are acceptable integer carriers.
  if ($plan.PSObject.Properties.Name -contains "phase") {
    $phaseVal = $plan.phase
    $phaseParsed = 0
    if ($phaseVal -is [bool] -or $phaseVal -is [string]) {
      Add-Issue $issues "$subject phase must be strict integer 2, found: $phaseVal."
    }
    elseif (-not [int]::TryParse([string]$phaseVal, [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$phaseParsed) -or $phaseParsed -ne 2) {
      Add-Issue $issues "$subject phase must be strict integer 2, found: $phaseVal."
    }
  }

  if ([string]$plan.deferredUntil -ne "mvp-contracts-stable") {
    Add-Issue $issues "$subject deferredUntil must be 'mvp-contracts-stable', found: $($plan.deferredUntil)."
  }

  # ownsWorkflowState must be strict boolean false.
  if ($plan.PSObject.Properties.Name -notcontains "ownsWorkflowState" -or $plan.ownsWorkflowState -isnot [bool] -or $plan.ownsWorkflowState) {
    Add-Issue $issues "$subject ownsWorkflowState must be strict boolean false; Phase-2 projections never own workflow state."
  }

  # triggeringStabilityCriteria must be a non-empty list of non-empty strings,
  # each naming the MVP contract that must hold (an Epic / Story anchor) —
  # coverage derived, not counted.
  $criteria = @($plan.triggeringStabilityCriteria | Where-Object { $null -ne $_ })
  if ($criteria.Count -lt 1) {
    Add-Issue $issues "$subject triggeringStabilityCriteria must list at least one non-empty stability criterion."
  }
  foreach ($criterion in $criteria) {
    if ([string]::IsNullOrWhiteSpace([string]$criterion)) {
      Add-Issue $issues "$subject triggeringStabilityCriteria entry must be a non-empty string."
    }
    elseif ([string]$criterion -notmatch "(?i)(epic|story)\s*\d") {
      Add-Issue $issues "$subject triggeringStabilityCriteria entry must name the MVP contract that must hold (an 'Epic <n>' / 'Story <n>' anchor), found: $criterion."
    }
  }

  $surface = [string]$plan.targetSurface
  if (-not [string]::IsNullOrWhiteSpace($surface)) {
    $surfacesSeen[$surface] = $true
  }

  Test-NoAuthorityFields -Issues $issues -Record $plan -Subject $subject

  # 4-5 cross-reference: each plan must reference semantic-contract-projection-slice.json
  # and its referencedProjectionIds must resolve in that slice when present.
  if ([string]$plan.referencedSemanticContractProjectionSlice -ne "semantic-contract-projection-slice.json") {
    Add-Issue $issues "$subject referencedSemanticContractProjectionSlice must be 'semantic-contract-projection-slice.json' (referenced, not duplicated)."
  }
  $refProjIds = @($plan.referencedProjectionIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($refProjIds.Count -lt 1) {
    Add-Issue $issues "$subject referencedProjectionIds must list at least one projection id from the 4-5 slice."
  }
  if ($semanticSlicePresent) {
    foreach ($refId in $refProjIds) {
      $refIdStr = [string]$refId
      if (-not $semanticProjectionIds.ContainsKey($refIdStr)) {
        Add-Issue $issues "$subject referencedProjectionId must resolve in the 4-5 semantic-contract-projection-slice projectionManifest: $refIdStr."
      }
    }
  }
}

foreach ($expected in $expectedSurfaces) {
  if (-not $surfacesSeen.ContainsKey($expected)) {
    Add-Issue $issues "Phase 2 projection run must catalog a plan for surface '$expected' (Fabric knowledge, Copilot Studio, or analytics)."
  }
}

# ---------------------------------------------------------------------------
# Premature activation attempts — the denial scenario
# ---------------------------------------------------------------------------

$attempts = @($run.prematureActivationAttempts | Where-Object { $null -ne $_ })
if ($attempts.Count -lt 1) {
  Add-Issue $issues "Phase 2 projection run must include at least one prematureActivationAttempt proving the denial guard."
}

$seenAttemptIds = @{}
foreach ($attempt in $attempts) {
  $attemptId = [string]$attempt.attemptId
  $subject = "Premature activation attempt $attemptId"
  if ([string]::IsNullOrWhiteSpace($attemptId)) {
    Add-Issue $issues "Premature activation attempt must carry a non-empty attemptId."
    $subject = "Premature activation attempt (unnamed)"
  }
  else {
    if ($seenAttemptIds.ContainsKey($attemptId)) {
      Add-Issue $issues "Duplicate attemptId in this slice: $attemptId."
    }
    else {
      $seenAttemptIds[$attemptId] = $true
    }
    # MINTED attempt ids must be unique across all slices.
    if ($allSliceWorkItemIds.ContainsKey($attemptId) -or $allSliceReceiptIds.ContainsKey($attemptId) -or $allSliceSourceIds.ContainsKey($attemptId) -or $allSliceRunIds.ContainsKey($attemptId) -or $allSliceProjectionIds.ContainsKey($attemptId)) {
      Add-Issue $issues "$subject attemptId collides with an id harvested from a sibling slice: $attemptId."
    }
  }

  foreach ($field in @("targetPlanId", "attemptedSurface", "attemptedAction", "deniedByReceipt", "denialRationale", "attemptedAt")) {
    if (-not (Test-HasNonEmptyField -Record $attempt -Field $field)) {
      Add-Issue $issues "$subject missing required field: $field."
    }
  }

  # targetPlanId must resolve to a plan minted in THIS slice (REFERENCED id must resolve).
  $targetPlanId = [string]$attempt.targetPlanId
  if (-not [string]::IsNullOrWhiteSpace($targetPlanId) -and -not $slicePlanIds.ContainsKey($targetPlanId)) {
    Add-Issue $issues "$subject targetPlanId must resolve to a projection plan declared in this slice, found: $targetPlanId."
  }
  # attemptedSurface must match the targeted plan's targetSurface (the denial must
  # be for the same surface the plan projects), not just be a free string.
  if (-not [string]::IsNullOrWhiteSpace($targetPlanId) -and $slicePlanIds.ContainsKey($targetPlanId)) {
    $linkedPlan = $slicePlanIds[$targetPlanId]
    if ([string]$attempt.attemptedSurface -ne [string]$linkedPlan.targetSurface) {
      Add-Issue $issues "$subject attemptedSurface must match the targeted plan's targetSurface ($($linkedPlan.targetSurface)), found: $($attempt.attemptedSurface)."
    }
  }

  # projectionRemainsDeferred must be strict boolean true (the denial actually holds).
  if ($attempt.PSObject.Properties.Name -notcontains "projectionRemainsDeferred" -or $attempt.projectionRemainsDeferred -isnot [bool] -or -not $attempt.projectionRemainsDeferred) {
    Add-Issue $issues "$subject projectionRemainsDeferred must be strict boolean true; the denied projection must remain deferred."
  }

  $null = Test-IsoTimestamp -Issues $issues -Record $attempt -Field "attemptedAt" -Subject $subject
  Test-NoAuthorityFields -Issues $issues -Record $attempt -Subject $subject
}

# ---------------------------------------------------------------------------
# Receipts — required manifest fields + cross-slice uniqueness (MINTED ids)
# ---------------------------------------------------------------------------

$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique

$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 2) {
  Add-Issue $issues "Phase 2 projection run must include at least two receipts (deferred-plan catalog + premature-activation denial)."
}

$sliceReceiptIdMap = @{}
$seenReceiptIds = @{}
$seenIdempotencyKeys = @{}
foreach ($receipt in $receipts) {
  $receiptId = [string]$receipt.com_receipt_id
  $subject = "Receipt $receiptId"
  if ([string]::IsNullOrWhiteSpace($receiptId)) {
    Add-Issue $issues "Receipt must carry a non-empty com_receipt_id."
    continue
  }
  if ($receiptId -notmatch "^CR-LOCAL-") {
    Add-Issue $issues "$subject must use a story-local CR-LOCAL-* identity, found: $receiptId."
  }
  if ($seenReceiptIds.ContainsKey($receiptId)) {
    Add-Issue $issues "Duplicate receipt id in this slice: $receiptId."
  }
  else {
    $seenReceiptIds[$receiptId] = $true
    $sliceReceiptIdMap[$receiptId] = $receipt
  }
  # MINTED receipt ids must be unique across ALL slices.
  if ($allSliceReceiptIds.ContainsKey($receiptId)) {
    Add-Issue $issues "$subject collides with a receipt id harvested from a sibling slice (unique across ALL slices required): $receiptId."
  }
  if ($demoReceiptIds = @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
    if ($demoReceiptIds -contains $receiptId) {
      Add-Issue $issues "$subject collides with a reserved state-transition-demo receipt ID."
    }
  }

  foreach ($field in $receiptRequiredFields) {
    if ($field -eq "com_append_only_locked") {
      if ($receipt.PSObject.Properties.Name -notcontains $field) {
        Add-Issue $issues "$subject missing required field: $field."
      }
      continue
    }
    if (-not (Test-HasNonEmptyField -Record $receipt -Field $field)) {
      Add-Issue $issues "$subject missing required manifest receipt field: $field."
    }
  }

  if ($receiptVerbs -notcontains [string]$receipt.com_verb) {
    Add-Issue $issues "$subject com_verb is not in manifest com_receiptverb vocabulary: $($receipt.com_verb)."
  }
  if ($actorTypes -notcontains [string]$receipt.com_actor_type) {
    Add-Issue $issues "$subject com_actor_type is not in manifest com_actortype vocabulary: $($receipt.com_actor_type)."
  }
  if ($receiptResults -notcontains [string]$receipt.com_result) {
    Add-Issue $issues "$subject com_result is not in manifest com_receiptresult vocabulary: $($receipt.com_result)."
  }
  if ($receipt.com_append_only_locked -isnot [bool] -or -not $receipt.com_append_only_locked) {
    Add-Issue $issues "$subject com_append_only_locked must be strict boolean true (receipts are append-only)."
  }

  $null = Test-IsoTimestamp -Issues $issues -Record $receipt -Field "com_occurred_at" -Subject $subject
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject

  $idempotencyKey = [string]$receipt.com_idempotency_key
  if (-not [string]::IsNullOrWhiteSpace($idempotencyKey)) {
    if ($seenIdempotencyKeys.ContainsKey($idempotencyKey)) {
      Add-Issue $issues "$subject duplicates an idempotency key already used in this slice: $idempotencyKey."
    }
    else {
      $seenIdempotencyKeys[$idempotencyKey] = $true
    }
    if ($allSliceIdempotencyKeys.ContainsKey($idempotencyKey)) {
      Add-Issue $issues "$subject idempotency key collides with one harvested from a sibling slice: $idempotencyKey."
    }
  }

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Phase 2 receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Phase 2 receipts are local contract evidence only."
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Role-based receipt requirements (semantic role over collections — never
# bind to fixture ids). General rules, not hardcoded-id binding.
# ---------------------------------------------------------------------------

$deferRoleReceipts = @($receipts | Where-Object {
  [string]$_.com_verb -eq "reviewed" -and [string]$_.com_policy_flags -match "phase2_plans_deferred_until_mvp_contracts_stable"
})
if ($deferRoleReceipts.Count -lt 1) {
  Add-Issue $issues "Phase 2 projection run must include >=1 deferred-plan catalog receipt (com_verb=reviewed AND com_policy_flags contains phase2_plans_deferred_until_mvp_contracts_stable)."
}
else {
  foreach ($deferReceipt in $deferRoleReceipts) {
    $roleSubject = "Deferred-plan catalog receipt $([string]$deferReceipt.com_receipt_id)"
    if ([string]$deferReceipt.com_policy_flags -notmatch "projections_never_own_workflow_state") {
      Add-Issue $issues "$roleSubject com_policy_flags must include projections_never_own_workflow_state."
    }
    if ([string]$deferReceipt.com_policy_flags -notmatch "planes_are_projections_only") {
      Add-Issue $issues "$roleSubject com_policy_flags must include planes_are_projections_only."
    }
  }
}

$denialRoleReceipts = @($receipts | Where-Object {
  [string]$_.com_verb -eq "policy_denied" -and [string]$_.com_policy_flags -match "premature_activation_policy_denied"
})
if ($denialRoleReceipts.Count -lt 1) {
  Add-Issue $issues "Phase 2 projection run must include >=1 premature-activation denial receipt (com_verb=policy_denied AND com_policy_flags contains premature_activation_policy_denied)."
}
else {
  foreach ($denialReceipt in $denialRoleReceipts) {
    $roleSubject = "Denial receipt $([string]$denialReceipt.com_receipt_id)"
    if ([string]$denialReceipt.com_result -ne "rejected") {
      Add-Issue $issues "$roleSubject com_result must be 'rejected' for a policy_denied receipt, found: $($denialReceipt.com_result)."
    }
    if ([string]$denialReceipt.com_policy_flags -notmatch "projections_never_own_workflow_state") {
      Add-Issue $issues "$roleSubject com_policy_flags must include projections_never_own_workflow_state."
    }
    if ([string]$denialReceipt.com_policy_flags -notmatch "phase2_plans_deferred_until_mvp_contracts_stable") {
      Add-Issue $issues "$roleSubject com_policy_flags must include phase2_plans_deferred_until_mvp_contracts_stable."
    }
  }
}

# Every premature activation attempt must bind to a denial-role receipt that
# is actually declared in this slice (REFERENCED id must resolve). General rule
# over the attempts collection — no hardcoded id binding.
foreach ($attempt in $attempts) {
  $deniedById = [string]$attempt.deniedByReceipt
  $attemptTargetPlanId = [string]$attempt.targetPlanId
  if (-not [string]::IsNullOrWhiteSpace($deniedById)) {
    if (-not $sliceReceiptIdMap.ContainsKey($deniedById)) {
      Add-Issue $issues "Premature activation attempt $([string]$attempt.attemptId) deniedByReceipt must resolve to a receipt declared in this slice, found: $deniedById."
    }
    elseif (-not ($denialRoleReceipts | Where-Object { [string]$_.com_receipt_id -eq $deniedById })) {
      Add-Issue $issues "Premature activation attempt $([string]$attempt.attemptId) deniedByReceipt must bind to a policy_denied role receipt, found: $deniedById."
    }
    elseif (-not [string]::IsNullOrWhiteSpace($attemptTargetPlanId) -and ([string]$sliceReceiptIdMap[$deniedById].com_evidence_refs -notmatch [regex]::Escape($attemptTargetPlanId))) {
      Add-Issue $issues "Premature activation attempt $([string]$attempt.attemptId) denial receipt $deniedById must name the targeted plan $attemptTargetPlanId in its com_evidence_refs (direct receipt->plan binding, not merely transitive via the attempt)."
    }
  }
}

# Every denial-role receipt must be bound to a plan via some attempt
# (the denial receipt must not float free). General rule over collections.
foreach ($denialReceipt in $denialRoleReceipts) {
  $denialId = [string]$denialReceipt.com_receipt_id
  $bound = @($attempts | Where-Object { [string]$_.deniedByReceipt -eq $denialId })
  if ($bound.Count -lt 1) {
    Add-Issue $issues "Denial receipt $denialId must be bound to a prematureActivationAttempt (deniedByReceipt), not float free."
  }
}

# ---------------------------------------------------------------------------
# Receipt source links
# ---------------------------------------------------------------------------

$links = @($run.receiptSourceLinks | Where-Object { $null -ne $_ })
if ($links.Count -lt 1) {
  Add-Issue $issues "Phase 2 projection run must include at least one receiptSourceLinks entry."
}
foreach ($link in $links) {
  $linkSubject = "Receipt source link $($link.com_name)"
  foreach ($field in @("com_name", "com_receipt", "com_source_record", "com_evidence_role")) {
    if (-not (Test-HasNonEmptyField -Record $link -Field $field)) {
      Add-Issue $issues "$linkSubject missing required field: $field."
    }
  }
  $linkReceiptId = [string]$link.com_receipt
  if (-not [string]::IsNullOrWhiteSpace($linkReceiptId) -and -not $sliceReceiptIdMap.ContainsKey($linkReceiptId)) {
    Add-Issue $issues "$linkSubject must bind a receipt from this slice, found: $linkReceiptId."
  }
  $linkSourceId = [string]$link.com_source_record
  if (-not [string]::IsNullOrWhiteSpace($linkSourceId)) {
    if ($knownSourceIds -notcontains $linkSourceId -and -not $allSliceSourceIds.ContainsKey($linkSourceId)) {
      Add-Issue $issues "$linkSubject must bind a source record that resolves in sibling slices, found: $linkSourceId."
    }
  }
  if ((Test-HasNonEmptyField -Record $link -Field "com_evidence_role") -and $evidenceRoles -notcontains [string]$link.com_evidence_role) {
    Add-Issue $issues "$linkSubject evidence role is not in manifest vocabulary: $($link.com_evidence_role)."
  }
}
foreach ($receiptId in @($sliceReceiptIdMap.Keys)) {
  if (@($links | Where-Object { $_.com_receipt -eq $receiptId }).Count -lt 1) {
    Add-Issue $issues "Receipt $receiptId must be bound to its source evidence by at least one receipt source link."
  }
}

# ---------------------------------------------------------------------------
# Deferred live Phase-2 plane writes — every plan must have a deferred entry,
# and every deferred entry must name a real plan + a receipt gate.
# ---------------------------------------------------------------------------

$deferredPlaneWrites = @($run.livePhase2PlaneWritesDeferred | Where-Object { $null -ne $_ })
if ($deferredPlaneWrites.Count -lt $plans.Count) {
  Add-Issue $issues "Phase 2 projection run must include a deferred live-write entry for every projection plan, found $($deferredPlaneWrites.Count) for $($plans.Count) plans."
}
$deferredPlanIdsSeen = @{}
foreach ($deferred in $deferredPlaneWrites) {
  $plane = [string]$deferred.targetSurface
  $deferredPlanId = [string]$deferred.planId
  $subject = "Deferred Phase-2 plane write for $plane"
  if ([string]::IsNullOrWhiteSpace($plane)) {
    Add-Issue $issues "Deferred Phase-2 plane write must name targetSurface."
  }
  if ([string]::IsNullOrWhiteSpace($deferredPlanId) -or -not $slicePlanIds.ContainsKey($deferredPlanId)) {
    Add-Issue $issues "Deferred Phase-2 plane write must name a planId declared in this slice, found: $deferredPlanId."
  }
  else {
    $deferredPlanIdsSeen[$deferredPlanId] = $true
    $linkedPlan = $slicePlanIds[$deferredPlanId]
    if ([string]$linkedPlan.targetSurface -ne $plane) {
      Add-Issue $issues "$subject targetSurface must match its plan's targetSurface ($($linkedPlan.targetSurface)), found: $plane."
    }
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "$subject must carry a non-empty deferredUpdate."
  }
  elseif (($deferred.deferredUpdate -notmatch "receipt-gat") -and ($deferred.deferredUpdate -notmatch "receipt gate") -and ($deferred.deferredUpdate -notmatch "CR-LOCAL-[A-Z0-9-]+")) {
    Add-Issue $issues "$subject deferredUpdate must name its receipt gate (e.g. 'receipt-gated' or a CR-LOCAL-* receipt id); the bare word 'receipt' does not name a gate, found: $($deferred.deferredUpdate)."
  }
}
foreach ($planId in @($slicePlanIds.Keys)) {
  if (-not $deferredPlanIdsSeen.ContainsKey($planId)) {
    Add-Issue $issues "Missing deferred live Phase-2 plane write entry for plan: $planId."
  }
}

# ---------------------------------------------------------------------------
# Acceptance mapping (three ACs derived from the story's Slice must prove list)
# ---------------------------------------------------------------------------

# Resolvable evidence-id registry: every id cited in an acceptance mapping's
# localEvidence must resolve either to an id MINTED in this slice (plan,
# attempt, receipt, run ids) or to a REFERENCED id harvested from a sibling
# slice (projection / source-record / work-item / run ids). General rule over
# the union of minted + referenced ids — no hardcoded-id binding.
$resolvableEvidenceIds = @{}
foreach ($id in @($slicePlanIds.Keys + $seenAttemptIds.Keys + $sliceReceiptIdMap.Keys + $allSliceProjectionIds.Keys + $allSliceWorkItemIds.Keys + $allSliceSourceIds.Keys + $allSliceRunIds.Keys + $allSliceReceiptIds.Keys)) {
  $idStr = [string]$id
  if (-not [string]::IsNullOrWhiteSpace($idStr)) { $resolvableEvidenceIds[$idStr] = $true }
}
if (-not [string]::IsNullOrWhiteSpace([string]$run.runId)) {
  $resolvableEvidenceIds[[string]$run.runId] = $true
}

$acceptanceMappings = @($slice.acceptanceMapping | Where-Object { $null -ne $_ })
$seenAcceptanceCriteria = @{}
foreach ($mapping in $acceptanceMappings) {
  $acKey = [string]$mapping.acceptanceCriterion
  if ([string]::IsNullOrWhiteSpace($acKey)) {
    Add-Issue $issues "Acceptance mapping entry must carry a non-empty acceptanceCriterion."
  }
  elseif ($acKey -notin @("1", "2", "3")) {
    Add-Issue $issues "Acceptance mapping entry references an unknown acceptanceCriterion (only 1, 2, 3 exist for this story), found: $acKey."
  }
  elseif ($seenAcceptanceCriteria.ContainsKey($acKey)) {
    Add-Issue $issues "Acceptance mapping entry for acceptanceCriterion $acKey is duplicated."
  }
  else {
    $seenAcceptanceCriteria[$acKey] = $true
  }

  if (@($mapping.localEvidence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -lt 1) {
    Add-Issue $issues "Acceptance mapping for AC $acKey must list non-empty localEvidence."
  }
  if (-not (Test-HasNonEmptyField -Record $mapping -Field "tenantEvidenceRequired")) {
    Add-Issue $issues "Acceptance mapping for AC $acKey must state tenantEvidenceRequired."
  }

  # Derive, don't count: every evidence id cited in localEvidence must resolve to
  # a real id in this slice or a sibling-harvested id. Free-text citations of
  # nonexistent evidence must FAIL. (Handles range/shorthand like 001..006 by
  # resolving each captured id token independently.)
  foreach ($evidenceLine in @($mapping.localEvidence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
    $idMatches = [regex]::Matches([string]$evidenceLine, "[A-Z][A-Z0-9]+(?:-[A-Z0-9]+)*-LOCAL(?:-[A-Z0-9]+)+")
    foreach ($idMatch in $idMatches) {
      $citedId = $idMatch.Value
      if (-not $resolvableEvidenceIds.ContainsKey($citedId)) {
        Add-Issue $issues "Acceptance mapping for AC $acKey cites an evidence id that does not resolve in this slice or any sibling slice: $citedId."
      }
    }
  }
}
foreach ($criterion in @(1, 2, 3)) {
  if (-not $seenAcceptanceCriteria.ContainsKey([string]$criterion)) {
    Add-Issue $issues "Missing acceptance mapping for AC $criterion."
  }
}

# ---------------------------------------------------------------------------
# Final
# ---------------------------------------------------------------------------

if ($issues.Count -gt 0) {
  Write-Host "Phase 2 projections slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Phase 2 projections slice validation succeeded."
Write-Host "Projection plans: $($plans.Count)"
Write-Host "Surfaces: $($surfacesSeen.Keys -join ', ')"
Write-Host "Premature activation attempts: $($attempts.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "Deferred plane writes: $($deferredPlaneWrites.Count)"
Write-Host "PHASE2_PROJECTIONS_SLICE_VALIDATE_OK"
