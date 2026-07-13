param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$ProjectionSlicePath = "$PSScriptRoot\semantic-contract-projection-slice.json",
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
    Write-Host "Semantic contract projection slice validation failed:"
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
      Add-Issue $Issues "$Subject must not claim workflow/approval authority via field '$field'; planes are projections only."
    }
  }
}

foreach ($path in @($ManifestPath, $ProjectionSlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $Story15DriftPath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required semantic contract projection validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$slice = Read-JsonInput -Path $ProjectionSlicePath
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
$graphEdgeTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_graphedgetype"
$graphEntityTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_graphentitytype"
$workItemTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemtype"
$evidenceRoles = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilreceiptsource" -ColumnName "com_evidence_role"

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_graphedgetype"; Values = $graphEdgeTypes },
    @{ Name = "com_graphentitytype"; Values = $graphEntityTypes },
    @{ Name = "com_workitemtype"; Values = $workItemTypes },
    @{ Name = "com_councilreceiptsource.com_evidence_role"; Values = $evidenceRoles }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

# Derive allowed projection vocabularies from the full manifest choice surface
# (not a hardcoded three-name subset the fixture happens to use).
$vocabularyByName = @{}
foreach ($choice in @($manifest.choices | Where-Object { $null -ne $_ })) {
  $choiceName = [string]$choice.name
  if ([string]::IsNullOrWhiteSpace($choiceName)) { continue }
  $vocabularyByName[$choiceName] = @($choice.values | Where-Object { $null -ne $_ })
}
if ($vocabularyByName.Count -eq 0) {
  Add-Issue $issues "Manifest choices yielded no projection vocabularies; term-resolution checks would silently no-op."
}

# ---------------------------------------------------------------------------
# Slice identity and guards
# ---------------------------------------------------------------------------

if ($slice.storyKey -ne "4-5-project-the-semantic-contract-without-dual-authoring") {
  Add-Issue $issues "Projection slice storyKey must be 4-5-project-the-semantic-contract-without-dual-authoring."
}
if ([string]$slice.status -notmatch "^local-contract") {
  Add-Issue $issues "Projection slice status must declare local contract evidence, found: $($slice.status)."
}

$requiredGuards = @(
  "noTenantWrites",
  "noOutboundAction",
  "noApprovalExecution",
  "requiresExplicitHumanApprovalForExecution",
  "receiptsAreLocalContractEvidenceOnly",
  "planesAreProjectionsOnly",
  "noCanonicalAuthoringInPlanes",
  "platformInferredTermsProposeContractUpdatesOnly",
  "driftNeverEditsPlaneInPlace",
  "reconciliationIsReceiptBacked",
  "projectionClaimsNoWorkflowAuthority"
)
foreach ($guard in $requiredGuards) {
  if (-not ($slice.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Projection slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($slice.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Projection guard must be boolean true: $($guardProperty.Name)."
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
# All-slice id harvest (live collision surface)
# ---------------------------------------------------------------------------

$allSliceWorkItemIds = @{}
$allSliceReceiptIds = @{}
$allSliceIdempotencyKeys = @{}
$allSliceSourceIds = @{}
$allSliceRunIds = @{}
$allSliceProjectionIds = @{}
$selfSliceBasename = (Split-Path -Leaf $ProjectionSlicePath)
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

# ---------------------------------------------------------------------------
# Projection run header
# ---------------------------------------------------------------------------

$run = $slice.projectionRun
if ($null -eq $run) {
  Add-Issue $issues "Projection slice must carry a projectionRun block."
  $run = [pscustomobject]@{}
}

if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Projection run must carry a non-empty runId."
}
elseif ($allSliceRunIds.ContainsKey([string]$run.runId)) {
  Add-Issue $issues "Projection run runId collides with a runId harvested from a sibling slice: $($run.runId)."
}

if ($actorTypes -notcontains [string]$run.actorType) {
  Add-Issue $issues "Projection run actorType is not in manifest com_actortype vocabulary: $($run.actorType)."
}
if (-not (Test-HasNonEmptyField -Record $run -Field "actorId")) {
  Add-Issue $issues "Projection run must carry a non-empty actorId."
}
if (-not (Test-HasNonEmptyField -Record $run -Field "authorityBasis")) {
  Add-Issue $issues "Projection run must carry a non-empty authorityBasis."
}
if (-not (Test-HasNonEmptyField -Record $run -Field "semanticContractVersion")) {
  Add-Issue $issues "Projection run must carry a non-empty semanticContractVersion."
}

if ([string]$run.canonicalSource -ne "council-semantic-contract") {
  Add-Issue $issues "Projection run canonicalSource must be 'council-semantic-contract', found: $($run.canonicalSource)."
}

$targetPlanes = @($run.targetPlanes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($targetPlanes.Count -lt 2) {
  Add-Issue $issues "Projection run targetPlanes must name at least two planes."
}
$targetPlaneSet = @{}
foreach ($p in $targetPlanes) { $targetPlaneSet[[string]$p] = $true }

$policy = $run.decisionPolicy
if ($null -eq $policy) {
  Add-Issue $issues "Projection run must carry decisionPolicy."
}
else {
  foreach ($flag in @("planesAreProjectionsOnly", "canonicalSourceIsCouncilSemanticContract", "platformInferredTermsProposeOnly", "driftNeverEditsPlaneInPlace", "reconciliationIsReceiptBacked", "projectionEntriesCarryNoStateOrApprovalAuthority", "livePlaneWritesReceiptGated")) {
    if (-not ($policy.PSObject.Properties.Name -contains $flag) -or $policy.$flag -isnot [bool] -or -not $policy.$flag) {
      Add-Issue $issues "decisionPolicy.$flag must be strict boolean true."
    }
  }
}

# ---------------------------------------------------------------------------
# Projection manifest
# ---------------------------------------------------------------------------

$projections = @($run.projectionManifest | Where-Object { $null -ne $_ })
if ($projections.Count -lt 4) {
  Add-Issue $issues "projectionManifest must include at least four projection entries, found $($projections.Count)."
}

$requiredProjectionFields = @(
  "projectionId",
  "canonicalTermId",
  "canonicalVocabulary",
  "canonicalValue",
  "targetPlane",
  "projectedRepresentation",
  "projectionDate",
  "canonicalSource"
)

$sliceProjectionIds = @{}
$seenProjectionIds = @{}
$planesTouched = @{}
$canonicalValuesSeen = @{}
foreach ($proj in $projections) {
  $projId = [string]$proj.projectionId
  $subject = "Projection entry $projId"
  if ([string]::IsNullOrWhiteSpace($projId)) {
    Add-Issue $issues "Projection entry must carry a non-empty projectionId."
    $subject = "Projection entry (unnamed)"
  }
  else {
    if ($seenProjectionIds.ContainsKey($projId)) {
      Add-Issue $issues "Duplicate projectionId in this slice: $projId."
    }
    else {
      $seenProjectionIds[$projId] = $true
      $sliceProjectionIds[$projId] = $proj
    }
    if ($allSliceProjectionIds.ContainsKey($projId) -or $allSliceReceiptIds.ContainsKey($projId) -or $allSliceWorkItemIds.ContainsKey($projId) -or $allSliceSourceIds.ContainsKey($projId)) {
      Add-Issue $issues "$subject projectionId collides with an id harvested from a sibling slice: $projId."
    }
  }

  foreach ($field in $requiredProjectionFields) {
    if (-not (Test-HasNonEmptyField -Record $proj -Field $field)) {
      Add-Issue $issues "$subject missing required field: $field."
    }
  }

  if ([string]$proj.canonicalSource -ne "council-semantic-contract") {
    Add-Issue $issues "$subject canonicalSource must be 'council-semantic-contract', found: $($proj.canonicalSource)."
  }

  $plane = [string]$proj.targetPlane
  if (-not [string]::IsNullOrWhiteSpace($plane)) {
    if (-not $targetPlaneSet.ContainsKey($plane)) {
      Add-Issue $issues "$subject targetPlane must be one of projectionRun.targetPlanes, found: $plane."
    }
    $planesTouched[$plane] = $true
  }

  $vocabName = [string]$proj.canonicalVocabulary
  $canonValue = [string]$proj.canonicalValue
  if ([string]::IsNullOrWhiteSpace($vocabName) -or -not $vocabularyByName.ContainsKey($vocabName)) {
    Add-Issue $issues "$subject canonicalVocabulary must name a manifest choices[] entry, found: $vocabName (known: $((@($vocabularyByName.Keys) | Sort-Object) -join ', '))."
  }
  else {
    $allowed = @($vocabularyByName[$vocabName])
    if ($allowed -notcontains $canonValue) {
      Add-Issue $issues "$subject canonicalValue '$canonValue' does not resolve in manifest vocabulary $vocabName."
    }
    else {
      $canonicalValuesSeen[$canonValue] = $true
    }
  }

  # canonicalTermId must be structurally consistent with vocabulary + value (not freeform)
  if ((Test-HasNonEmptyField -Record $proj -Field "canonicalTermId") -and -not [string]::IsNullOrWhiteSpace($canonValue)) {
    $termId = [string]$proj.canonicalTermId
    if ($termId -notmatch [regex]::Escape($canonValue)) {
      Add-Issue $issues "$subject canonicalTermId '$termId' must contain its canonicalValue '$canonValue'."
    }
  }

  $null = Test-IsoTimestamp -Issues $issues -Record $proj -Field "projectionDate" -Subject $subject
  Test-NoAuthorityFields -Issues $issues -Record $proj -Subject $subject
}

if ($planesTouched.Count -lt 2) {
  Add-Issue $issues "projectionManifest must touch at least two distinct target planes, found: $($planesTouched.Keys -join ', ')."
}
if ($canonicalValuesSeen.Count -lt 4) {
  Add-Issue $issues "projectionManifest must project at least four distinct canonical vocabulary values, found: $($canonicalValuesSeen.Count) ($($canonicalValuesSeen.Keys -join ', '))."
}

# ---------------------------------------------------------------------------
# Drift detection (content-delta proven, not self-asserted)
# ---------------------------------------------------------------------------

$drift = $run.driftDetection
if ($null -eq $drift) {
  Add-Issue $issues "Projection slice must carry a driftDetection block."
}
else {
  $driftSubject = "driftDetection"
  foreach ($field in @("detectionId", "projectedTermProjectionId", "canonicalTermId", "canonicalVocabulary", "canonicalValue", "targetPlane", "canonicalProjectedRepresentation", "observedPlaneRepresentation", "detectionRationale", "reconciliationAction", "detectedAt", "flaggedByReceipt")) {
    if (-not (Test-HasNonEmptyField -Record $drift -Field $field)) {
      Add-Issue $issues "$driftSubject must carry non-empty field: $field."
    }
  }

  if ($drift.planeEditedInPlace -isnot [bool] -or $drift.planeEditedInPlace) {
    Add-Issue $issues "$driftSubject.planeEditedInPlace must be strict boolean false (never edit plane in place)."
  }
  if ($drift.claimsPlaneAuthority -isnot [bool] -or $drift.claimsPlaneAuthority) {
    Add-Issue $issues "$driftSubject.claimsPlaneAuthority must be strict boolean false."
  }
  if ([string]$drift.reconciliationAction -notmatch "flag_for_reconciliation_never_edit_in_place") {
    Add-Issue $issues "$driftSubject.reconciliationAction must mandate flag-for-reconciliation without in-place plane edit, found: $($drift.reconciliationAction)."
  }

  $null = Test-IsoTimestamp -Issues $issues -Record $drift -Field "detectedAt" -Subject $driftSubject
  Test-NoAuthorityFields -Issues $issues -Record $drift -Subject $driftSubject

  $linkedProjId = [string]$drift.projectedTermProjectionId
  if (-not $sliceProjectionIds.ContainsKey($linkedProjId)) {
    Add-Issue $issues "$driftSubject.projectedTermProjectionId must reference a real projection entry in this slice, found: $linkedProjId."
  }
  else {
    $linked = $sliceProjectionIds[$linkedProjId]
    if ([string]$linked.canonicalValue -ne [string]$drift.canonicalValue) {
      Add-Issue $issues "$driftSubject.canonicalValue must match linked projection's canonicalValue ($($linked.canonicalValue)), found: $($drift.canonicalValue)."
    }
    if ([string]$linked.targetPlane -ne [string]$drift.targetPlane) {
      Add-Issue $issues "$driftSubject.targetPlane must match linked projection's targetPlane ($($linked.targetPlane)), found: $($drift.targetPlane)."
    }
    if ([string]$linked.canonicalVocabulary -ne [string]$drift.canonicalVocabulary) {
      Add-Issue $issues "$driftSubject.canonicalVocabulary must match linked projection's canonicalVocabulary ($($linked.canonicalVocabulary)), found: $($drift.canonicalVocabulary)."
    }
    # Content delta: observed plane representation must truly differ from projected representation
    $canonicalRep = [string]$linked.projectedRepresentation
    $observedRep = [string]$drift.observedPlaneRepresentation
    if ([string]::IsNullOrWhiteSpace($observedRep) -or $observedRep -eq $canonicalRep) {
      Add-Issue $issues "$driftSubject.observedPlaneRepresentation must content-differ from the linked projection's projectedRepresentation; identical content is not drift."
    }
    if ((Test-HasNonEmptyField -Record $drift -Field "canonicalProjectedRepresentation") -and [string]$drift.canonicalProjectedRepresentation -ne $canonicalRep) {
      Add-Issue $issues "$driftSubject.canonicalProjectedRepresentation must equal the linked projection's projectedRepresentation (echo check), else the drift claim is unanchored."
    }
  }

  $driftVocab = [string]$drift.canonicalVocabulary
  $driftValue = [string]$drift.canonicalValue
  if ($vocabularyByName.ContainsKey($driftVocab)) {
    if (@($vocabularyByName[$driftVocab]) -notcontains $driftValue) {
      Add-Issue $issues "$driftSubject.canonicalValue '$driftValue' does not resolve in manifest vocabulary $driftVocab."
    }
  }
  elseif (-not [string]::IsNullOrWhiteSpace($driftVocab)) {
    Add-Issue $issues "$driftSubject.canonicalVocabulary must name a manifest choices[] entry, found: $driftVocab."
  }
}

# ---------------------------------------------------------------------------
# Receipts
# ---------------------------------------------------------------------------

$requiredReceiptFields = @(
  "com_receipt_id",
  "com_verb",
  "com_actor_type",
  "com_actor_id",
  "com_authority_basis",
  "com_occurred_at",
  "com_idempotency_key",
  "com_before_state",
  "com_after_state",
  "com_evidence_refs",
  "com_decision_rationale",
  "com_confidence",
  "com_result",
  "com_policy_flags",
  "com_append_only_locked"
)

$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 2) {
  Add-Issue $issues "Projection slice must include at least two receipts (projection + drift/reconciliation)."
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
  if ($allSliceReceiptIds.ContainsKey($receiptId)) {
    Add-Issue $issues "$subject collides with a receipt id harvested from a sibling slice (unique across ALL slices required): $receiptId."
  }

  foreach ($field in $requiredReceiptFields) {
    if ($field -eq "com_append_only_locked") {
      if ($receipt.PSObject.Properties.Name -notcontains $field) {
        Add-Issue $issues "$subject missing required field: $field."
      }
      continue
    }
    if (-not (Test-HasNonEmptyField -Record $receipt -Field $field)) {
      Add-Issue $issues "$subject missing required field: $field."
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
}

# Role-based receipt requirements (semantic role over collections — never bind to fixture ids)
$projectionRoleReceipts = @($receipts | Where-Object {
  [string]$_.com_verb -eq "reviewed" -and [string]$_.com_policy_flags -match "planes_are_projections_only"
})
if ($projectionRoleReceipts.Count -lt 1) {
  Add-Issue $issues "Projection slice must include ≥1 projection-role receipt (com_verb=reviewed AND com_policy_flags contains planes_are_projections_only)."
}
else {
  foreach ($projReceipt in $projectionRoleReceipts) {
    $roleSubject = "Projection-role receipt $([string]$projReceipt.com_receipt_id)"
    if ([string]$projReceipt.com_policy_flags -notmatch "local_contract_evidence_only") {
      Add-Issue $issues "$roleSubject com_policy_flags must include local_contract_evidence_only."
    }
    if ([string]$projReceipt.com_policy_flags -notmatch "no_tenant_write") {
      Add-Issue $issues "$roleSubject com_policy_flags must include no_tenant_write."
    }
  }
}

$driftRoleReceipts = @($receipts | Where-Object {
  [string]$_.com_verb -eq "source_drifted" -and [string]$_.com_policy_flags -match "drift_never_edits_plane_in_place"
})
if ($driftRoleReceipts.Count -lt 1) {
  Add-Issue $issues "Projection slice must include ≥1 drift-role receipt (com_verb=source_drifted AND com_policy_flags contains drift_never_edits_plane_in_place)."
}
else {
  $driftRoleReceiptIds = @{}
  foreach ($driftReceipt in $driftRoleReceipts) {
    $roleSubject = "Drift-role receipt $([string]$driftReceipt.com_receipt_id)"
    $driftRoleReceiptIds[[string]$driftReceipt.com_receipt_id] = $true
    if ([string]$driftReceipt.com_policy_flags -notmatch "reconciliation_flagged") {
      Add-Issue $issues "$roleSubject com_policy_flags must include reconciliation_flagged."
    }
    if ([string]$driftReceipt.com_policy_flags -notmatch "local_contract_evidence_only") {
      Add-Issue $issues "$roleSubject com_policy_flags must include local_contract_evidence_only."
    }
  }
  if ($null -ne $drift -and (Test-HasNonEmptyField -Record $drift -Field "flaggedByReceipt")) {
    $flaggedId = [string]$drift.flaggedByReceipt
    if (-not $driftRoleReceiptIds.ContainsKey($flaggedId)) {
      Add-Issue $issues "driftDetection.flaggedByReceipt must resolve to a drift-role receipt in this slice (verb=source_drifted + drift_never_edits_plane_in_place), found: $flaggedId."
    }
    if (-not $sliceReceiptIdMap.ContainsKey($flaggedId)) {
      Add-Issue $issues "driftDetection.flaggedByReceipt must be a receipt id declared in this slice, found: $flaggedId."
    }
  }
}

$reconcileRoleReceipts = @($receipts | Where-Object {
  [string]$_.com_verb -eq "proposed" -and [string]$_.com_policy_flags -match "reconciliation_is_receipt_backed"
})
if ($reconcileRoleReceipts.Count -lt 1) {
  Add-Issue $issues "Projection slice must include ≥1 reconciliation-role receipt (com_verb=proposed AND com_policy_flags contains reconciliation_is_receipt_backed)."
}
else {
  foreach ($recReceipt in $reconcileRoleReceipts) {
    $roleSubject = "Reconciliation-role receipt $([string]$recReceipt.com_receipt_id)"
    if ([string]$recReceipt.com_policy_flags -notmatch "platform_inferred_terms_propose_only") {
      Add-Issue $issues "$roleSubject com_policy_flags must include platform_inferred_terms_propose_only."
    }
  }
}

# ---------------------------------------------------------------------------
# Receipt source links
# ---------------------------------------------------------------------------

$links = @($run.receiptSourceLinks | Where-Object { $null -ne $_ })
if ($links.Count -lt 1) {
  Add-Issue $issues "Projection slice must include at least one receiptSourceLinks entry."
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
# Deferred live plane writes (must name target planes + receipt gate)
# ---------------------------------------------------------------------------

$deferredPlaneWrites = @($run.livePlaneWritesDeferred | Where-Object { $null -ne $_ })
if ($deferredPlaneWrites.Count -lt 2) {
  Add-Issue $issues "Projection slice must include deferred live-write entries for both target planes."
}
$deferredPlanesSeen = @{}
foreach ($deferred in $deferredPlaneWrites) {
  $plane = [string]$deferred.targetPlane
  if ([string]::IsNullOrWhiteSpace($plane)) {
    Add-Issue $issues "Deferred plane write must name targetPlane."
  }
  else {
    if (-not $targetPlaneSet.ContainsKey($plane)) {
      Add-Issue $issues "Deferred plane write names unknown targetPlane: $plane."
    }
    $deferredPlanesSeen[$plane] = $true
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred plane write for $plane must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred plane write for $plane must state that the live mutation is receipt-gated."
  }
}
foreach ($plane in @($targetPlanes)) {
  if (-not $deferredPlanesSeen.ContainsKey([string]$plane)) {
    Add-Issue $issues "Missing deferred live plane write entry for target plane: $plane."
  }
}

$platformCandidates = @($run.platformInferredCandidatesDeferred | Where-Object { $null -ne $_ })
if ($platformCandidates.Count -lt 1) {
  Add-Issue $issues "Projection slice must include platformInferredCandidatesDeferred proving platform-inferred terms do not silently update canonical meaning."
}
foreach ($candidate in $platformCandidates) {
  if (-not (Test-HasNonEmptyField -Record $candidate -Field "observedTerm")) {
    Add-Issue $issues "platformInferredCandidatesDeferred entry must name observedTerm."
  }
  if (-not (Test-HasNonEmptyField -Record $candidate -Field "deferredUpdate")) {
    Add-Issue $issues "platformInferredCandidatesDeferred entry must carry deferredUpdate."
  }
  elseif ([string]$candidate.deferredUpdate -notmatch "silently" -and [string]$candidate.deferredUpdate -notmatch "canonical") {
    Add-Issue $issues "platformInferredCandidatesDeferred deferredUpdate must forbid silent canonical updates."
  }
}

# ---------------------------------------------------------------------------
# Acceptance mapping (epics AC 1 and AC 2)
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Final
# ---------------------------------------------------------------------------

if ($issues.Count -gt 0) {
  Write-Host "Semantic contract projection slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Semantic contract projection slice validation succeeded."
Write-Host "Projection entries: $($projections.Count)"
Write-Host "Planes touched: $($planesTouched.Keys -join ', ')"
Write-Host "Canonical values: $($canonicalValuesSeen.Keys -join ', ')"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "SEMANTIC_CONTRACT_PROJECTION_SLICE_VALIDATE_OK"
