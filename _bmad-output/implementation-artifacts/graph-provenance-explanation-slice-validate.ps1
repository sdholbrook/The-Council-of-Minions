param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$SlicePath = "$PSScriptRoot\graph-provenance-explanation-slice.json",
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
    Write-Host "Graph provenance explanation slice validation failed:"
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
    throw "Required graph provenance explanation validation input not found: $path"
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
$graphEntityTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_graphentitytype"
$evidenceRoles = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilreceiptsource" -ColumnName "com_evidence_role"

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_workitemstategroup"; Values = $stateGroups },
    @{ Name = "com_workitemtype"; Values = $workItemTypes },
    @{ Name = "com_graphentitytype"; Values = $graphEntityTypes },
    @{ Name = "com_councilreceiptsource.com_evidence_role"; Values = $evidenceRoles }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

# Story 4.2 speaks to graph provenance; the reviewed verb and no_op result must exist for explanation receipts.
foreach ($requiredVerb in @("reviewed")) {
  if ($receiptVerbs -notcontains $requiredVerb) {
    Add-Issue $issues "Manifest com_receiptverb is missing required explanation verb: $requiredVerb."
  }
}
if ($receiptResults -notcontains "no_op") {
  Add-Issue $issues "Manifest com_receiptresult is missing no_op, required for no-state-change explanation receipts."
}

if ($slice.storyKey -ne "4-2-explain-work-through-graph-provenance") {
  Add-Issue $issues "Explanation slice storyKey must be 4-2-explain-work-through-graph-provenance."
}
if ([string]$slice.status -notmatch "^local-contract") {
  Add-Issue $issues "Explanation slice status must declare local contract evidence, found: $($slice.status)."
}

$requiredGuards = @(
  "noTenantWrites",
  "noOutboundAction",
  "noApprovalExecution",
  "requiresExplicitHumanApprovalForExecution",
  "receiptsAreLocalContractEvidenceOnly",
  "receiptsAreAppendOnly",
  "meaningGraphDoesNotOwnWorkflowState",
  "dataverseRowsNotUsedAsCouncilIdentity",
  "noAutoApprovalFromGraph",
  "uncertaintyMustBeVisible",
  "explanationsAreReadOnlyProjections",
  "noWorkItemStateChangeInThisSlice"
)
foreach ($guard in $requiredGuards) {
  if (-not ($slice.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Explanation slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($slice.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Explanation guard must be boolean true: $($guardProperty.Name)."
  }
}

# Cross-slice ID inventories — harvested from the named sibling slices (1-1..1-5 + demo) AND
# from EVERY *-slice.json in $PSScriptRoot, so collision tripwires are live and not coupled
# to a hardcoded filename list. The slice under test is excluded.
$selfName = Split-Path -Leaf $SlicePath
$siblingRaw = @()
foreach ($siblingPath in @($ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $Story15DriftPath, $DemoEvidencePath)) {
  $siblingRaw += Get-Content -LiteralPath $siblingPath -Raw
}
foreach ($sibFile in (Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*-slice.json" -File)) {
  if ($sibFile.Name -eq $selfName) { continue }
  $sibRaw = Get-Content -LiteralPath $sibFile.FullName -Raw
  if ($siblingRaw -notcontains $sibRaw) {
    $siblingRaw += $sibRaw
  }
}
$siblingText = $siblingRaw -join "`n"

$siblingCwiIds = @(
  @(
    Get-IdsFromSliceText -RawText $siblingText -Pattern '"com_council_work_item_id"\s*:\s*"(CWI-[^"]+)"'
    Get-IdsFromSliceText -RawText $siblingText -Pattern '"(CWI-(?:LOCAL|DEMO)[^"]+)"'
    Get-IdsFromSliceText -RawText $siblingText -Pattern '\b(CWI-[A-Za-z0-9-]+)\b'
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
)
$siblingCrIds = @(
  @(
    Get-IdsFromSliceText -RawText $siblingText -Pattern '"com_receipt_id"\s*:\s*"(CR-[^"]+)"'
    Get-IdsFromSliceText -RawText $siblingText -Pattern '"(CR-(?:LOCAL|DEMO)[^"]+)"'
    Get-IdsFromSliceText -RawText $siblingText -Pattern '\b(CR-[A-Za-z0-9-]+)\b'
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
)
$siblingCsrIds = @(
  @(
    Get-IdsFromSliceText -RawText $siblingText -Pattern '"com_council_source_record_id"\s*:\s*"(CSR-[^"]+)"'
    Get-IdsFromSliceText -RawText $siblingText -Pattern '"(CSR-[^"]+)"'
    Get-IdsFromSliceText -RawText $siblingText -Pattern '\b(CSR-[A-Za-z0-9-]+)\b'
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
)

$demoReceiptIds = @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$demoWorkItemIds = @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($demoReceiptIds.Count -eq 0) {
  Add-Issue $issues "No reserved receipt IDs could be loaded from state-transition-demo-evidence.json; receipt collision checks would silently no-op."
}
if ($demoWorkItemIds.Count -eq 0) {
  Add-Issue $issues "No reserved work-item IDs could be loaded from state-transition-demo-evidence.json; work-item collision checks would silently no-op."
}

# Structured inventories unioned into raw harvest so tripwires cannot silent-no-op
$siblingCwiIds = @($siblingCwiIds + $demoWorkItemIds) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
$siblingCrIds = @($siblingCrIds + $demoReceiptIds) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

if ($siblingCwiIds.Count -eq 0) {
  Add-Issue $issues "No sibling CWI-* IDs could be harvested from slices 1-1..1-5/demo; cross-slice Work Item resolution checks would silently no-op."
}
if ($siblingCrIds.Count -eq 0) {
  Add-Issue $issues "No sibling CR-* IDs could be harvested from slices 1-1..1-5/demo; cross-slice receipt collision checks would silently no-op."
}
if ($siblingCsrIds.Count -eq 0) {
  Add-Issue $issues "No sibling CSR-* IDs could be harvested from slices 1-1..1-5; cross-slice source-record binding checks would silently no-op."
}

# Build a Work-Item id -> state-group map from every loaded sibling slice that carries proposedWorkItems/workItems,
# so the conflict scenario's unchanged-state claim is cross-checked against the referenced Work Item's home slice
# (content-proven, not self-asserted).
$workItemStateByHomeSlice = @{}
function Register-WorkItemStates {
  param(
    [Parameter(Mandatory = $true)]$SliceData,
    [Parameter(Mandatory = $true)][string]$HomeSlice
  )
  # Work Items may sit at the top level (Epic 2 stateChangeRun.workItems) or nested under a run block
  # (Epic 1 extractionRun.proposedWorkItems), so harvest from every plausible location.
  $candidateArrays = @()
  foreach ($prop in @("proposedWorkItems", "workItems")) {
    if ($null -ne $SliceData.$prop) {
      $candidateArrays += @($SliceData.$prop | Where-Object { $null -ne $_ })
    }
  }
  foreach ($runProp in @("extractionRun", "stateChangeRun")) {
    if ($null -ne $SliceData.$runProp) {
      foreach ($prop in @("proposedWorkItems", "workItems")) {
        if ($null -ne $SliceData.$runProp.$prop) {
          $candidateArrays += @($SliceData.$runProp.$prop | Where-Object { $null -ne $_ })
        }
      }
    }
  }
  foreach ($item in $candidateArrays) {
    $itemId = [string]$item.com_council_work_item_id
    if ([string]::IsNullOrWhiteSpace($itemId)) {
      continue
    }
    $stateGroup = [string]$item.com_state_group
    if (-not [string]::IsNullOrWhiteSpace($stateGroup)) {
      $workItemStateByHomeSlice[$itemId] = @{ HomeSlice = $HomeSlice; StateGroup = $stateGroup }
    }
  }
}
Register-WorkItemStates -SliceData $story13Extraction -HomeSlice "proposed-work-item-extraction-slice.json"
Register-WorkItemStates -SliceData $story14Extraction -HomeSlice "zero-multi-item-extraction-slice.json"

# Live state harvest: register Work-Item state groups from EVERY sibling *-slice.json in
# $PSScriptRoot, not only the two named extraction slices, so the unchanged-state cross-check
# proves coordination against actual sibling structure rather than a hardcoded slice list.
foreach ($sibFile in (Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*-slice.json" -File)) {
  if ($sibFile.Name -eq $selfName) { continue }
  try {
    $sibData = Get-Content -LiteralPath $sibFile.FullName -Raw | ConvertFrom-Json
    Register-WorkItemStates -SliceData $sibData -HomeSlice $sibFile.Name
  }
  catch {
    # Skip unparseable sibling slices; the explicitly loaded siblings carry the structured load.
  }
}

# Also union in drift-flagged Work Items (state unchanged in drift slice) for collision purposes.
$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$knownPriorWorkItemIds = @(($story13Items + $story14Items) | ForEach-Object { [string]$_.com_council_work_item_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($knownPriorWorkItemIds.Count -eq 0) {
  Add-Issue $issues "No Work Item IDs could be loaded from Story 1.3/1.4 slices; cross-slice CWI resolution checks would silently no-op."
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
$siblingCsrIds = @($siblingCsrIds + $knownPriorSourceIds) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
if ($knownPriorSourceIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be loaded from sibling slices; source-record binding checks would silently no-op."
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

$run = $slice.explanationRun
if ($null -eq $run) {
  Add-Issue $issues "Explanation slice must carry an explanationRun block."
  Write-Host "Graph provenance explanation slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Explanation run must declare a runId."
}
elseif ([string]$run.runId -match "DRIFT-LOCAL|EXTRACT-LOCAL|STATE-LOCAL") {
  Add-Issue $issues "Explanation run must use a new local runId, not a prior-story runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Explanation run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Explanation run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Explanation run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("proposed-work-item-extraction-slice.json", "zero-multi-item-extraction-slice.json")) {
  if (@($run.inputWorkItemsFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Explanation run must reference $inputSlice as a Work Item input."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "zero-multi-item-extraction-slice.json")) {
  if (@($run.inputSourceRecordsFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Explanation run must reference $inputSlice as a Source Record input."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Explanation run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("explanationsDistinguishEvidenceFromInference", "everyElementCarriesEvidenceKind", "uncertaintyIsAlwaysVisible", "graphEvidenceNeverAutoApproves", "stateChangesRequireNewReceiptAndStayDeferredToEpic2", "explanationsAreReadOnlyProjections")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Explanation run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Explanation run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

$explanations = @($run.explanations | Where-Object { $null -ne $_ })
if ($explanations.Count -lt 2) {
  Add-Issue $issues "Explanation slice must include at least two explanations (one provenance, one conflict/uncertain), found $($explanations.Count)."
}

$allowedEvidenceKinds = @("evidence", "inference")
$seenExplanationIds = @{}
$seenElementIds = @{}
$sliceReferencedWorkItemIds = @()
$sliceReferencedSourceIds = @()
$conflictFound = $false
$provenanceFound = $false

# Manifest receipt table required fields, harvested so required-field checks cannot silently no-op
$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags", "com_work_item")) | Sort-Object -Unique

# Build the slice-local receipt id set first so element receipt references can be validated against it.
$sliceReceipts = @($run.receipts | Where-Object { $null -ne $_ })
$sliceReceiptIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($receipt in $sliceReceipts) {
  $rid = [string]$receipt.com_receipt_id
  if (-not [string]::IsNullOrWhiteSpace($rid)) {
    $sliceReceiptIds.Add($rid) | Out-Null
  }
}

foreach ($explanation in $explanations) {
  $explanationId = [string]$explanation.explanationId
  $exSubject = "Explanation $explanationId"
  if ([string]::IsNullOrWhiteSpace($explanationId)) {
    Add-Issue $issues "Explanation must declare an explanationId."
  }
  else {
    if ($seenExplanationIds.ContainsKey($explanationId)) {
      Add-Issue $issues "Duplicate explanationId: $explanationId."
    }
    else {
      $seenExplanationIds[$explanationId] = $true
    }
  }

  $workItemId = [string]$explanation.workItem
  if ([string]::IsNullOrWhiteSpace($workItemId)) {
    Add-Issue $issues "$exSubject must reference a Work Item."
  }
  else {
    $sliceReferencedWorkItemIds += $workItemId
    # Must resolve to a known sibling CWI (raw harvest + structured inventories)
    if ($siblingCwiIds -notcontains $workItemId -and $knownPriorWorkItemIds -notcontains $workItemId) {
      Add-Issue $issues "$exSubject references an unknown sibling Work Item: $workItemId."
    }
  }

  $homeSlice = [string]$explanation.workItemHomeSlice
  $claimedState = [string]$explanation.workItemStateGroupClaimed
  if ([string]::IsNullOrWhiteSpace($homeSlice)) {
    Add-Issue $issues "$exSubject must declare a workItemHomeSlice for cross-slice state verification."
  }
  if ([string]::IsNullOrWhiteSpace($claimedState)) {
    Add-Issue $issues "$exSubject must declare workItemStateGroupClaimed."
  }
  elseif ($stateGroups -notcontains $claimedState) {
    Add-Issue $issues "$exSubject workItemStateGroupClaimed must be a manifest com_workitemstategroup value, found: $claimedState."
  }

  # Cross-slice state verification: the claimed state must match the Work Item's actual state group in its home slice.
  if (-not [string]::IsNullOrWhiteSpace($workItemId) -and $workItemStateByHomeSlice.ContainsKey($workItemId)) {
    $homeEntry = $workItemStateByHomeSlice[$workItemId]
    $actualHomeSlice = [string]$homeEntry.HomeSlice
    $actualState = [string]$homeEntry.StateGroup
    if (-not [string]::IsNullOrWhiteSpace($homeSlice) -and $actualHomeSlice -ne $homeSlice) {
      Add-Issue $issues "$exSubject workItemHomeSlice ($homeSlice) must match the Work Item's actual home slice ($actualHomeSlice) for $workItemId."
    }
    if (-not [string]::IsNullOrWhiteSpace($claimedState) -and $actualState -ne $claimedState) {
      Add-Issue $issues "$exSubject workItemStateGroupClaimed ($claimedState) must match the Work Item's actual state group in its home slice ($actualState) for $workItemId."
    }
  }
  else {
    Add-Issue $issues "$exSubject references Work Item $workItemId whose state group could not be loaded from any sibling slice; unchanged-state cross-check would silently no-op."
  }

  if (-not (Test-HasNonEmptyField -Record $explanation -Field "summary")) {
    Add-Issue $issues "$exSubject must carry a non-empty summary."
  }

  $elements = @($explanation.elements | Where-Object { $null -ne $_ })
  if ($elements.Count -lt 3) {
    Add-Issue $issues "$exSubject must include at least three provenance elements (source/people/roles/projects/topics/receipts), found $($elements.Count)."
  }

  $hasSourceElement = $false
  $hasReceiptElement = $false
  foreach ($element in $elements) {
    $elementId = [string]$element.elementId
    $elSubject = "$exSubject element $elementId"
    if ([string]::IsNullOrWhiteSpace($elementId)) {
      Add-Issue $issues "$elSubject must declare an elementId."
    }
    else {
      if ($seenElementIds.ContainsKey($elementId)) {
        Add-Issue $issues "Duplicate elementId across explanations: $elementId."
      }
      else {
        $seenElementIds[$elementId] = $true
      }
    }
    if (-not (Test-HasNonEmptyField -Record $element -Field "label")) {
      Add-Issue $issues "$elSubject must carry a non-empty label."
    }
    $elementType = [string]$element.elementType
    if ([string]::IsNullOrWhiteSpace($elementType)) {
      Add-Issue $issues "$elSubject must declare an elementType."
    }
    elseif ($graphEntityTypes -notcontains $elementType -and $elementType -ne "receipt") {
      Add-Issue $issues "$elSubject elementType must be a manifest com_graphentitytype value or 'receipt', found: $elementType."
    }
    if ($elementType -eq "source") {
      $hasSourceElement = $true
    }
    if ($elementType -eq "receipt") {
      $hasReceiptElement = $true
    }

    # evidenceKind closed set — REQUIRED on EVERY element, no conditional/skippable check
    if (-not (Test-HasNonEmptyField -Record $element -Field "evidenceKind")) {
      Add-Issue $issues "$elSubject must carry a non-empty evidenceKind."
    }
    elseif ($allowedEvidenceKinds -notcontains [string]$element.evidenceKind) {
      Add-Issue $issues "$elSubject evidenceKind must be from the closed set {evidence, inference}, found: $($element.evidenceKind)."
    }

    Test-ConfidenceInRange -Issues $issues -Record $element -Field "confidence" -Subject $elSubject

    if (-not (Test-HasNonEmptyField -Record $element -Field "provenance")) {
      Add-Issue $issues "$elSubject must carry a non-empty provenance statement."
    }

    # Source elements must bind a known sibling CSR (no self-asserted source identity)
    if ($elementType -eq "source") {
      $sourceRef = [string]$element.sourceRecord
      if ([string]::IsNullOrWhiteSpace($sourceRef)) {
        Add-Issue $issues "$elSubject source element must declare a sourceRecord."
      }
      elseif ($siblingCsrIds -notcontains $sourceRef -and $knownPriorSourceIds -notcontains $sourceRef) {
        Add-Issue $issues "$elSubject sourceRecord must reference a known sibling CSR-* id, found: $sourceRef."
      }
      else {
        $sliceReferencedSourceIds += $sourceRef
      }
    }

    # Receipt elements must bind a slice-local receipt id (content-proven, not free text)
    if ($elementType -eq "receipt") {
      $receiptRef = [string]$element.receipt
      if ([string]::IsNullOrWhiteSpace($receiptRef)) {
        Add-Issue $issues "$elSubject receipt element must declare a receipt reference."
      }
      elseif (-not $sliceReceiptIds.Contains($receiptRef)) {
        Add-Issue $issues "$elSubject receipt reference must resolve to a receipt declared in this slice, found: $receiptRef."
      }
    }
  }

  if (-not $hasSourceElement) {
    Add-Issue $issues "$exSubject must include at least one source element anchoring provenance to a Source Record."
  }

  $supportingReceipts = @($explanation.supportingReceipts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($supportingReceipts.Count -lt 1) {
    Add-Issue $issues "$exSubject must list at least one supporting receipt."
  }
  foreach ($rid in $supportingReceipts) {
    if (-not $sliceReceiptIds.Contains([string]$rid)) {
      Add-Issue $issues "$exSubject supportingReceipts must reference a receipt declared in this slice, found: $rid."
    }
  }

  if (-not (Test-HasNonEmptyField -Record $explanation -Field "overallConfidence")) {
    Add-Issue $issues "$exSubject must declare an overallConfidence."
  }
  else {
    $parsedOverall = [decimal]0
    if (-not [decimal]::TryParse([string]$explanation.overallConfidence, [System.Globalization.NumberStyles]::Number, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedOverall)) {
      Add-Issue $issues "$exSubject overallConfidence must be numeric, found: $($explanation.overallConfidence)."
    }
    elseif ($parsedOverall -lt 0 -or $parsedOverall -gt 1) {
      Add-Issue $issues "$exSubject overallConfidence must be between 0 and 1, found: $parsedOverall."
    }
  }

  # uncertaintyVisible strict boolean on EVERY explanation — uncertainty must always be a visible flag
  if ($explanation.uncertaintyVisible -isnot [bool]) {
    Add-Issue $issues "$exSubject uncertaintyVisible must be a strict boolean."
  }
  # noAutoApprovalFromGraph strict boolean on EVERY explanation — graph never auto-approves
  if ($explanation.noAutoApprovalFromGraph -isnot [bool] -or -not $explanation.noAutoApprovalFromGraph) {
    Add-Issue $issues "$exSubject noAutoApprovalFromGraph must be strict boolean true; graph evidence must never auto-approve."
  }
  # stateGroupChangedInThisSlice strict boolean false — explanations move no state
  if ($explanation.stateGroupChangedInThisSlice -isnot [bool] -or $explanation.stateGroupChangedInThisSlice) {
    Add-Issue $issues "$exSubject stateGroupChangedInThisSlice must be strict boolean false; explanations are read-only projections."
  }

  # Conflict/uncertain scenario requirements: a conflict block forces uncertaintyVisible=true AND unchanged state.
  $conflict = $explanation.conflict
  if ($null -ne $conflict) {
    $conflictFound = $true
    if (-not (Test-HasNonEmptyField -Record $conflict -Field "description")) {
      Add-Issue $issues "$exSubject conflict must carry a non-empty description."
    }
    $conflictingElements = @($conflict.conflictingElements | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($conflictingElements.Count -lt 2) {
      Add-Issue $issues "$exSubject conflict.conflictingElements must name at least two element ids in tension."
    }
    else {
      foreach ($ceId in $conflictingElements) {
        if (-not $seenElementIds.ContainsKey([string]$ceId)) {
          Add-Issue $issues "$exSubject conflict.conflictingElements references an unknown element: $ceId."
        }
      }
    }
    if (-not (Test-HasNonEmptyField -Record $conflict -Field "resolution")) {
      Add-Issue $issues "$exSubject conflict must carry a non-empty resolution."
    }
    # Conflict scenario MUST surface uncertainty and MUST NOT auto-approve (the heart of FR19/FR20)
    if ($explanation.uncertaintyVisible -isnot [bool] -or -not $explanation.uncertaintyVisible) {
      Add-Issue $issues "$exSubject with a conflict must set uncertaintyVisible=true (strict boolean); uncertainty must be visible."
    }
    if ($explanation.noAutoApprovalFromGraph -isnot [bool] -or -not $explanation.noAutoApprovalFromGraph) {
      Add-Issue $issues "$exSubject with a conflict must set noAutoApprovalFromGraph=true (strict boolean); graph evidence must never auto-approve."
    }
    # State group must be unchanged for the conflict Work Item — cross-checked against its home slice above.
    if ($explanation.stateGroupChangedInThisSlice -isnot [bool] -or $explanation.stateGroupChangedInThisSlice) {
      Add-Issue $issues "$exSubject with a conflict must keep stateGroupChangedInThisSlice=false; the Work Item was not auto-approved."
    }
  }
  else {
    $provenanceFound = $true
  }
}

if (-not $provenanceFound) {
  Add-Issue $issues "Explanation slice must include at least one plain provenance explanation (no conflict block)."
}
if (-not $conflictFound) {
  Add-Issue $issues "Explanation slice must include at least one conflicting/uncertain-evidence explanation with a conflict block."
}

# Receipts
if ($sliceReceipts.Count -lt 3) {
  Add-Issue $issues "Explanation slice must include at least three receipts (one review + conflict trail of two), found $($sliceReceipts.Count)."
}
$sliceReceiptIdSet = @{}
$seenIdempotencyKeys = @{}
foreach ($receipt in $sliceReceipts) {
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
    if ($sliceReceiptIdSet.ContainsKey($receiptId)) {
      Add-Issue $issues "Duplicate receipt ID in slice: $receiptId."
    }
    else {
      $sliceReceiptIdSet[$receiptId] = $true
    }
    # Active cross-slice collision against full raw-text harvest of siblings 1-1..1-5 + demo
    if ($siblingCrIds -contains $receiptId) {
      Add-Issue $issues "$subject collides with a sibling-slice or demo receipt ID harvested from slices 1-1..1-5/demo."
    }
  }

  $workItemRef = [string]$receipt.com_work_item
  if (-not [string]::IsNullOrWhiteSpace($workItemRef)) {
    # Receipts may only target Work Items that are either referenced by an explanation or known siblings.
    if ($sliceReferencedWorkItemIds -notcontains $workItemRef -and $siblingCwiIds -notcontains $workItemRef -and $knownPriorWorkItemIds -notcontains $workItemRef) {
      Add-Issue $issues "$subject references an unknown Work Item: $workItemRef."
    }
  }

  if ($receiptVerbs -notcontains $receipt.com_verb) {
    Add-Issue $issues "$subject verb is not in manifest com_receiptverb vocabulary: $($receipt.com_verb)."
  }
  elseif ($receipt.com_verb -ne "reviewed") {
    Add-Issue $issues "$subject must use verb reviewed for Story 4.2 explanation evidence, found: $($receipt.com_verb)."
  }
  if ($actorTypes -notcontains $receipt.com_actor_type) {
    Add-Issue $issues "$subject actor type is not in manifest com_actortype vocabulary: $($receipt.com_actor_type)."
  }
  if ($receiptResults -notcontains $receipt.com_result) {
    Add-Issue $issues "$subject result is not in manifest com_receiptresult vocabulary: $($receipt.com_result)."
  }
  elseif ($receipt.com_result -ne "no_op") {
    Add-Issue $issues "$subject must use result no_op; explanations move no Work Item state, found: $($receipt.com_result)."
  }

  $before = [string]$receipt.com_before_state
  $after = [string]$receipt.com_after_state
  if ($stateGroups -notcontains $before) {
    Add-Issue $issues "$subject com_before_state must be a manifest state group, found: $before."
  }
  if ($stateGroups -notcontains $after) {
    Add-Issue $issues "$subject com_after_state must be a manifest state group, found: $after."
  }
  # Explanation receipts must NOT move state — before and after must be equal (read-only projection).
  if ($before -ne $after) {
    Add-Issue $issues "$subject com_before_state and com_after_state must be equal; explanation receipts must not move Work Item state, found: $before -> $after."
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
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 4.2 receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write", "no_auto_approval_from_graph")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 4.2 receipts are local contract evidence and never auto-approve."
      }
    }
  }
}

foreach ($expectedReceiptId in @("CR-LOCAL-EXPLAIN-REVIEW-001", "CR-LOCAL-EXPLAIN-CONFLICT-001", "CR-LOCAL-EXPLAIN-NOAUTO-001")) {
  if (-not $sliceReceiptIdSet.ContainsKey($expectedReceiptId)) {
    Add-Issue $issues "Explanation slice must include receipt $expectedReceiptId."
  }
}

# Receipt source links — bind explanation receipts to the provenance Source Records
$links = @($run.receiptSourceLinks | Where-Object { $null -ne $_ })
if ($links.Count -lt 1) {
  Add-Issue $issues "Explanation slice must include at least one receiptSourceLinks entry binding receipts to source provenance."
}
foreach ($link in $links) {
  $linkSubject = "Receipt source link $($link.com_name)"
  if (-not (Test-HasNonEmptyField -Record $link -Field "com_name")) {
    Add-Issue $issues "Receipt source link must carry a non-empty com_name."
  }
  $linkReceiptId = [string]$link.com_receipt
  if ([string]::IsNullOrWhiteSpace($linkReceiptId) -or -not $sliceReceiptIdSet.ContainsKey($linkReceiptId)) {
    Add-Issue $issues "$linkSubject references unknown receipt: $linkReceiptId."
  }
  $linkSourceId = [string]$link.com_source_record
  if ([string]::IsNullOrWhiteSpace($linkSourceId) -or ($siblingCsrIds -notcontains $linkSourceId -and $knownPriorSourceIds -notcontains $linkSourceId)) {
    Add-Issue $issues "$linkSubject must bind a known sibling Source Record, found: $linkSourceId."
  }
  if ($evidenceRoles -notcontains $link.com_evidence_role) {
    Add-Issue $issues "$linkSubject evidence role is not in manifest vocabulary: $($link.com_evidence_role)."
  }
}
# Every receipt must be bound to at least one source link (no free-floating explanation receipts)
foreach ($receiptId in @($sliceReceiptIdSet.Keys)) {
  if (@($links | Where-Object { $_.com_receipt -eq $receiptId }).Count -lt 1) {
    Add-Issue $issues "Receipt $receiptId must be bound to its source provenance by at least one receiptSourceLinks entry."
  }
}

# Live writes deferred — every referenced Work Item needs a deferred gate entry
$deferred = @($run.liveWritesDeferred | Where-Object { $null -ne $_ })
if ($deferred.Count -lt 1) {
  Add-Issue $issues "liveWritesDeferred must include at least one entry per referenced Work Item, found $($deferred.Count)."
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
foreach ($itemId in @($sliceReferencedWorkItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)) {
  if ($deferredTargets -notcontains $itemId) {
    Add-Issue $issues "Missing liveWritesDeferred entry for referenced Work Item $itemId."
  }
}

# This slice must not mint new CSR-*/CWI-* identities that collide with (or silently replace) sibling harvest.
# Story 4.2 only references existing sibling Work Items and Source Records; it must not mint new CWI-*/CSR-* ids.
$sliceCsrIds = @(
  @(
    Get-IdsFromSliceText -RawText $rawSliceText -Pattern '"com_council_source_record_id"\s*:\s*"(CSR-[^"]+)"'
    Get-IdsFromSliceText -RawText $rawSliceText -Pattern '"(CSR-[A-Za-z0-9-]+)"'
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
)
foreach ($csrId in $sliceCsrIds) {
  if ($siblingCsrIds -notcontains $csrId) {
    Add-Issue $issues "Slice CSR id $csrId is not present in sibling slices 1-1..1-5 harvest; Story 4.2 must reference existing source records, not mint new CSR identities."
  }
}
$sliceCwiIdRefs = @(
  @(
    Get-IdsFromSliceText -RawText $rawSliceText -Pattern '"workItem"\s*:\s*"(CWI-[^"]+)"'
    Get-IdsFromSliceText -RawText $rawSliceText -Pattern '"com_work_item"\s*:\s*"(CWI-[^"]+)"'
    Get-IdsFromSliceText -RawText $rawSliceText -Pattern '\b(CWI-LOCAL-[A-Za-z0-9-]+)\b'
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
)
foreach ($cwiId in $sliceCwiIdRefs) {
  if ($siblingCwiIds -notcontains $cwiId -and $knownPriorWorkItemIds -notcontains $cwiId) {
    Add-Issue $issues "Slice CWI id $cwiId is not present in sibling slices 1-1..1-5/demo harvest; Story 4.2 must reference existing Work Items, not mint new CWI identities."
  }
}

# Acceptance mapping for every AC the story declares (two "Slice must prove" items => AC 1 and 2).
$requiredAcceptanceCriteria = @(1, 2)
$declaredCriteria = @(
  @($slice.acceptanceMapping) |
    Where-Object { $null -ne $_ -and $null -ne $_.acceptanceCriterion } |
    ForEach-Object { [int]$_.acceptanceCriterion } |
    Sort-Object -Unique
)
$maxDeclared = 0
if ($declaredCriteria.Count -gt 0) {
  $maxDeclared = ($declaredCriteria | Measure-Object -Maximum).Maximum
}
if ($maxDeclared -gt $requiredAcceptanceCriteria.Count) {
  $requiredAcceptanceCriteria = 1..$maxDeclared
}
foreach ($criterion in $requiredAcceptanceCriteria) {
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
# AC2 must speak to uncertainty visible + no auto-approval + unchanged state (the FR19/FR20 core).
$ac2 = @($slice.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq 2 } | Select-Object -First 1
if ($ac2) {
  $ac2EvidenceText = (@($ac2.localEvidence) -join " ")
  if ($ac2EvidenceText -notmatch "(?i)uncertainty" -or $ac2EvidenceText -notmatch "(?i)visible") {
    Add-Issue $issues "Acceptance mapping for AC 2 must evidence that uncertainty is made visible."
  }
  if ($ac2EvidenceText -notmatch "(?i)auto-approv" -and $ac2EvidenceText -notmatch "(?i)noAutoApprovalFromGraph") {
    Add-Issue $issues "Acceptance mapping for AC 2 must evidence that the Work Item was not auto-approved from graph evidence."
  }
  if ($ac2EvidenceText -notmatch "(?i)unchanged" -and $ac2EvidenceText -notmatch "(?i)state group") {
    Add-Issue $issues "Acceptance mapping for AC 2 must evidence that the Work Item state group is unchanged."
  }
}

# Tripwires: raw slice text must carry the machine-checkable markers the story pins.
if ($rawSliceText -notmatch '"noAutoApprovalFromGraph"\s*:\s*true') {
  Add-Issue $issues "Slice must declare noAutoApprovalFromGraph true so non-auto-approval is machine-checkable."
}
if ($rawSliceText -notmatch '"uncertaintyVisible"\s*:\s*true') {
  Add-Issue $issues "Slice must declare uncertaintyVisible true for the conflict scenario so visible uncertainty is machine-checkable."
}
if ($rawSliceText -notmatch '"evidenceKind"') {
  Add-Issue $issues "Slice must carry evidenceKind on every element so the evidence/inference distinction is machine-checkable."
}

if ($issues.Count -gt 0) {
  Write-Host "Graph provenance explanation slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Graph provenance explanation slice validation succeeded."
Write-Host "Explanations: $($explanations.Count)"
Write-Host "Receipts: $($sliceReceipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "Deferred live writes: $($deferred.Count)"
Write-Host "GRAPH_PROVENANCE_EXPLANATION_SLICE_VALIDATE_OK"
