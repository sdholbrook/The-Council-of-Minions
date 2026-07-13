param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$GraphSlicePath = "$PSScriptRoot\meaning-graph-records-slice.json",
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
  if (@($Record.PSObject.Properties.Name) -notcontains $Field) { return $false }
  if ($null -eq $Record.$Field -or [string]::IsNullOrWhiteSpace([string]$Record.$Field)) { return $false }
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

function Test-StrictBooleanTrue {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$Field,
    [Parameter(Mandatory = $true)][string]$Subject
  )
  if (-not (@($Record.PSObject.Properties.Name) -contains $Field)) {
    Add-Issue $Issues "$Subject must declare guard/flag: $Field."
    return
  }
  if ($Record.$Field -isnot [bool] -or -not $Record.$Field) {
    Add-Issue $Issues "$Subject $Field must be strict boolean true."
  }
}

function Read-JsonInput {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label
  )
  try {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  }
  catch {
    Write-Host "Meaning graph records slice validation failed:"
    Write-Host "- $Label is not valid JSON: $Path"
    exit 1
  }
}

function Get-IdsFromSliceText {
  param(
    [Parameter(Mandatory = $true)][string]$RawText,
    [Parameter(Mandatory = $true)][string]$Pattern
  )
  $matches = [regex]::Matches($RawText, $Pattern)
  @($matches | ForEach-Object { $_.Groups[1].Value } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

foreach ($path in @($ManifestPath, $GraphSlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $Story15DriftPath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required meaning graph records validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath -Label "Manifest"
$graph = Read-JsonInput -Path $GraphSlicePath -Label "Meaning graph slice"
$manualSlice = Read-JsonInput -Path $ManualSlicePath -Label "Manual source slice"
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath -Label "Outlook source slice"
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath -Label "Story 1.3 extraction slice"
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath -Label "Story 1.4 extraction slice"
$story15Drift = Read-JsonInput -Path $Story15DriftPath -Label "Story 1.5 drift slice"
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath -Label "State transition demo evidence"
$rawSliceText = Get-Content -LiteralPath $GraphSlicePath -Raw
$issues = [System.Collections.Generic.List[string]]::new()

# --- Manifest vocabulary harvest ---
$graphEntityTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_graphentitytype"
$graphEdgeTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_graphedgetype"
$recordStatuses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_recordstatus"
$workItemStateGroups = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemstategroup"

foreach ($vocabulary in @(
    @{ Name = "com_graphentitytype"; Values = $graphEntityTypes },
    @{ Name = "com_graphedgetype"; Values = $graphEdgeTypes },
    @{ Name = "com_recordstatus"; Values = $recordStatuses },
    @{ Name = "com_workitemstategroup"; Values = $workItemStateGroups }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

# Manifest table/column sanity so entity/edge required-field checks cannot silent-no-op.
$entityTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilgraphentity" } | Select-Object -First 1
$edgeTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilgraphedge" } | Select-Object -First 1
if ($null -eq $entityTable) { Add-Issue $issues "Manifest is missing com_councilgraphentity table." }
if ($null -eq $edgeTable) { Add-Issue $issues "Manifest is missing com_councilgraphedge table." }
$manifestRequiredEntityFields = @(@($entityTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$manifestRequiredEdgeFields = @(@($edgeTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredEntityFields.Count -eq 0) { Add-Issue $issues "No required graph entity columns could be derived from manifest; entity required-field checks would silently no-op." }
if ($manifestRequiredEdgeFields.Count -eq 0) { Add-Issue $issues "No required graph edge columns could be derived from manifest; edge required-field checks would silently no-op." }

# --- Cross-slice ID harvest (siblings 1.1-1.5 + demo) ---
$siblingRaw = @()
foreach ($siblingPath in @($ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $Story15DriftPath, $DemoEvidencePath)) {
  $siblingRaw += Get-Content -LiteralPath $siblingPath -Raw
}
$siblingText = $siblingRaw -join "`n"

$siblingCwiIds = Get-IdsFromSliceText -RawText $siblingText -Pattern '\b(CWI-[A-Za-z0-9-]+)\b'
$siblingCsrIds = Get-IdsFromSliceText -RawText $siblingText -Pattern '\b(CSR-[A-Za-z0-9-]+)\b'
$siblingCrIds = Get-IdsFromSliceText -RawText $siblingText -Pattern '\b(CR-[A-Za-z0-9-]+)\b'
$siblingGeIds = Get-IdsFromSliceText -RawText $siblingText -Pattern '\b(GE-[A-Za-z0-9-]+)\b'
$siblingGedgeIds = Get-IdsFromSliceText -RawText $siblingText -Pattern '\b(GEDGE-[A-Za-z0-9-]+)\b'

if ($siblingCwiIds.Count -eq 0) { Add-Issue $issues "No Work Item IDs could be harvested from sibling slices; cross-slice CWI binding checks would silently no-op." }
if ($siblingCsrIds.Count -eq 0) { Add-Issue $issues "No Source Record IDs could be harvested from sibling slices; cross-slice CSR binding checks would silently no-op." }
if ($siblingCrIds.Count -eq 0) { Add-Issue $issues "No Receipt IDs could be harvested from sibling slices; cross-slice CR grounding checks would silently no-op." }

# Structured harvest of work items / sources / receipts for resolution checks.
$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$knownWorkItemIds = @(($story13Items + $story14Items) | ForEach-Object { [string]$_.com_council_work_item_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$manualSources = @($manualSlice.manualCapture.sampleRecords | Where-Object { $null -ne $_ })
$outlookSources = @($outlookSlice.outlookCapture.sampleRecords | Where-Object { $null -ne $_ })
$story14EmbeddedSources = @($story14Extraction.extractionRun.embeddedSampleSourceRecords | Where-Object { $null -ne $_ })
$knownSourceIds = @(($manualSources + $outlookSources + $story14EmbeddedSources) | ForEach-Object { [string]$_.com_council_source_record_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$driftReceiptIds = @($story15Drift.driftRun.receipts | ForEach-Object { [string]$_.com_receipt_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$demoReceiptIds = @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
$knownReceiptIds = @($driftReceiptIds + $demoReceiptIds + $siblingCrIds) | Sort-Object -Unique
$knownSourceIds = @($knownSourceIds + $siblingCsrIds) | Sort-Object -Unique
$knownWorkItemIds = @($knownWorkItemIds + $siblingCwiIds) | Sort-Object -Unique

# --- Slice-level guards / metadata ---
if ($graph.storyKey -ne "4-1-create-lightweight-meaning-graph-records") {
  Add-Issue $issues "Meaning graph slice storyKey must be 4-1-create-lightweight-meaning-graph-records, found: $($graph.storyKey)."
}
if ([string]$graph.status -notmatch "^local-contract") {
  Add-Issue $issues "Meaning graph slice status must declare local contract evidence, found: $($graph.status)."
}
foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "requiresExplicitHumanApprovalForExecution", "sourceRecordsRemainSeparate", "meaningGraphDoesNotOwnWorkflowState", "dataverseRowsNotUsedAsCouncilIdentity", "receiptsAreLocalContractEvidenceOnly", "edgesOwnNoWorkflowState", "graphIsExplanationNotWorkflowAuthority", "noWorkItemStateChangeInThisSlice")) {
  if (-not ($graph.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Meaning graph slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($graph.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Meaning graph guard must be boolean true: $($guardProperty.Name)."
  }
}

$run = $graph.meaningGraphRun
if ($null -eq $run) {
  Add-Issue $issues "Meaning graph slice must carry a meaningGraphRun block."
  Write-Host "Meaning graph records slice validation failed:"
  foreach ($issue in $issues) { Write-Host "- $issue" }
  exit 1
}
foreach ($field in @("runId", "actorType", "actorId", "authorityBasis", "semanticContractVersion")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Meaning graph run must carry a non-empty ${field}."
  }
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Meaning graph run semanticContractVersion must be 2026-07-07, found: $($run.semanticContractVersion)."
}
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Meaning graph run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "proposed-work-item-extraction-slice.json", "zero-multi-item-extraction-slice.json", "source-drift-supersession-slice.json")) {
  if (@($run.inputFromSiblingSlices) -notcontains $inputSlice) {
    Add-Issue $issues "Meaning graph run must reference $inputSlice as an input."
  }
}
$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Meaning graph run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("graphIsExplanationOnlyNeverWorkflowAuthority", "edgesCarryNoWorkflowStateFields", "edgeGroundingResolvesToSiblingSlices", "liveGraphMutationReceiptGatedToEpic2", "entityBindingsReferenceExistingSiblingIdsOnly")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Meaning graph run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Meaning graph run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# --- Graph entities ---
$entities = @($run.graphEntities | Where-Object { $null -ne $_ })
if ($entities.Count -lt 8) {
  Add-Issue $issues "Meaning graph slice must include at least 8 graph entities (2 work items, 2 sources, person, role, project, topic), found $($entities.Count)."
}

# Slice-local required fields: manifest-required + com_external_binding_ref (nullable but must be present).
$entityRequiredFields = @($manifestRequiredEntityFields + @("com_external_binding_ref")) | Sort-Object -Unique
$sliceEntityIds = @{}
$seenEntityIds = @{}
foreach ($entity in $entities) {
  $entityId = [string]$entity.com_council_graph_entity_id
  $subject = "Graph entity $entityId"
  foreach ($field in $entityRequiredFields) {
    if (-not (@($entity.PSObject.Properties.Name) -contains $field)) {
      Add-Issue $issues "$subject missing required field: $field."
    }
  }
  if ([string]::IsNullOrWhiteSpace($entityId)) {
    Add-Issue $issues "Graph entity must declare com_council_graph_entity_id."
    continue
  }
  if ($entityId -notmatch "^GE-LOCAL-") {
    Add-Issue $issues "$subject must use fresh GE-LOCAL-* identity, found: $entityId."
  }
  if ($seenEntityIds.ContainsKey($entityId)) {
    Add-Issue $issues "Duplicate graph entity ID in slice: $entityId."
  } else { $seenEntityIds[$entityId] = $true }
  if ($siblingGeIds -contains $entityId) {
    Add-Issue $issues "$subject collides with an id appearing in a sibling slice; new GE-LOCAL-* ids must be unique across all slices."
  }
  $sliceEntityIds[$entityId] = $entity

  if ($graphEntityTypes -notcontains $entity.com_entity_type) {
    Add-Issue $issues "$subject com_entity_type is not in manifest com_graphentitytype vocabulary, found: $($entity.com_entity_type)."
  }
  if ($recordStatuses -notcontains $entity.com_status) {
    Add-Issue $issues "$subject com_status is not in manifest com_recordstatus vocabulary, found: $($entity.com_status)."
  }
  if ($entity.com_semantic_contract_version -ne "2026-07-07") {
    Add-Issue $issues "$subject com_semantic_contract_version must be 2026-07-07, found: $($entity.com_semantic_contract_version)."
  }

  # external_binding_ref: nullable, but when present must resolve to a sibling CWI/CSR/CR id.
  $binding = [string]$entity.com_external_binding_ref
  if (-not [string]::IsNullOrWhiteSpace($binding)) {
    if ($binding -match "^CWI-") {
      if ($knownWorkItemIds -notcontains $binding) {
        Add-Issue $issues "$subject com_external_binding_ref references an unknown sibling Work Item: $binding."
      }
    }
    elseif ($binding -match "^CSR-") {
      if ($knownSourceIds -notcontains $binding) {
        Add-Issue $issues "$subject com_external_binding_ref references an unknown sibling Source Record: $binding."
      }
    }
    elseif ($binding -match "^CR-") {
      if ($knownReceiptIds -notcontains $binding) {
        Add-Issue $issues "$subject com_external_binding_ref references an unknown sibling Receipt: $binding."
      }
    }
    else {
      Add-Issue $issues "$subject com_external_binding_ref must be a CWI-*/CSR-*/CR-* sibling id or null, found: $binding."
    }
  }
  # No state fields on entities either (entities are explanation nodes, not workflow authority).
  foreach ($prop in @($entity.PSObject.Properties)) {
    $propName = [string]$prop.Name
    if ($propName -match "(?i)(com_state_group|com_work_item_state|com_before_state|com_after_state|\bstate\b|\bstatus\b|state_group|work_item_state)") {
      Add-Issue $issues "$subject must not carry a workflow-state field: $propName; graph entities carry no workflow state."
    }
  }
}

# Coverage: at least 2 work-item-bound entities, 2 source-bound entities, person, role, project, topic.
$workItemBoundEntities = @($entities | Where-Object { [string]$_.com_external_binding_ref -match "^CWI-" })
$sourceBoundEntities = @($entities | Where-Object { [string]$_.com_external_binding_ref -match "^CSR-" })
$distinctWorkItemBindings = @($workItemBoundEntities | ForEach-Object { [string]$_.com_external_binding_ref } | Sort-Object -Unique)
$distinctSourceBindings = @($sourceBoundEntities | ForEach-Object { [string]$_.com_external_binding_ref } | Sort-Object -Unique)
if ($distinctWorkItemBindings.Count -lt 2) {
  Add-Issue $issues "Meaning graph slice must bind at least 2 distinct Work Items as graph entities, found $($distinctWorkItemBindings.Count)."
}
if ($distinctSourceBindings.Count -lt 2) {
  Add-Issue $issues "Meaning graph slice must bind at least 2 distinct Source Records as graph entities, found $($distinctSourceBindings.Count)."
}
foreach ($requiredType in @("person", "role", "project", "topic")) {
  $countOfType = @($entities | Where-Object { [string]$_.com_entity_type -eq $requiredType }).Count
  if ($countOfType -lt 1) {
    Add-Issue $issues "Meaning graph slice must include at least one graph entity of type '$requiredType'."
  }
}

# --- Graph edges ---
$edges = @($run.graphEdges | Where-Object { $null -ne $_ })
if ($edges.Count -lt 6) {
  Add-Issue $issues "Meaning graph slice must include at least 6 graph edges, found $($edges.Count)."
}

$edgeRequiredFields = @($manifestRequiredEdgeFields + @("com_from_entity", "com_to_entity", "com_source_record", "com_receipt", "com_rationale", "com_confidence", "retainedValueTag")) | Sort-Object -Unique
$retainedValueTags = @("routing", "retrieval", "provenance", "context", "explanation", "audit")
$sliceEdgeIds = @{}
$seenEdgeIds = @{}
$usedRetainedTags = @{}
foreach ($edge in $edges) {
  $edgeName = [string]$edge.com_name
  $subject = "Graph edge $edgeName"
  foreach ($field in $edgeRequiredFields) {
    if (-not (@($edge.PSObject.Properties.Name) -contains $field)) {
      Add-Issue $issues "$subject missing required field: $field."
    }
  }
  if ([string]::IsNullOrWhiteSpace($edgeName)) {
    Add-Issue $issues "Graph edge must declare com_name."
    continue
  }
  if ($edgeName -notmatch "^GEDGE-LOCAL-") {
    Add-Issue $issues "$subject com_name must use fresh GEDGE-LOCAL-* identity, found: $edgeName."
  }
  if ($seenEdgeIds.ContainsKey($edgeName)) {
    Add-Issue $issues "Duplicate graph edge com_name in slice: $edgeName."
  } else { $seenEdgeIds[$edgeName] = $true }
  if ($siblingGedgeIds -contains $edgeName) {
    Add-Issue $issues "$subject collides with an id appearing in a sibling slice; new GEDGE-LOCAL-* ids must be unique across all slices."
  }
  $sliceEdgeIds[$edgeName] = $edge

  if ($graphEdgeTypes -notcontains $edge.com_edge_type) {
    Add-Issue $issues "$subject com_edge_type is not in manifest com_graphedgetype vocabulary, found: $($edge.com_edge_type)."
  }

  # Entity endpoint resolution.
  foreach ($endpointField in @("com_from_entity", "com_to_entity")) {
    $endpointId = [string]$edge.$endpointField
    if ([string]::IsNullOrWhiteSpace($endpointId)) {
      Add-Issue $issues "$subject $endpointField must name a graph entity in this slice (null endpoints are not allowed)."
    }
    elseif (-not $sliceEntityIds.ContainsKey($endpointId)) {
      Add-Issue $issues "$subject $endpointField references an unknown graph entity in this slice: $endpointId."
    }
  }

  # Work item endpoint resolution (when present).
  foreach ($wiField in @("com_from_work_item", "com_to_work_item")) {
    if (@($edge.PSObject.Properties.Name) -contains $wiField) {
      $wiRef = [string]$edge.$wiField
      if (-not [string]::IsNullOrWhiteSpace($wiRef) -and $knownWorkItemIds -notcontains $wiRef) {
        Add-Issue $issues "$subject $wiField references an unknown sibling Work Item: $wiRef."
      }
    }
  }

  # Grounding refs: both source_record and receipt must be present and resolve to sibling slices.
  $sourceRef = [string]$edge.com_source_record
  if ([string]::IsNullOrWhiteSpace($sourceRef)) {
    Add-Issue $issues "$subject must carry a non-empty com_source_record grounding ref."
  }
  elseif ($knownSourceIds -notcontains $sourceRef) {
    Add-Issue $issues "$subject com_source_record grounding ref does not resolve to a sibling-slice Source Record: $sourceRef."
  }
  $receiptRef = [string]$edge.com_receipt
  if ([string]::IsNullOrWhiteSpace($receiptRef)) {
    Add-Issue $issues "$subject must carry a non-empty com_receipt grounding ref."
  }
  elseif ($knownReceiptIds -notcontains $receiptRef) {
    Add-Issue $issues "$subject com_receipt grounding ref does not resolve to a sibling-slice Receipt: $receiptRef."
  }

  # Rationale non-empty.
  if (-not (Test-HasNonEmptyField -Record $edge -Field "com_rationale")) {
    Add-Issue $issues "$subject must carry a non-empty com_rationale."
  }

  # Confidence TryParse [0,1].
  Test-ConfidenceInRange -Issues $issues -Record $edge -Field "com_confidence" -Subject $subject

  # Retained-value tag membership in closed set.
  $tag = [string]$edge.retainedValueTag
  if ([string]::IsNullOrWhiteSpace($tag)) {
    Add-Issue $issues "$subject must carry a non-empty retainedValueTag."
  }
  elseif ($retainedValueTags -notcontains $tag) {
    Add-Issue $issues "$subject retainedValueTag must be in the closed set {routing, retrieval, provenance, context, explanation, audit}, found: $tag."
  }
  else {
    $usedRetainedTags[$tag] = $true
  }

  # com_created_receipt (when present) must resolve to a sibling receipt.
  if (@($edge.PSObject.Properties.Name) -contains "com_created_receipt") {
    $createdReceipt = [string]$edge.com_created_receipt
    if (-not [string]::IsNullOrWhiteSpace($createdReceipt) -and $knownReceiptIds -notcontains $createdReceipt) {
      Add-Issue $issues "$subject com_created_receipt references an unknown sibling Receipt: $createdReceipt."
    }
  }

  # No state fields on any edge (authority guard scan).
  foreach ($prop in @($edge.PSObject.Properties)) {
    $propName = [string]$prop.Name
    if ($propName -match "(?i)(com_state_group|com_work_item_state|com_before_state|com_after_state|\bstate\b|\bstatus\b|state_group|work_item_state)") {
      Add-Issue $issues "$subject must not carry a workflow-state field: $propName; edges own no workflow state."
    }
  }
}

# Every retained-value tag in the closed set must be exercised by at least one edge.
foreach ($requiredTag in $retainedValueTags) {
  if (-not $usedRetainedTags.ContainsKey($requiredTag)) {
    Add-Issue $issues "Meaning graph slice must exercise every retained-value tag at least once; missing: $requiredTag."
  }
}

# --- Authority guard ---
Test-StrictBooleanTrue -Issues $issues -Record $graph.guards -Field "edgesOwnNoWorkflowState" -Subject "Meaning graph slice guards"
Test-StrictBooleanTrue -Issues $issues -Record $graph.guards -Field "meaningGraphDoesNotOwnWorkflowState" -Subject "Meaning graph slice guards"

$authorityGuard = $run.authorityGuard
if ($null -eq $authorityGuard) {
  Add-Issue $issues "Meaning graph run must declare an authorityGuard block."
}
else {
  Test-StrictBooleanTrue -Issues $issues -Record $authorityGuard -Field "edgesOwnNoWorkflowState" -Subject "authorityGuard"
  Test-StrictBooleanTrue -Issues $issues -Record $authorityGuard -Field "noStateFieldsOnAnyEdge" -Subject "authorityGuard"
  if (-not (Test-HasNonEmptyField -Record $authorityGuard -Field "guardStatement")) {
    Add-Issue $issues "authorityGuard must carry a non-empty guardStatement."
  }
  $demo = $authorityGuard.demonstration
  if ($null -eq $demo) {
    Add-Issue $issues "authorityGuard must declare a demonstration entry proving a Work Item state group is identical before and after edge creation."
  }
  else {
    $demoWorkItem = [string]$demo.workItem
    if ([string]::IsNullOrWhiteSpace($demoWorkItem) -or $knownWorkItemIds -notcontains $demoWorkItem) {
      Add-Issue $issues "authorityGuard demonstration workItem must resolve to a sibling-slice Work Item, found: $demoWorkItem."
    }
    $demoBoundEntity = [string]$demo.boundGraphEntity
    if ([string]::IsNullOrWhiteSpace($demoBoundEntity) -or -not $sliceEntityIds.ContainsKey($demoBoundEntity)) {
      Add-Issue $issues "authorityGuard demonstration boundGraphEntity must resolve to a graph entity in this slice, found: $demoBoundEntity."
    }
    else {
      $boundEntity = $sliceEntityIds[$demoBoundEntity]
      if ([string]$boundEntity.com_external_binding_ref -ne $demoWorkItem) {
        Add-Issue $issues "authorityGuard demonstration boundGraphEntity must bind the demonstrated Work Item ($demoWorkItem), but it binds: $($boundEntity.com_external_binding_ref)."
      }
    }
    if ($workItemStateGroups -notcontains [string]$demo.beforeStateGroup) {
      Add-Issue $issues "authorityGuard demonstration beforeStateGroup must be in manifest com_workitemstategroup vocabulary, found: $($demo.beforeStateGroup)."
    }
    if ($workItemStateGroups -notcontains [string]$demo.afterStateGroup) {
      Add-Issue $issues "authorityGuard demonstration afterStateGroup must be in manifest com_workitemstategroup vocabulary, found: $($demo.afterStateGroup)."
    }
    if ([string]$demo.beforeStateGroup -ne [string]$demo.afterStateGroup) {
      Add-Issue $issues "authorityGuard demonstration must show an IDENTICAL Work Item state group before ($($demo.beforeStateGroup)) and after ($($demo.afterStateGroup)) edge creation; the graph owns no workflow state."
    }
    Test-StrictBooleanTrue -Issues $issues -Record $demo -Field "stateGroupIdenticalBeforeAndAfterEdgeCreation" -Subject "authorityGuard demonstration"
    $touchingEdges = @($demo.edgesTouchingThisWorkItem | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($touchingEdges.Count -lt 1) {
      Add-Issue $issues "authorityGuard demonstration must name at least one edge touching the demonstrated Work Item."
    }
    foreach ($touchingEdge in $touchingEdges) {
      if (-not $sliceEdgeIds.ContainsKey([string]$touchingEdge)) {
        Add-Issue $issues "authorityGuard demonstration edgesTouchingThisWorkItem references an unknown graph edge: $touchingEdge."
      }
    }
    if (-not (Test-HasNonEmptyField -Record $demo -Field "note")) {
      Add-Issue $issues "authorityGuard demonstration must carry a non-empty note."
    }
  }
}

# --- Deferred live mutation entries ---
$deferred = @($run.liveGraphMutationDeferred | Where-Object { $null -ne $_ })
if ($deferred.Count -lt 1) {
  Add-Issue $issues "Meaning graph slice must declare at least one liveGraphMutationDeferred entry."
}
foreach ($entry in $deferred) {
  if (-not (Test-HasNonEmptyField -Record $entry -Field "deferredUpdate")) {
    Add-Issue $issues "liveGraphMutationDeferred entry must carry a non-empty deferredUpdate."
  }
  elseif ([string]$entry.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "liveGraphMutationDeferred entry must state that the live mutation is receipt-gated."
  }
}

# --- Acceptance mapping ---
foreach ($criterion in @(1, 2, 3)) {
  $mapping = @($graph.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
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

# --- Final report ---
if ($issues.Count -gt 0) {
  Write-Host "Meaning graph records slice validation failed:"
  foreach ($issue in $issues) { Write-Host "- $issue" }
  exit 1
}

Write-Host "Meaning graph records slice validation succeeded."
Write-Host "Graph entities: $($entities.Count)"
Write-Host "Graph edges: $($edges.Count)"
Write-Host "Retained-value tags exercised: $(@($usedRetainedTags.Keys | Sort-Object) -join ', ')"
Write-Host "MEANING_GRAPH_RECORDS_SLICE_VALIDATE_OK"
