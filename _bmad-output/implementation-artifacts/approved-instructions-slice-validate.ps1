param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$ApprovedSlicePath = "$PSScriptRoot\approved-instructions-slice.json",
  [string]$ManualSlicePath = "$PSScriptRoot\manual-source-record-slice.json",
  [string]$OutlookSlicePath = "$PSScriptRoot\outlook-source-reference-slice.json",
  [string]$Story14ExtractionPath = "$PSScriptRoot\zero-multi-item-extraction-slice.json",
  [string]$Story13ExtractionPath = "$PSScriptRoot\proposed-work-item-extraction-slice.json",
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

function Invoke-CollectSiblingIds {
  # Recursively walk a parsed sibling slice JSON and harvest every canonical
  # Council id / idempotency key by property name, plus the demo-evidence
  # workItemIds/receiptIds arrays. This is the single source of truth for
  # cross-slice collision checks so they cover ALL co-located slices, not just
  # the named siblings (Story 4.4 hard rule: ids unique across ALL slices).
  param(
    [Parameter(Mandatory = $false)][AllowNull()]$Node,
    [Parameter(Mandatory = $true)][hashtable]$WorkItems,
    [Parameter(Mandatory = $true)][hashtable]$Receipts,
    [Parameter(Mandatory = $true)][hashtable]$Keys,
    [Parameter(Mandatory = $true)][hashtable]$SourceRecords,
    [Parameter(Mandatory = $true)][hashtable]$Instructions,
    [Parameter(Mandatory = $true)][hashtable]$MemoryCandidates
  )

  if ($null -eq $Node) { return }
  if ($Node -is [System.Collections.IList]) {
    foreach ($item in $Node) {
      Invoke-CollectSiblingIds -Node $item -WorkItems $WorkItems -Receipts $Receipts -Keys $Keys -SourceRecords $SourceRecords -Instructions $Instructions -MemoryCandidates $MemoryCandidates
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
        "com_council_approved_instruction_id" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $Instructions[$id] = $true }
          break
        }
        "com_council_memory_candidate_id" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $MemoryCandidates[$id] = $true }
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
          Invoke-CollectSiblingIds -Node $prop.Value -WorkItems $WorkItems -Receipts $Receipts -Keys $Keys -SourceRecords $SourceRecords -Instructions $Instructions -MemoryCandidates $MemoryCandidates
        }
      }
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
    Write-Host "Approved instructions slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

foreach ($path in @($ManifestPath, $ApprovedSlicePath, $ManualSlicePath, $OutlookSlicePath, $Story14ExtractionPath, $Story13ExtractionPath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required approved instructions validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$slice = Read-JsonInput -Path $ApprovedSlicePath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$rawSliceText = Get-Content -LiteralPath $ApprovedSlicePath -Raw
$issues = [System.Collections.Generic.List[string]]::new()

$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$recordStatuses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_recordstatus"
$evidenceRoles = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilreceiptsource" -ColumnName "com_evidence_role"

# Approved Instruction scope is a column-level choice (values inline, not a named choice).
$instructionTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilapprovedinstruction" } | Select-Object -First 1
$scopeColumn = @($instructionTable.columns) | Where-Object { $_.name -eq "com_scope" } | Select-Object -First 1
$scopeValues = @($scopeColumn.values | Where-Object { $null -ne $_ })

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_recordstatus"; Values = $recordStatuses },
    @{ Name = "com_councilreceiptsource.com_evidence_role"; Values = $evidenceRoles },
    @{ Name = "com_councilapprovedinstruction.com_scope"; Values = $scopeValues }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

foreach ($requiredVerb in @("approved", "memory_promoted")) {
  if ($receiptVerbs -notcontains $requiredVerb) {
    Add-Issue $issues "Manifest com_receiptverb is missing a verb required by Story 4.4: $requiredVerb."
  }
}
foreach ($requiredResult in @("accepted", "superseded")) {
  if ($receiptResults -notcontains $requiredResult) {
    Add-Issue $issues "Manifest com_receiptresult is missing a result required by Story 4.4: $requiredResult."
  }
}
foreach ($requiredActor in @("human")) {
  if ($actorTypes -notcontains $requiredActor) {
    Add-Issue $issues "Manifest com_actortype is missing an actor type required by Story 4.4: $requiredActor."
  }
}
foreach ($requiredStatus in @("active", "superseded")) {
  if ($recordStatuses -notcontains $requiredStatus) {
    Add-Issue $issues "Manifest com_recordstatus is missing a status required by Story 4.4: $requiredStatus."
  }
}
foreach ($requiredRole in @("approval", "supporting")) {
  if ($evidenceRoles -notcontains $requiredRole) {
    Add-Issue $issues "Manifest com_councilreceiptsource.com_evidence_role is missing a role required by Story 4.4: $requiredRole."
  }
}
foreach ($requiredScope in @("project", "personal", "tenant", "workflow", "skill")) {
  if ($scopeValues -notcontains $requiredScope) {
    Add-Issue $issues "Manifest com_councilapprovedinstruction.com_scope is missing a scope value required by Story 4.4: $requiredScope."
  }
}

if ($slice.storyKey -ne "4-4-promote-approved-instructions-with-receipts") {
  Add-Issue $issues "Slice storyKey must be 4-4-promote-approved-instructions-with-receipts."
}
if ([string]$slice.status -notmatch "^local-contract") {
  Add-Issue $issues "Slice status must declare local contract evidence, found: $($slice.status)."
}

foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "requiresExplicitHumanApprovalForExecution", "sourceRecordsRemainSeparate", "meaningGraphDoesNotOwnWorkflowState", "dataverseRowsNotUsedAsCouncilIdentity", "receiptsAreLocalContractEvidenceOnly", "receiptsAreAppendOnlyCorrectionsAreNewReceipts", "priorInstructionUnchanged", "supersessionNeverOverwritesPriorReceiptOrText", "promotionRequiresExplicitApprovalReceipt", "noWorkItemStateChangeInThisSlice")) {
  if (-not ($slice.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($slice.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Slice guard must be boolean true: $($guardProperty.Name)."
  }
}

# Cross-slice prior source IDs (for com_source_record / com_primary_source_record resolution).
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
  elseif ((ConvertTo-Json $record -Depth 10 -Compress) -ne (ConvertTo-Json $priorSourcesById[$recordId] -Depth 10 -Compress)) {
    Add-Issue $issues "Divergent duplicate prior Source Record across sibling slices: $recordId; cross-slice checks would silently run against an arbitrary copy."
  }
}
$knownPriorSourceIds = @($priorSourcesById.Keys)

# Named sibling structural loads (for deep per-slice tripwires + runId collision).
$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })

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

# Generic cross-slice id harvest: walk EVERY sibling slice JSON in this folder so
# collision checks cover ALL co-located slices (Story 4.4 hard rule: ids unique
# across ALL slices). Hashtables make membership tests O(1) and immune to
# duplicate-fold bugs. The slice's own file is excluded so its ids are checked
# only for intra-slice uniqueness below, not false-flagged as collisions.
$siblingWorkItemIds = @{}
$siblingReceiptIds = @{}
$siblingIdempotencyKeys = @{}
$siblingSourceRecordIds = @{}
$siblingInstructionIds = @{}
$siblingMemoryCandidateIds = @{}
$siblingSliceFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.json" |
  Where-Object { $_.Name -ne "dataverse-mvp-schema-manifest.json" -and $_.Name -ne "approved-instructions-slice.json" } |
  ForEach-Object { $_.FullName })
if ($siblingSliceFiles.Count -eq 0) {
  Add-Issue $issues "No sibling slice JSON files found in $PSScriptRoot; cross-slice id-collision checks would silently no-op."
}
foreach ($siblingFile in $siblingSliceFiles) {
  $siblingJson = Read-JsonInput -Path $siblingFile
  Invoke-CollectSiblingIds -Node $siblingJson -WorkItems $siblingWorkItemIds -Receipts $siblingReceiptIds -Keys $siblingIdempotencyKeys -SourceRecords $siblingSourceRecordIds -Instructions $siblingInstructionIds -MemoryCandidates $siblingMemoryCandidateIds
}

# Fold sibling source-record ids into the prior-source set used for resolution.
foreach ($sid in @($siblingSourceRecordIds.Keys)) {
  if ($knownPriorSourceIds -notcontains $sid) { $knownPriorSourceIds += $sid }
}

if ($knownPriorSourceIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be harvested from sibling slices; com_source_record checks would silently no-op."
}
if ($siblingReceiptIds.Count -eq 0) {
  Add-Issue $issues "No Receipt IDs could be harvested from sibling slices; receipt collision checks would silently no-op."
}
if ($siblingIdempotencyKeys.Count -eq 0) {
  Add-Issue $issues "No idempotency keys could be harvested from sibling slices; key collision checks would silently no-op."
}

# Story 4-3 coordination: cross-check 4-3 memory-candidate ids ONLY when a matching
# slice file is present (parallel development). Do not hard-fail when absent; the
# slice embeds a self-contained candidate and records story43SlicePresent=false.
$story43SliceFile = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*memory-candidate*.json" | ForEach-Object { $_.FullName })
$story43SlicePresent = $story43SliceFile.Count -gt 0

$run = $slice.promotionRun
if ($null -eq $run) {
  Add-Issue $issues "Slice must carry a promotionRun block."
  Write-Host "Approved instructions slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Promotion run must declare a runId."
}
elseif (@([string]$story13Extraction.extractionRun.runId, [string]$story14Extraction.extractionRun.runId) -contains [string]$run.runId) {
  Add-Issue $issues "Promotion run must use a new local runId, not a sibling slice runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Promotion run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Promotion run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Promotion run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "zero-multi-item-extraction-slice.json")) {
  if (@($run.inputSlicesFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Promotion run must reference $inputSlice as an input."
  }
}

# Source-candidate coordination block must agree with the actual filesystem state.
$coordination = $run.sourceCandidateCoordination
if ($null -eq $coordination) {
  Add-Issue $issues "Promotion run must declare a sourceCandidateCoordination block."
}
else {
  if ($coordination.story43SlicePresent -isnot [bool]) {
    Add-Issue $issues "sourceCandidateCoordination.story43SlicePresent must be a strict boolean."
  }
  elseif ($coordination.story43SlicePresent -ne $story43SlicePresent) {
    Add-Issue $issues "sourceCandidateCoordination.story43SlicePresent ($($coordination.story43SlicePresent)) must match the actual filesystem presence of a Story 4-3 memory-candidate slice ($story43SlicePresent)."
  }
  if (-not (Test-HasNonEmptyField -Record $coordination -Field "note")) {
    Add-Issue $issues "sourceCandidateCoordination must carry a non-empty note."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Promotion run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("promotionRequiresExplicitHumanApprovalReceipt", "supersessionIsRecordedByANewReceiptNeverByEditingPriorReceipt", "supersededInstructionTextAndOriginalReceiptStayUnchanged", "replacementInstructionIsApprovedViaItsOwnNewReceipt", "liveInstructionMutationReceiptGatedToEpic2", "receiptsAreAppendOnlyCorrectionsAreNewReceipts")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Promotion run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Promotion run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# Embedded memory candidate (source candidate ref for the Approved Instruction).
$embeddedCandidate = $run.embeddedMemoryCandidate
$embeddedCandidateId = ""
if ($null -eq $embeddedCandidate) {
  Add-Issue $issues "Promotion run must embed a memory candidate (embeddedMemoryCandidate) as the source candidate ref."
}
else {
  $candidateTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilmemorycandidate" } | Select-Object -First 1
  $candidateRequiredFields = @(@($candidateTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($candidateRequiredFields.Count -eq 0) {
    Add-Issue $issues "No required memory-candidate columns could be derived from manifest com_councilmemorycandidate; candidate required-field checks would silently no-op."
  }
  $embeddedSubject = "Embedded memory candidate"
  foreach ($field in $candidateRequiredFields) {
    if (-not (Test-HasNonEmptyField -Record $embeddedCandidate -Field $field)) {
      Add-Issue $issues "$embeddedSubject missing required manifest memory-candidate field: $field."
    }
  }
  $embeddedCandidateId = [string]$embeddedCandidate.com_council_memory_candidate_id
  if ([string]::IsNullOrWhiteSpace($embeddedCandidateId)) {
    Add-Issue $issues "$embeddedSubject must declare com_council_memory_candidate_id."
  }
  else {
    if ($embeddedCandidateId -notmatch "^CMC-LOCAL-") {
      Add-Issue $issues "$embeddedSubject must use fresh CMC-LOCAL-* identity, found: $embeddedCandidateId."
    }
    if ($siblingMemoryCandidateIds.ContainsKey($embeddedCandidateId)) {
      Add-Issue $issues "$embeddedSubject id collides with a memory candidate id from a sibling slice: $embeddedCandidateId."
    }
  }
  # com_scope for the memory candidate is a column-level choice with the same vocabulary shape.
  $candidateScopeColumn = @($candidateTable.columns) | Where-Object { $_.name -eq "com_scope" } | Select-Object -First 1
  $candidateScopeValues = @($candidateScopeColumn.values | Where-Object { $null -ne $_ })
  if ($candidateScopeValues.Count -eq 0) {
    Add-Issue $issues "Manifest com_councilmemorycandidate.com_scope vocabulary missing or empty; candidate scope checks would silently no-op."
  }
  elseif ($candidateScopeValues -notcontains [string]$embeddedCandidate.com_scope) {
    Add-Issue $issues "$embeddedSubject com_scope is not in manifest vocabulary, found: $($embeddedCandidate.com_scope)."
  }
  $candidateReviewStates = @(@($candidateTable.columns) | Where-Object { $_.name -eq "com_review_state" } | Select-Object -First 1 | ForEach-Object { @($_.values | Where-Object { $null -ne $_ }) })
  if ($candidateReviewStates.Count -gt 0 -and $candidateReviewStates -notcontains [string]$embeddedCandidate.com_review_state) {
    Add-Issue $issues "$embeddedSubject com_review_state is not in manifest vocabulary, found: $($embeddedCandidate.com_review_state)."
  }
  if (-not (Test-HasNonEmptyField -Record $embeddedCandidate -Field "com_source_record")) {
    Add-Issue $issues "$embeddedSubject must reference a source record (com_source_record)."
  }
  elseif ($knownPriorSourceIds -notcontains [string]$embeddedCandidate.com_source_record) {
    Add-Issue $issues "$embeddedSubject com_source_record must reference a known Source Record from a sibling slice, found: $($embeddedCandidate.com_source_record)."
  }
  Test-ConfidenceInRange -Issues $issues -Record $embeddedCandidate -Field "com_confidence" -Subject $embeddedSubject
  if ($embeddedCandidate.evidenceStatus -ne "mock_manual_not_tenant_verified") {
    Add-Issue $issues "$embeddedSubject must be marked mock_manual_not_tenant_verified evidence, found: $($embeddedCandidate.evidenceStatus)."
  }
}

# Approved Instructions
$instructionRequiredFields = @(@($instructionTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($instructionRequiredFields.Count -eq 0) {
  Add-Issue $issues "No required Approved Instruction columns could be derived from manifest com_councilapprovedinstruction; instruction required-field checks would silently no-op."
}
$instructions = @($run.approvedInstructions | Where-Object { $null -ne $_ })
if ($instructions.Count -lt 2) {
  Add-Issue $issues "Promotion run must include at least two Approved Instructions (one promotion, one replacement), found $($instructions.Count)."
}
$sliceInstructionIds = @{}
$instructionById = @{}
foreach ($instruction in $instructions) {
  $instructionId = [string]$instruction.com_council_approved_instruction_id
  $subject = "Approved Instruction $instructionId"
  foreach ($field in $instructionRequiredFields) {
    if (-not (Test-HasNonEmptyField -Record $instruction -Field $field)) {
      Add-Issue $issues "$subject missing required manifest Approved Instruction field: $field."
    }
  }
  if ([string]::IsNullOrWhiteSpace($instructionId)) {
    Add-Issue $issues "Approved Instruction must declare com_council_approved_instruction_id."
  }
  else {
    if ($instructionId -notmatch "^CAI-LOCAL-") {
      Add-Issue $issues "$subject must use fresh CAI-LOCAL-* identity, found: $instructionId."
    }
    if ($sliceInstructionIds.ContainsKey($instructionId)) {
      Add-Issue $issues "Duplicate Approved Instruction id in slice: $instructionId."
    }
    else {
      $sliceInstructionIds[$instructionId] = $instruction
    }
    if ($siblingInstructionIds.ContainsKey($instructionId)) {
      Add-Issue $issues "$subject collides with an Approved Instruction id from a sibling slice: $instructionId."
    }
  }
  $instructionById[$instructionId] = $instruction

  if ($scopeValues -notcontains [string]$instruction.com_scope) {
    Add-Issue $issues "$subject com_scope is not in manifest com_councilapprovedinstruction.com_scope vocabulary, found: $($instruction.com_scope)."
  }
  if ($recordStatuses -notcontains [string]$instruction.com_status) {
    Add-Issue $issues "$subject com_status is not in manifest com_recordstatus vocabulary, found: $($instruction.com_status)."
  }
  $effectiveFrom = Test-IsoTimestamp -Issues $issues -Record $instruction -Field "com_effective_from" -Subject $subject
  if ($null -eq $effectiveFrom) {
    # Test-IsoTimestamp already recorded the specific failure.
  }
  # Source candidate ref must resolve to the embedded candidate (or a 4-3 candidate when present).
  if (Test-HasNonEmptyField -Record $instruction -Field "com_source_memory_candidate") {
    $candidateRef = [string]$instruction.com_source_memory_candidate
    if (-not [string]::IsNullOrWhiteSpace($embeddedCandidateId) -and $candidateRef -ne $embeddedCandidateId -and -not $story43SlicePresent) {
      Add-Issue $issues "$subject com_source_memory_candidate must reference the embedded candidate $embeddedCandidateId when no 4-3 slice is present, found: $candidateRef."
    }
  }
  # Approval receipt must be a real receipt in this slice.
  if (Test-HasNonEmptyField -Record $instruction -Field "com_approval_receipt") {
    $approvalReceiptRef = [string]$instruction.com_approval_receipt
    # Resolved later once $sliceReceiptIds is built; record the ref for cross-check.
  }
  # priorInstructionUnchanged guard must be strict boolean true on every instruction.
  if ($instruction.PSObject.Properties.Name -contains "priorInstructionUnchanged") {
    if ($instruction.priorInstructionUnchanged -isnot [bool] -or -not $instruction.priorInstructionUnchanged) {
      Add-Issue $issues "$subject priorInstructionUnchanged must be strict boolean true."
    }
  }
  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($instruction.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 4.4 instructions are local contract evidence only."
    }
  }
}

# Receipts
$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
# Manifest-required columns, plus the Council receipt contract fields this story additionally pins.
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique

$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 3) {
  Add-Issue $issues "Promotion run must include at least three receipts (two approvals, one supersession), found $($receipts.Count)."
}
$sliceReceiptIds = @{}
$receiptById = @{}
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
    if ($receiptId -notmatch "^CR-LOCAL-INSTR-") {
      Add-Issue $issues "$subject must use Council-level CR-LOCAL-INSTR-* identity."
    }
    if ($sliceReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "Duplicate receipt ID in slice: $receiptId."
    }
    else {
      $sliceReceiptIds[$receiptId] = $receipt
    }
    if ($siblingReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "$subject collides with a receipt ID from a sibling slice."
    }
  }
  $receiptById[$receiptId] = $receipt

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
      Add-Issue $issues "$subject reuses an idempotency key already used by another receipt in this slice: $idempotencyKey. Receipt idempotency keys are alternate keys and must be unique (append-only)."
    }
    else {
      $seenIdempotencyKeys[$idempotencyKey] = $true
    }
    if ($siblingIdempotencyKeys.ContainsKey($idempotencyKey)) {
      Add-Issue $issues "$subject idempotency key collides with a sibling slice receipt idempotency key: $idempotencyKey."
    }
  }

  if ($receipt.com_append_only_locked -isnot [bool] -or -not $receipt.com_append_only_locked) {
    Add-Issue $issues "$subject com_append_only_locked must be strict boolean true (receipts are append-only)."
  }
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 4.4 receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 4.4 receipts are local contract evidence only."
      }
    }
  }
}

foreach ($expectedReceiptId in @("CR-LOCAL-INSTR-APPROVE-001", "CR-LOCAL-INSTR-APPROVE-002", "CR-LOCAL-INSTR-SUPERSEDE-001")) {
  if (-not $sliceReceiptIds.ContainsKey($expectedReceiptId)) {
    Add-Issue $issues "Slice must include receipt $expectedReceiptId."
  }
}

# Approval receipts: verb=approved, actor=human, actor_id=Doug, result=accepted.
foreach ($approvalId in @("CR-LOCAL-INSTR-APPROVE-001", "CR-LOCAL-INSTR-APPROVE-002")) {
  $approval = $receiptById[$approvalId]
  if ($null -eq $approval) { continue }
  $subject = "Receipt $approvalId"
  if ([string]$approval.com_verb -ne "approved") {
    Add-Issue $issues "$subject verb must be approved for an approval receipt, found: $($approval.com_verb)."
  }
  if ([string]$approval.com_actor_type -ne "human") {
    Add-Issue $issues "$subject actor type must be human for an approval receipt, found: $($approval.com_actor_type)."
  }
  if ([string]$approval.com_actor_id -ne "Doug") {
    Add-Issue $issues "$subject actor id must be Doug (human approver) for an approval receipt, found: $($approval.com_actor_id)."
  }
  if ([string]$approval.com_result -ne "accepted") {
    Add-Issue $issues "$subject result must be accepted for an approval receipt, found: $($approval.com_result)."
  }
  if (-not (Test-HasNonEmptyField -Record $approval -Field "com_authority_basis")) {
    Add-Issue $issues "$subject must carry a non-empty com_authority_basis (approval authority basis)."
  }
  if (-not (Test-HasNonEmptyField -Record $approval -Field "com_decision_rationale")) {
    Add-Issue $issues "$subject must carry a non-empty com_decision_rationale (approval rationale)."
  }
  if (-not (Test-HasNonEmptyField -Record $approval -Field "com_evidence_refs")) {
    Add-Issue $issues "$subject must carry non-empty com_evidence_refs (source evidence)."
  }
}

# Supersession receipt: distinct from the approval receipts; before active, after superseded.
$supersedeReceipt = $receiptById["CR-LOCAL-INSTR-SUPERSEDE-001"]
if ($null -eq $supersedeReceipt) {
  Add-Issue $issues "Slice must include supersession receipt CR-LOCAL-INSTR-SUPERSEDE-001."
}
else {
  $subject = "Receipt CR-LOCAL-INSTR-SUPERSEDE-001"
  if ([string]$supersedeReceipt.com_verb -ne "memory_promoted") {
    Add-Issue $issues "$subject verb must be memory_promoted (promotion that supersedes the prior instruction), found: $($supersedeReceipt.com_verb)."
  }
  if ([string]$supersedeReceipt.com_result -ne "superseded") {
    Add-Issue $issues "$subject result must be superseded, found: $($supersedeReceipt.com_result)."
  }
  if ([string]$supersedeReceipt.com_before_state -ne "active") {
    Add-Issue $issues "$subject com_before_state must be active, found: $($supersedeReceipt.com_before_state)."
  }
  if ([string]$supersedeReceipt.com_after_state -ne "superseded") {
    Add-Issue $issues "$subject com_after_state must be superseded, found: $($supersedeReceipt.com_after_state)."
  }
  if ([string]$supersedeReceipt.com_actor_type -ne "human") {
    Add-Issue $issues "$subject actor type must be human, found: $($supersedeReceipt.com_actor_type)."
  }
  if ([string]$supersedeReceipt.com_actor_id -ne "Doug") {
    Add-Issue $issues "$subject actor id must be Doug, found: $($supersedeReceipt.com_actor_id)."
  }
}

# Bind each Approved Instruction's com_approval_receipt to a real slice receipt.
foreach ($instruction in $instructions) {
  $instructionId = [string]$instruction.com_council_approved_instruction_id
  $subject = "Approved Instruction $instructionId"
  if (Test-HasNonEmptyField -Record $instruction -Field "com_approval_receipt") {
    $approvalRef = [string]$instruction.com_approval_receipt
    if (-not $sliceReceiptIds.ContainsKey($approvalRef)) {
      Add-Issue $issues "$subject com_approval_receipt must reference a receipt that exists in this slice, found: $approvalRef."
    }
    else {
      $boundReceipt = $sliceReceiptIds[$approvalRef]
      if ([string]$boundReceipt.com_verb -ne "approved") {
        Add-Issue $issues "$subject com_approval_receipt must reference an approval receipt (verb approved), found verb: $($boundReceipt.com_verb)."
      }
      if ([string]$boundReceipt.com_actor_type -ne "human") {
        Add-Issue $issues "$subject com_approval_receipt must reference a human-actor receipt, found actor type: $($boundReceipt.com_actor_type)."
      }
    }
  }
  # originalApprovalReceipt must equal com_approval_receipt and resolve.
  if (Test-HasNonEmptyField -Record $instruction -Field "originalApprovalReceipt") {
    $origRef = [string]$instruction.originalApprovalReceipt
    if ($origRef -ne [string]$instruction.com_approval_receipt) {
      Add-Issue $issues "$subject originalApprovalReceipt must equal com_approval_receipt, found: $origRef vs $($instruction.com_approval_receipt)."
    }
    elseif (-not $sliceReceiptIds.ContainsKey($origRef)) {
      Add-Issue $issues "$subject originalApprovalReceipt must reference a receipt that exists in this slice, found: $origRef."
    }
  }
  # com_superseded_by (when present and non-null) must resolve to a slice instruction.
  if ($instruction.PSObject.Properties.Name -contains "com_superseded_by" -and $null -ne $instruction.com_superseded_by) {
    $supersededBy = [string]$instruction.com_superseded_by
    if (-not [string]::IsNullOrWhiteSpace($supersededBy)) {
      if (-not $sliceInstructionIds.ContainsKey($supersededBy)) {
        Add-Issue $issues "$subject com_superseded_by must reference an Approved Instruction that exists in this slice, found: $supersededBy."
      }
      elseif ($supersededBy -eq $instructionId) {
        Add-Issue $issues "$subject com_superseded_by must not reference itself: $supersededBy."
      }
    }
  }
}

# Supersessions: chain integrity + prior-unchanged guard.
$supersessions = @($run.supersessions | Where-Object { $null -ne $_ })
if ($supersessions.Count -lt 1) {
  Add-Issue $issues "Promotion run must include at least one supersession."
}
$seenSupersededIds = @{}
foreach ($supersession in $supersessions) {
  $supersededId = [string]$supersession.supersededInstruction
  $supersedingId = [string]$supersession.supersedingInstruction
  $subject = "Supersession of $supersededId"
  if ([string]::IsNullOrWhiteSpace($supersededId)) {
    Add-Issue $issues "Supersession must name its supersededInstruction."
  }
  else {
    if ($seenSupersededIds.ContainsKey($supersededId)) {
      Add-Issue $issues "Duplicate supersession for Approved Instruction: $supersededId."
    }
    else {
      $seenSupersededIds[$supersededId] = $true
    }
    if (-not $sliceInstructionIds.ContainsKey($supersededId)) {
      Add-Issue $issues "$subject references an unknown Approved Instruction: $supersededId."
    }
  }
  if ([string]::IsNullOrWhiteSpace($supersedingId)) {
    Add-Issue $issues "$subject must name its supersedingInstruction."
  }
  elseif (-not $sliceInstructionIds.ContainsKey($supersedingId)) {
    Add-Issue $issues "$subject references an unknown superseding Approved Instruction: $supersedingId."
  }

  # Old instruction must be marked superseded.
  if ($sliceInstructionIds.ContainsKey($supersededId)) {
    $oldInstruction = $sliceInstructionIds[$supersededId]
    if ([string]$oldInstruction.com_status -ne "superseded") {
      Add-Issue $issues "$subject old instruction com_status must be superseded, found: $($oldInstruction.com_status)."
    }
    if ([string]$oldInstruction.com_superseded_by -ne $supersedingId) {
      Add-Issue $issues "$subject old instruction com_superseded_by must link to the superseding instruction $supersedingId, found: $($oldInstruction.com_superseded_by)."
    }
  }
  # New (replacement) instruction must be active.
  if ($sliceInstructionIds.ContainsKey($supersedingId)) {
    $newInstruction = $sliceInstructionIds[$supersedingId]
    if ([string]$newInstruction.com_status -ne "active") {
      Add-Issue $issues "$subject replacement instruction com_status must be active, found: $($newInstruction.com_status)."
    }
    # Replacement instruction must not itself be superseded in this slice.
    if ($newInstruction.PSObject.Properties.Name -contains "com_superseded_by" -and $null -ne $newInstruction.com_superseded_by) {
      Add-Issue $issues "$subject replacement instruction must not carry a com_superseded_by link (it is the active replacement), found: $($newInstruction.com_superseded_by)."
    }
  }

  # Supersession receipt must resolve and be distinct from both approval receipts.
  $supersessionReceiptId = [string]$supersession.supersessionReceipt
  if ([string]::IsNullOrWhiteSpace($supersessionReceiptId) -or -not $sliceReceiptIds.ContainsKey($supersessionReceiptId)) {
    Add-Issue $issues "$subject supersessionReceipt must reference a receipt that exists in this slice, found: $supersessionReceiptId."
  }
  else {
    if ($supersessionReceiptId -eq "CR-LOCAL-INSTR-APPROVE-001" -or $supersessionReceiptId -eq "CR-LOCAL-INSTR-APPROVE-002") {
      Add-Issue $issues "$subject supersessionReceipt must be a NEW receipt distinct from the approval receipts, found: $supersessionReceiptId."
    }
    $sReceipt = $sliceReceiptIds[$supersessionReceiptId]
    if ([string]$sReceipt.com_result -ne "superseded") {
      Add-Issue $issues "$subject supersessionReceipt result must be superseded, found: $($sReceipt.com_result)."
    }
  }
  # Replacement approval receipt must resolve and be distinct from the original approval receipt.
  $replacementApprovalId = [string]$supersession.replacementApprovalReceipt
  if (Test-HasNonEmptyField -Record $supersession -Field "replacementApprovalReceipt") {
    if (-not $sliceReceiptIds.ContainsKey($replacementApprovalId)) {
      Add-Issue $issues "$subject replacementApprovalReceipt must reference a receipt that exists in this slice, found: $replacementApprovalId."
    }
    elseif ($replacementApprovalId -eq "CR-LOCAL-INSTR-APPROVE-001") {
      Add-Issue $issues "$subject replacementApprovalReceipt must be a NEW receipt distinct from the original approval receipt CR-LOCAL-INSTR-APPROVE-001."
    }
  }

  # priorInstructionUnchanged guard on the supersession entry.
  if ($supersession.PSObject.Properties.Name -contains "priorInstructionUnchanged") {
    if ($supersession.priorInstructionUnchanged -isnot [bool] -or -not $supersession.priorInstructionUnchanged) {
      Add-Issue $issues "$subject priorInstructionUnchanged must be strict boolean true."
    }
  }
  else {
    Add-Issue $issues "$subject must declare priorInstructionUnchanged."
  }

  if (-not (Test-HasNonEmptyField -Record $supersession -Field "supersessionRationale")) {
    Add-Issue $issues "$subject must carry a non-empty supersessionRationale."
  }

  # priorInstructionSnapshot must prove the prior text/receipt are untouched:
  # the snapshot's instruction text and approval receipt must match the actual
  # old instruction's com_instruction_text and com_approval_receipt (content delta
  # proven, not self-asserted).
  $snapshot = $supersession.priorInstructionSnapshot
  if ($null -eq $snapshot) {
    Add-Issue $issues "$subject must embed a priorInstructionSnapshot proving the prior text/receipt are unchanged."
  }
  elseif ($sliceInstructionIds.ContainsKey($supersededId)) {
    $oldInstruction = $sliceInstructionIds[$supersededId]
    if ([string]$snapshot.com_council_approved_instruction_id -ne $supersededId) {
      Add-Issue $issues "$subject priorInstructionSnapshot must reference the superseded instruction $supersededId, found: $($snapshot.com_council_approved_instruction_id)."
    }
    if ([string]$snapshot.com_instruction_text -ne [string]$oldInstruction.com_instruction_text) {
      Add-Issue $issues "$subject priorInstructionSnapshot com_instruction_text must match the superseded instruction's actual text; the prior text must be unchanged."
    }
    if ([string]$snapshot.com_approval_receipt -ne [string]$oldInstruction.com_approval_receipt) {
      Add-Issue $issues "$subject priorInstructionSnapshot com_approval_receipt must match the superseded instruction's actual approval receipt; the prior receipt must be unchanged."
    }
    if ([string]$snapshot.com_status -ne "superseded") {
      Add-Issue $issues "$subject priorInstructionSnapshot com_status must be superseded, found: $($snapshot.com_status)."
    }
    if ([string]$snapshot.com_superseded_by -ne $supersedingId) {
      Add-Issue $issues "$subject priorInstructionSnapshot com_superseded_by must link to $supersedingId, found: $($snapshot.com_superseded_by)."
    }
    # The snapshot's effective_from must equal the old instruction's effective_from (unchanged).
    if ([string]$snapshot.com_effective_from -ne [string]$oldInstruction.com_effective_from) {
      Add-Issue $issues "$subject priorInstructionSnapshot com_effective_from must match the superseded instruction's actual effective_from; the prior effective date must be unchanged."
    }
  }
}

# Exactly one supersession expected for this story (CAI-LOCAL-001 -> CAI-LOCAL-002).
if (-not $seenSupersededIds.ContainsKey("CAI-LOCAL-001")) {
  Add-Issue $issues "Slice must record a supersession of the original instruction CAI-LOCAL-001."
}
if (-not $sliceInstructionIds.ContainsKey("CAI-LOCAL-001")) {
  Add-Issue $issues "Slice must include the original Approved Instruction CAI-LOCAL-001."
}
if (-not $sliceInstructionIds.ContainsKey("CAI-LOCAL-002")) {
  Add-Issue $issues "Slice must include the replacement Approved Instruction CAI-LOCAL-002."
}
# CAI-LOCAL-001 must be superseded by CAI-LOCAL-002.
if ($sliceInstructionIds.ContainsKey("CAI-LOCAL-001") -and $sliceInstructionIds.ContainsKey("CAI-LOCAL-002")) {
  $old = $sliceInstructionIds["CAI-LOCAL-001"]
  $new = $sliceInstructionIds["CAI-LOCAL-002"]
  if ([string]$old.com_status -ne "superseded") {
    Add-Issue $issues "CAI-LOCAL-001 must be marked superseded, found: $($old.com_status)."
  }
  if ([string]$old.com_superseded_by -ne "CAI-LOCAL-002") {
    Add-Issue $issues "CAI-LOCAL-001 com_superseded_by must link to CAI-LOCAL-002, found: $($old.com_superseded_by)."
  }
  if ([string]$new.com_status -ne "active") {
    Add-Issue $issues "CAI-LOCAL-002 must be active (the replacement), found: $($new.com_status)."
  }
  # The replacement instruction text must differ from the prior (a real change, not a no-op supersession).
  if ([string]$old.com_instruction_text -eq [string]$new.com_instruction_text) {
    Add-Issue $issues "CAI-LOCAL-002 instruction text must differ from CAI-LOCAL-001; identical text is not a supersession."
  }
  # The replacement approval receipt must differ from the original approval receipt.
  if ([string]$old.com_approval_receipt -eq [string]$new.com_approval_receipt) {
    Add-Issue $issues "CAI-LOCAL-002 com_approval_receipt must differ from CAI-LOCAL-001's; a replacement must be approved via its own NEW receipt."
  }
  # Effective-from ordering: the replacement effective date must be on or after the original's.
  $oldEffective = Get-ComparableInstant $old.com_effective_from
  $newEffective = Get-ComparableInstant $new.com_effective_from
  if ($null -ne $oldEffective -and $null -ne $newEffective -and $newEffective -lt $oldEffective) {
    Add-Issue $issues "CAI-LOCAL-002 com_effective_from must be on or after CAI-LOCAL-001's effective date ($($old.com_effective_from)), found: $($new.com_effective_from)."
  }
}

# Receipt source links: each approval receipt must be bound to its source by an approval link.
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
    Add-Issue $issues "$linkSubject must bind a known Source Record from a sibling slice, found: $($link.com_source_record)."
  }
  if ($evidenceRoles -notcontains $link.com_evidence_role) {
    Add-Issue $issues "$linkSubject evidence role is not in manifest vocabulary: $($link.com_evidence_role)."
  }
}
foreach ($approvalId in @("CR-LOCAL-INSTR-APPROVE-001", "CR-LOCAL-INSTR-APPROVE-002")) {
  $approvalLinks = @($links | Where-Object { $_.com_receipt -eq $approvalId })
  if ($approvalLinks.Count -lt 1) {
    Add-Issue $issues "Receipt $approvalId must be bound to its source evidence by at least one receipt source link."
  }
  else {
    $hasApprovalRole = @($approvalLinks | Where-Object { $_.com_evidence_role -eq "approval" }).Count -ge 1
    if (-not $hasApprovalRole) {
      Add-Issue $issues "Receipt $approvalId must have at least one receipt source link with com_evidence_role approval."
    }
  }
}
$supersedeLinks = @($links | Where-Object { $_.com_receipt -eq "CR-LOCAL-INSTR-SUPERSEDE-001" })
if ($supersedeLinks.Count -lt 1) {
  Add-Issue $issues "Receipt CR-LOCAL-INSTR-SUPERSEDE-001 must be bound to its source evidence by at least one receipt source link."
}

# Deferred instruction updates: every instruction's live mutation must be a deferred entry naming a receipt gate.
$deferredUpdates = @($run.instructionUpdatesDeferred | Where-Object { $null -ne $_ })
foreach ($deferred in $deferredUpdates) {
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "instruction")) {
    Add-Issue $issues "Deferred instruction update must name its instruction."
  }
  elseif (-not $sliceInstructionIds.ContainsKey([string]$deferred.instruction)) {
    Add-Issue $issues "Deferred instruction update references an unknown Approved Instruction: $($deferred.instruction)."
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred instruction update must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred instruction update for $($deferred.instruction) must state that the live mutation is receipt-gated."
  }
}
foreach ($instructionId in @($sliceInstructionIds.Keys)) {
  $deferred = $deferredUpdates | Where-Object { [string]$_.instruction -eq $instructionId } | Select-Object -First 1
  if (-not $deferred) {
    Add-Issue $issues "Missing deferred instruction update entry for $instructionId; live instruction mutation must be receipt-gated."
  }
}

# Acceptance mapping for AC 1, 2. localEvidence must not be self-asserting prose:
# every CR-LOCAL-INSTR-*, CAI-LOCAL-*, and CMC-LOCAL-* id it cites must resolve
# to a real slice entity, and each AC must cite at least one real slice id.
foreach ($criterion in @(1, 2)) {
  $mapping = @($slice.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
  if (-not $mapping) {
    Add-Issue $issues "Missing acceptance mapping for AC $criterion."
    continue
  }
  $evidenceItems = @($mapping.localEvidence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($evidenceItems.Count -lt 1) {
    Add-Issue $issues "Acceptance mapping for AC $criterion must list non-empty localEvidence."
  }
  if (-not (Test-HasNonEmptyField -Record $mapping -Field "tenantEvidenceRequired")) {
    Add-Issue $issues "Acceptance mapping for AC $criterion must state tenantEvidenceRequired."
  }
  $joinedEvidence = $evidenceItems -join " `n"
  $citedIds = [regex]::Matches($joinedEvidence, "(?:CR-LOCAL-INSTR-[A-Z0-9-]+|CAI-LOCAL-[A-Z0-9-]+|CMC-LOCAL-[A-Z0-9-]+)") | ForEach-Object { [string]$_.Value } | Sort-Object -Unique
  $citedAny = $false
  foreach ($citedId in $citedIds) {
    $resolved = $false
    if ($citedId -like "CR-LOCAL-INSTR-*") {
      if ($sliceReceiptIds.ContainsKey($citedId)) { $resolved = $true }
    }
    elseif ($citedId -like "CAI-LOCAL-*") {
      if ($sliceInstructionIds.ContainsKey($citedId)) { $resolved = $true }
    }
    elseif ($citedId -like "CMC-LOCAL-*") {
      if (-not [string]::IsNullOrWhiteSpace($embeddedCandidateId) -and $citedId -eq $embeddedCandidateId) { $resolved = $true }
    }
    if (-not $resolved) {
      Add-Issue $issues "Acceptance mapping for AC $criterion cites id '$citedId' which does not resolve to any receipt, instruction, or memory candidate in this slice."
    }
    else {
      $citedAny = $true
    }
  }
  if (-not $citedAny) {
    Add-Issue $issues "Acceptance mapping for AC $criterion must cite at least one real slice id (CR-LOCAL-INSTR-*/CAI-LOCAL-*/CMC-LOCAL-*) in localEvidence; self-asserting prose is not proof."
  }
}

if ($issues.Count -gt 0) {
  Write-Host "Approved instructions slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Approved instructions slice validation succeeded."
Write-Host "Approved instructions: $($instructions.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Supersessions: $($supersessions.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "APPROVED_INSTRUCTIONS_SLICE_VALIDATE_OK"
