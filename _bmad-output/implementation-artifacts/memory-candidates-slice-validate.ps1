param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$MemorySlicePath = "$PSScriptRoot\memory-candidates-slice.json",
  [string]$ManualSlicePath = "$PSScriptRoot\manual-source-record-slice.json",
  [string]$OutlookSlicePath = "$PSScriptRoot\outlook-source-reference-slice.json",
  [string]$Story13ExtractionPath = "$PSScriptRoot\proposed-work-item-extraction-slice.json",
  [string]$Story14ExtractionPath = "$PSScriptRoot\zero-multi-item-extraction-slice.json",
  [string]$DriftSlicePath = "$PSScriptRoot\source-drift-supersession-slice.json",
  [string]$IdempotentSlicePath = "$PSScriptRoot\idempotent-mutations-slice.json",
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

function Get-ColumnValues {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)][string]$TableSchemaName,
    [Parameter(Mandatory = $true)][string]$ColumnName
  )

  $table = @($Manifest.tables) | Where-Object { $_.schemaName -eq $TableSchemaName } | Select-Object -First 1
  $column = @($table.columns) | Where-Object { $_.name -eq $ColumnName } | Select-Object -First 1
  if ($null -ne $column.values) {
    return @($column.values | Where-Object { $null -ne $_ })
  }
  return @()
}

function Get-TableRequiredFields {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)][string]$TableSchemaName
  )

  $table = @($Manifest.tables) | Where-Object { $_.schemaName -eq $TableSchemaName } | Select-Object -First 1
  @(@($table.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Invoke-CollectSiblingIds {
  # Recursively walk a parsed sibling slice JSON and harvest every canonical
  # Council id / idempotency key by property name, plus the demo-evidence
  # workItemIds/receiptIds arrays. This is the single source of truth for
  # cross-slice collision checks so they cover ALL co-located slices, not just
  # the named 1.1-1.5 / 2.4 siblings (Story 4.3 hard rule: ids unique across ALL
  # slices).
  param(
    [Parameter(Mandatory = $false)][AllowNull()]$Node,
    [Parameter(Mandatory = $true)][hashtable]$WorkItems,
    [Parameter(Mandatory = $true)][hashtable]$Receipts,
    [Parameter(Mandatory = $true)][hashtable]$Keys,
    [Parameter(Mandatory = $true)][hashtable]$SourceRecords,
    [Parameter(Mandatory = $true)][hashtable]$MemoryCandidates
  )

  if ($null -eq $Node) { return }
  if ($Node -is [System.Collections.IList]) {
    foreach ($item in $Node) {
      Invoke-CollectSiblingIds -Node $item -WorkItems $WorkItems -Receipts $Receipts -Keys $Keys -SourceRecords $SourceRecords -MemoryCandidates $MemoryCandidates
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
          Invoke-CollectSiblingIds -Node $prop.Value -WorkItems $WorkItems -Receipts $Receipts -Keys $Keys -SourceRecords $SourceRecords -MemoryCandidates $MemoryCandidates
        }
      }
    }
  }
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
    Add-Issue $Issues "$Subject $Field must be strict boolean true."
  }
}

function Test-StrictBooleanFalse {
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
  if ($Record.$Field -isnot [bool] -or $Record.$Field) {
    Add-Issue $Issues "$Subject $Field must be strict boolean false."
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

function Read-JsonInput {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  try {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  }
  catch {
    Write-Host "Memory candidates slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

foreach ($path in @($ManifestPath, $MemorySlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $DriftSlicePath, $IdempotentSlicePath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required memory candidates validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$slice = Read-JsonInput -Path $MemorySlicePath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$driftSlice = Read-JsonInput -Path $DriftSlicePath
$idempotentSlice = Read-JsonInput -Path $IdempotentSlicePath
$issues = [System.Collections.Generic.List[string]]::new()

$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$recordStatuses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_recordstatus"
$scopeValues = Get-ColumnValues -Manifest $manifest -TableSchemaName "com_councilmemorycandidate" -ColumnName "com_scope"
$reviewStateValues = Get-ColumnValues -Manifest $manifest -TableSchemaName "com_councilmemorycandidate" -ColumnName "com_review_state"
$evidenceRoles = Get-ColumnValues -Manifest $manifest -TableSchemaName "com_councilreceiptsource" -ColumnName "com_evidence_role"
$memoryCandidateRequiredFields = Get-TableRequiredFields -Manifest $manifest -TableSchemaName "com_councilmemorycandidate"
$receiptRequiredFields = Get-TableRequiredFields -Manifest $manifest -TableSchemaName "com_councilreceipt"
$instructionTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilapprovedinstruction" } | Select-Object -First 1

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_recordstatus"; Values = $recordStatuses },
    @{ Name = "com_councilmemorycandidate.com_scope"; Values = $scopeValues },
    @{ Name = "com_councilmemorycandidate.com_review_state"; Values = $reviewStateValues },
    @{ Name = "com_councilreceiptsource.com_evidence_role"; Values = $evidenceRoles },
    @{ Name = "com_councilmemorycandidate required fields"; Values = $memoryCandidateRequiredFields },
    @{ Name = "com_councilreceipt required fields"; Values = $receiptRequiredFields }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

foreach ($requiredVerb in @("memory_proposed", "memory_promoted", "reviewed")) {
  if ($receiptVerbs -notcontains $requiredVerb) {
    Add-Issue $issues "Manifest com_receiptverb is missing a verb required by Story 4.3: $requiredVerb."
  }
}
foreach ($requiredReviewState in @("proposed", "approved", "rejected", "needs_clarification")) {
  if ($reviewStateValues -notcontains $requiredReviewState) {
    Add-Issue $issues "Manifest com_councilmemorycandidate.com_review_state is missing a value required by Story 4.3: $requiredReviewState."
  }
}
foreach ($requiredResult in @("accepted", "rejected", "no_op")) {
  if ($receiptResults -notcontains $requiredResult) {
    Add-Issue $issues "Manifest com_receiptresult is missing a result required by Story 4.3: $requiredResult."
  }
}
foreach ($requiredScope in @("project", "tenant")) {
  if ($scopeValues -notcontains $requiredScope) {
    Add-Issue $issues "Manifest com_councilmemorycandidate.com_scope is missing a value required by Story 4.3: $requiredScope."
  }
}
if ($evidenceRoles -notcontains "supporting") {
  Add-Issue $issues "Manifest com_councilreceiptsource.com_evidence_role is missing: supporting (sanctioned role for memory candidate source evidence)."
}
if ($null -eq $instructionTable) {
  Add-Issue $issues "Manifest must declare the com_councilapprovedinstruction table (the instruction Memory Candidates must stay distinct from)."
}

if ($slice.storyKey -ne "4-3-propose-memory-candidates") {
  Add-Issue $issues "Slice storyKey must be 4-3-propose-memory-candidates."
}
if ([string]$slice.status -notmatch "^local-contract") {
  Add-Issue $issues "Slice status must declare local contract evidence, found: $($slice.status)."
}

foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "requiresExplicitHumanApprovalForExecution", "receiptsAreLocalContractEvidenceOnly", "memoryCandidatesRemainDistinctFromInstructions", "noInstructionCreatedInThisSlice", "noMemoryPromotionInThisSlice", "actsAsInstructionStrictlyFalseForNonPromotedCandidates", "receiptsAreAppendOnly")) {
  if (-not ($slice.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($slice.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Slice guard must be boolean true: $($guardProperty.Name)."
  }
}

# Named sibling structural loads (for deep per-slice tripwires + runId collision).
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
$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$driftReceipts = @($driftSlice.driftRun.receipts | Where-Object { $null -ne $_ })
$driftSupersessions = @($driftSlice.driftRun.supersessions | Where-Object { $null -ne $_ })
$siblingRunIds = @(
  [string]$story13Extraction.extractionRun.runId,
  [string]$story14Extraction.extractionRun.runId,
  [string]$driftSlice.driftRun.runId,
  [string]$idempotentSlice.idempotencyRun.runId
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

foreach ($sliceLoad in @(
    @{ Name = "manual-source-record-slice sampleRecords"; Count = $manualSources.Count },
    @{ Name = "outlook-source-reference-slice sampleRecords"; Count = $outlookSources.Count },
    @{ Name = "zero-multi-item-extraction-slice embeddedSampleSourceRecords"; Count = $story14EmbeddedSources.Count },
    @{ Name = "proposed-work-item-extraction-slice proposedWorkItems"; Count = $story13Items.Count },
    @{ Name = "zero-multi-item-extraction-slice proposedWorkItems"; Count = $story14Items.Count },
    @{ Name = "source-drift-supersession-slice receipts"; Count = $driftReceipts.Count },
    @{ Name = "source-drift-supersession-slice supersessions"; Count = $driftSupersessions.Count }
  )) {
  if ($sliceLoad.Count -eq 0) {
    Add-Issue $issues "No records loaded from $($sliceLoad.Name); its cross-slice checks would silently no-op."
  }
}

# Generic cross-slice id harvest: walk EVERY sibling slice JSON in this folder so
# collision checks cover ALL co-located slices (Story 4.3 hard rule: ids unique
# across ALL slices), not only the named 1.1-1.5 / 2.4 siblings. Hashtables make
# the membership tests O(1) and immune to duplicate-fold bugs.
$siblingWorkItemIds = @{}
$siblingReceiptIds = @{}
$siblingIdempotencyKeys = @{}
$siblingSourceRecordIds = @{}
$siblingMemoryCandidateIds = @{}
$siblingSliceFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.json" |
  Where-Object { $_.Name -ne "dataverse-mvp-schema-manifest.json" -and $_.Name -ne "memory-candidates-slice.json" } |
  ForEach-Object { $_.FullName })
if ($siblingSliceFiles.Count -eq 0) {
  Add-Issue $issues "No sibling slice JSON files found in $PSScriptRoot; cross-slice id-collision checks would silently no-op."
}
foreach ($siblingFile in $siblingSliceFiles) {
  $siblingJson = Read-JsonInput -Path $siblingFile
  Invoke-CollectSiblingIds -Node $siblingJson -WorkItems $siblingWorkItemIds -Receipts $siblingReceiptIds -Keys $siblingIdempotencyKeys -SourceRecords $siblingSourceRecordIds -MemoryCandidates $siblingMemoryCandidateIds
}

# Fold harvested source-record ids into the named prior-source set used for
# com_source_record resolution (broader than the named 1.1/1.2/1.4 set).
$knownPriorSourceIds = @($priorSourcesById.Keys)
foreach ($sid in @($siblingSourceRecordIds.Keys)) {
  if ($knownPriorSourceIds -notcontains $sid) { $knownPriorSourceIds += $sid }
}

if ($knownPriorSourceIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be harvested from sibling slices; com_source_record checks would silently no-op."
}
if ($siblingWorkItemIds.Count -eq 0) {
  Add-Issue $issues "No Work Item IDs could be harvested from sibling slices; source-record-pattern ref checks would silently no-op."
}
if ($siblingReceiptIds.Count -eq 0) {
  Add-Issue $issues "No Receipt IDs could be harvested from sibling slices; receipt-pattern ref checks would silently no-op."
}
if ($siblingIdempotencyKeys.Count -eq 0) {
  Add-Issue $issues "No idempotency keys could be harvested from sibling slices; key collision checks would silently no-op."
}

$run = $slice.memoryRun
if ($null -eq $run) {
  Add-Issue $issues "Slice must carry a memoryRun block."
  Write-Host "Memory candidates slice validation failed:"
  foreach ($issue in $issues) { Write-Host "- $issue" }
  exit 1
}
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Memory run must declare a runId."
}
elseif ($siblingRunIds -contains [string]$run.runId) {
  Add-Issue $issues "Memory run must use a new local runId, not a sibling slice runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Memory run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Memory run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Memory run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "zero-multi-item-extraction-slice.json", "source-drift-supersession-slice.json")) {
  if (@($run.inputSourceRecordsFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Memory run must reference $inputSlice as an input."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Memory run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("memoryCandidateOriginsAreDistinct", "everyCandidateStartsProposedWithReceipt", "nonPromotedCandidateNeverActsAsInstruction", "reviewStateTransitionsAreReceiptBackedWithBeforeAndAfter", "promotionToApprovedInstructionIsReceiptGatedToAFutureStory", "liveMemoryCandidateRowCreationReceiptGatedToTenantStory", "receiptsAreAppendOnlyCorrectionsAreNewReceipts")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Memory run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Memory run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# ---- Receipts (validate BEFORE candidates so candidate receipt-history refs resolve) ----
$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -ne 4) {
  Add-Issue $issues "Memory slice must include exactly four receipts (two memory_proposed creation, two reviewed transition), found $($receipts.Count)."
}
$receiptRequiredFields = @($receiptRequiredFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique
$sliceReceiptIds = @{}
$sliceReceiptById = @{}
$sliceReceiptIdempotencyKeys = @{}
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
    if ($receiptId -notmatch "^CR-LOCAL-MEMORY-") {
      Add-Issue $issues "$subject must use Council-level CR-LOCAL-MEMORY-* identity."
    }
    if ($sliceReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "Duplicate receipt ID in slice: $receiptId."
    }
    else {
      $sliceReceiptIds[$receiptId] = $receipt
      $sliceReceiptById[$receiptId] = $receipt
    }
    if ($siblingReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "$subject collides with a receipt ID from a sibling slice or demo evidence."
    }
    if ($siblingMemoryCandidateIds.ContainsKey($receiptId)) {
      Add-Issue $issues "$subject collides with a Memory Candidate ID from a sibling slice."
    }
  }

  if ($receiptVerbs -notcontains $receipt.com_verb) {
    Add-Issue $issues "$subject verb is not in manifest com_receiptverb vocabulary: $($receipt.com_verb)."
  }
  elseif (@("memory_proposed", "reviewed") -notcontains [string]$receipt.com_verb) {
    Add-Issue $issues "$subject must use verb memory_proposed or reviewed for Story 4.3 memory candidate evidence, found: $($receipt.com_verb)."
  }
  if ($actorTypes -notcontains $receipt.com_actor_type) {
    Add-Issue $issues "$subject actor type is not in manifest com_actortype vocabulary: $($receipt.com_actor_type)."
  }
  if ($receiptResults -notcontains $receipt.com_result) {
    Add-Issue $issues "$subject result is not in manifest com_receiptresult vocabulary: $($receipt.com_result)."
  }
  Test-IsoTimestamp -Issues $issues -Record $receipt -Field "com_occurred_at" -Subject $subject | Out-Null

  $receiptKey = [string]$receipt.com_idempotency_key
  if (-not [string]::IsNullOrWhiteSpace($receiptKey)) {
    if ($sliceReceiptIdempotencyKeys.ContainsKey($receiptKey)) {
      Add-Issue $issues "$subject reuses an idempotency key already used by another receipt in this slice: $receiptKey. Receipt idempotency keys are alternate keys and must be unique (append-only)."
    }
    else {
      $sliceReceiptIdempotencyKeys[$receiptKey] = $true
    }
    if ($siblingIdempotencyKeys.ContainsKey($receiptKey)) {
      Add-Issue $issues "$subject idempotency key collides with a sibling slice idempotency key: $receiptKey."
    }
  }

  if ($receipt.com_append_only_locked -isnot [bool] -or -not $receipt.com_append_only_locked) {
    Add-Issue $issues "$subject com_append_only_locked must be strict boolean true (receipts are append-only)."
  }
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 4.3 receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 4.3 receipts are local contract evidence only."
      }
    }
  }

  # Content delta (proven, not self-asserted): before and after must both be present and differ.
  if (-not (Test-HasNonEmptyField -Record $receipt -Field "com_before_state") -or -not (Test-HasNonEmptyField -Record $receipt -Field "com_after_state")) {
    Add-Issue $issues "$subject must carry non-empty com_before_state and com_after_state."
  }
  elseif ([string]$receipt.com_before_state -eq [string]$receipt.com_after_state) {
    Add-Issue $issues "$subject com_before_state and com_after_state must differ (content delta), found: $($receipt.com_before_state)."
  }
}

# ---- Receipt source links ----
$links = @($run.receiptSourceLinks | Where-Object { $null -ne $_ })
if ($links.Count -lt $receipts.Count) {
  Add-Issue $issues "Every receipt must be bound to its source evidence by a receiptSourceLinks entry; found $($links.Count) links for $($receipts.Count) receipts."
}
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
  elseif ($link.com_evidence_role -ne "supporting") {
    Add-Issue $issues "$linkSubject must use the supporting role for memory candidate source evidence, found: $($link.com_evidence_role)."
  }
}
foreach ($receiptId in @($sliceReceiptIds.Keys)) {
  if (@($links | Where-Object { $_.com_receipt -eq $receiptId }).Count -lt 1) {
    Add-Issue $issues "Receipt $receiptId must be bound to its source evidence by at least one receiptSourceLinks entry."
  }
}

# ---- Memory Candidates ----
$candidates = @($run.candidates | Where-Object { $null -ne $_ })
if ($candidates.Count -ne 2) {
  Add-Issue $issues "Memory slice must include exactly two Memory Candidates (one per distinct origin), found $($candidates.Count)."
}
$sliceCandidateIds = @{}
$seenOrigins = @{}
foreach ($candidate in $candidates) {
  $candidateId = [string]$candidate.com_council_memory_candidate_id
  $subject = "Memory Candidate $candidateId"

  foreach ($field in $memoryCandidateRequiredFields) {
    if (-not (Test-HasNonEmptyField -Record $candidate -Field $field)) {
      Add-Issue $issues "$subject missing required manifest memory-candidate field: $field."
    }
  }

  if ([string]::IsNullOrWhiteSpace($candidateId)) {
    Add-Issue $issues "Memory Candidate must declare com_council_memory_candidate_id."
  }
  else {
    if ($candidateId -notmatch "^CMC-LOCAL-") {
      Add-Issue $issues "$subject must use fresh CMC-LOCAL-* identity."
    }
    if ($sliceCandidateIds.ContainsKey($candidateId)) {
      Add-Issue $issues "Duplicate Memory Candidate id in slice: $candidateId."
    }
    else {
      $sliceCandidateIds[$candidateId] = $candidate
    }
    if ($siblingMemoryCandidateIds.ContainsKey($candidateId)) {
      Add-Issue $issues "$subject collides with a Memory Candidate id from a sibling slice."
    }
    if ($siblingReceiptIds.ContainsKey($candidateId) -or $siblingWorkItemIds.ContainsKey($candidateId) -or $siblingSourceRecordIds.ContainsKey($candidateId)) {
      Add-Issue $issues "$subject collides with a non-candidate id from a sibling slice."
    }
  }

  if ($scopeValues -notcontains [string]$candidate.com_scope) {
    Add-Issue $issues "$subject com_scope is not in manifest com_councilmemorycandidate.com_scope vocabulary, found: $($candidate.com_scope)."
  }
  if ($reviewStateValues -notcontains [string]$candidate.com_review_state) {
    Add-Issue $issues "$subject com_review_state is not in manifest vocabulary, found: $($candidate.com_review_state)."
  }
  elseif (@("proposed", "rejected", "needs_clarification") -notcontains [string]$candidate.com_review_state) {
    Add-Issue $issues "$subject com_review_state must end in proposed, rejected, or needs_clarification for Story 4.3 (no approval in this slice), found: $($candidate.com_review_state)."
  }
  Test-ConfidenceInRange -Issues $issues -Record $candidate -Field "com_confidence" -Subject $subject

  $candidateSource = [string]$candidate.com_source_record
  if ([string]::IsNullOrWhiteSpace($candidateSource) -or $knownPriorSourceIds -notcontains $candidateSource) {
    Add-Issue $issues "$subject com_source_record must reference a known Source Record from a sibling slice, found: $candidateSource."
  }

  # actsAsInstruction strictly false for every non-promoted candidate (both are non-promoted here).
  Test-StrictBooleanFalse -Issues $issues -Record $candidate -Field "actsAsInstruction" -Subject $subject
  Test-StrictBooleanTrue -Issues $issues -Record $candidate -Field "distinctFromInstruction" -Subject $subject

  # Origin must be one of the two distinct sanctioned origins.
  if (-not (Test-HasNonEmptyField -Record $candidate -Field "origin")) {
    Add-Issue $issues "$subject must declare a non-empty origin."
  }
  else {
    $originValue = [string]$candidate.origin
    if (@("source_record_pattern", "receipt_pattern") -notcontains $originValue) {
      Add-Issue $issues "$subject origin must be source_record_pattern or receipt_pattern, found: $originValue."
    }
    elseif ($seenOrigins.ContainsKey($originValue)) {
      Add-Issue $issues "$subject origin '$originValue' duplicates another candidate's origin; the two candidates must come from distinct origins."
    }
    else {
      $seenOrigins[$originValue] = $true
    }

    if ($originValue -eq "source_record_pattern") {
      $pattern = $candidate.sourceRecordPattern
      if ($null -eq $pattern) {
        Add-Issue $issues "$subject (source_record_pattern) must carry a sourceRecordPattern block."
      }
      else {
        if ([string]$pattern.sourceRecord -ne $candidateSource) {
          Add-Issue $issues "$subject sourceRecordPattern.sourceRecord must equal the candidate's com_source_record ($candidateSource), found: $($pattern.sourceRecord)."
        }
        $refs = @($pattern.sourceRefs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($refs.Count -lt 2) {
          Add-Issue $issues "$subject sourceRecordPattern.sourceRefs must list at least two resolving refs (the source plus its downstream work items), found $($refs.Count)."
        }
        foreach ($ref in $refs) {
          $refStr = [string]$ref
          if ($refStr -eq $candidateSource) { continue }
          if ($siblingWorkItemIds.ContainsKey($refStr)) { continue }
          if ($siblingSourceRecordIds.ContainsKey($refStr)) { continue }
          Add-Issue $issues "$subject sourceRecordPattern.sourceRefs entry '$refStr' must resolve to a known sibling Source Record or Work Item."
        }
        if (-not (Test-HasNonEmptyField -Record $pattern -Field "patternNote")) {
          Add-Issue $issues "$subject sourceRecordPattern.patternNote must state the observed pattern (not self-asserted)."
        }
      }
    }
    elseif ($originValue -eq "receipt_pattern") {
      $pattern = $candidate.receiptPatternOrigin
      if ($null -eq $pattern) {
        Add-Issue $issues "$subject (receipt_pattern) must carry a receiptPatternOrigin block."
      }
      else {
        if ([string]$pattern.sourceRecord -ne $candidateSource) {
          Add-Issue $issues "$subject receiptPatternOrigin.sourceRecord must equal the candidate's com_source_record ($candidateSource), found: $($pattern.sourceRecord)."
        }
        $receiptRefs = @($pattern.receipts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($receiptRefs.Count -lt 1) {
          Add-Issue $issues "$subject receiptPatternOrigin.receipts must list at least one resolving sibling receipt, found $($receiptRefs.Count)."
        }
        foreach ($ref in $receiptRefs) {
          $refStr = [string]$ref
          if (-not $siblingReceiptIds.ContainsKey($refStr)) {
            Add-Issue $issues "$subject receiptPatternOrigin.receipts entry '$refStr' must resolve to a known sibling Receipt."
          }
        }
        $sourceRefs = @($pattern.sourceRefs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        foreach ($ref in $sourceRefs) {
          $refStr = [string]$ref
          if ($refStr -eq $candidateSource) { continue }
          if ($siblingSourceRecordIds.ContainsKey($refStr)) { continue }
          Add-Issue $issues "$subject receiptPatternOrigin.sourceRefs entry '$refStr' must resolve to a known sibling Source Record."
        }
        if (-not (Test-HasNonEmptyField -Record $pattern -Field "patternNote")) {
          Add-Issue $issues "$subject receiptPatternOrigin.patternNote must state the observed pattern (not self-asserted)."
        }
      }
    }
  }

  # Receipt history must reference real slice receipts and prove the proposed -> final transition.
  $history = @($candidate.receiptHistory | Where-Object { $null -ne $_ })
  if ($history.Count -lt 2) {
    Add-Issue $issues "$subject receiptHistory must list at least a creation entry and a review_transition entry, found $($history.Count)."
  }
  $historyReceiptIds = @{}
  foreach ($entry in $history) {
    $entryReceipt = [string]$entry.receipt
    if ([string]::IsNullOrWhiteSpace($entryReceipt) -or -not $sliceReceiptIds.ContainsKey($entryReceipt)) {
      Add-Issue $issues "$subject receiptHistory entry references an unknown slice receipt: $entryReceipt."
    }
    else {
      $historyReceiptIds[$entryReceipt] = $true
    }
  }
  # com_created_receipt and com_review_receipt must exist and be in history.
  $createdReceiptId = [string]$candidate.com_created_receipt
  if ([string]::IsNullOrWhiteSpace($createdReceiptId) -or -not $sliceReceiptIds.ContainsKey($createdReceiptId)) {
    Add-Issue $issues "$subject com_created_receipt must reference a slice receipt, found: $createdReceiptId."
  }
  elseif (-not $historyReceiptIds.ContainsKey($createdReceiptId)) {
    Add-Issue $issues "$subject com_created_receipt ($createdReceiptId) must appear in receiptHistory."
  }
  $reviewReceiptId = [string]$candidate.com_review_receipt
  if ([string]::IsNullOrWhiteSpace($reviewReceiptId) -or -not $sliceReceiptIds.ContainsKey($reviewReceiptId)) {
    Add-Issue $issues "$subject com_review_receipt must reference a slice receipt, found: $reviewReceiptId."
  }
  elseif (-not $historyReceiptIds.ContainsKey($reviewReceiptId)) {
    Add-Issue $issues "$subject com_review_receipt ($reviewReceiptId) must appear in receiptHistory."
  }
  elseif ($createdReceiptId -eq $reviewReceiptId) {
    Add-Issue $issues "$subject com_created_receipt and com_review_receipt must be distinct receipts (creation then transition)."
  }

  # Creation receipt semantics: verb memory_proposed, result accepted, after proposed.
  if ($sliceReceiptIds.ContainsKey($createdReceiptId)) {
    $createdReceipt = $sliceReceiptById[$createdReceiptId]
    if ([string]$createdReceipt.com_verb -ne "memory_proposed") {
      Add-Issue $issues "$subject com_created_receipt ($createdReceiptId) verb must be memory_proposed, found: $($createdReceipt.com_verb)."
    }
    if ([string]$createdReceipt.com_result -ne "accepted") {
      Add-Issue $issues "$subject com_created_receipt ($createdReceiptId) result must be accepted, found: $($createdReceipt.com_result)."
    }
    if ([string]$createdReceipt.com_after_state -ne "proposed") {
      Add-Issue $issues "$subject com_created_receipt ($createdReceiptId) com_after_state must be proposed (candidate starts proposed), found: $($createdReceipt.com_after_state)."
    }
    if ([string]$createdReceipt.com_before_state -ne "absent") {
      Add-Issue $issues "$subject com_created_receipt ($createdReceiptId) com_before_state must be absent (no prior candidate), found: $($createdReceipt.com_before_state)."
    }
  }

  # Review transition receipt semantics + content-delta cross-check (proven, not self-asserted):
  # before must equal the creation's after (proposed), after must equal the candidate's final review_state.
  if ($sliceReceiptIds.ContainsKey($reviewReceiptId)) {
    $reviewReceipt = $sliceReceiptById[$reviewReceiptId]
    if ([string]$reviewReceipt.com_verb -ne "reviewed") {
      Add-Issue $issues "$subject com_review_receipt ($reviewReceiptId) verb must be reviewed, found: $($reviewReceipt.com_verb)."
    }
    if ([string]$reviewReceipt.com_before_state -ne "proposed") {
      Add-Issue $issues "$subject com_review_receipt ($reviewReceiptId) com_before_state must be proposed (matching the creation's after), found: $($reviewReceipt.com_before_state)."
    }
    if ([string]$reviewReceipt.com_after_state -ne [string]$candidate.com_review_state) {
      Add-Issue $issues "$subject com_review_receipt ($reviewReceiptId) com_after_state must equal the candidate's current com_review_state ($($candidate.com_review_state)) — content delta must be proven, not self-asserted; found: $($reviewReceipt.com_after_state)."
    }
    if (@("rejected", "needs_clarification") -notcontains [string]$reviewReceipt.com_after_state) {
      Add-Issue $issues "$subject com_review_receipt ($reviewReceiptId) com_after_state must be rejected or needs_clarification for Story 4.3, found: $($reviewReceipt.com_after_state)."
    }
    if ([string]$reviewReceipt.com_result -ne "rejected" -and [string]$reviewReceipt.com_result -ne "no_op") {
      Add-Issue $issues "$subject com_review_receipt ($reviewReceiptId) com_result must be rejected (for a rejected candidate) or no_op (for a needs_clarification candidate), found: $($reviewReceipt.com_result)."
    }
    # Result / after-state coherence: rejected after-state must pair with rejected result; needs_clarification pairs with no_op.
    if ([string]$reviewReceipt.com_after_state -eq "rejected" -and [string]$reviewReceipt.com_result -ne "rejected") {
      Add-Issue $issues "$subject com_review_receipt ($reviewReceiptId) moving to rejected must carry result rejected, found: $($reviewReceipt.com_result)."
    }
    if ([string]$reviewReceipt.com_after_state -eq "needs_clarification" -and [string]$reviewReceipt.com_result -ne "no_op") {
      Add-Issue $issues "$subject com_review_receipt ($reviewReceiptId) moving to needs_clarification must carry result no_op, found: $($reviewReceipt.com_result)."
    }
  }
}

# Exactly one of each sanctioned origin, and exactly one rejected + one needs_clarification transition.
if (-not $seenOrigins.ContainsKey("source_record_pattern")) {
  Add-Issue $issues "Memory slice must include exactly one candidate with origin source_record_pattern."
}
if (-not $seenOrigins.ContainsKey("receipt_pattern")) {
  Add-Issue $issues "Memory slice must include exactly one candidate with origin receipt_pattern."
}
$transitionTargets = @($candidates | ForEach-Object { [string]$_.com_review_state } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if (@($transitionTargets | Where-Object { $_ -eq "rejected" }).Count -ne 1) {
  Add-Issue $issues "Exactly one candidate must transition to rejected, found $(@($transitionTargets | Where-Object { $_ -eq 'rejected' }).Count)."
}
if (@($transitionTargets | Where-Object { $_ -eq "needs_clarification" }).Count -ne 1) {
  Add-Issue $issues "Exactly one candidate must transition to needs_clarification, found $(@($transitionTargets | Where-Object { $_ -eq 'needs_clarification' }).Count)."
}

# Timestamp ordering: each candidate's review receipt must occur after its creation receipt.
foreach ($candidate in $candidates) {
  $candidateId = [string]$candidate.com_council_memory_candidate_id
  $subject = "Memory Candidate $candidateId"
  $createdId = [string]$candidate.com_created_receipt
  $reviewId = [string]$candidate.com_review_receipt
  if ($sliceReceiptById.ContainsKey($createdId) -and $sliceReceiptById.ContainsKey($reviewId)) {
    $createdAt = Get-ComparableInstant $sliceReceiptById[$createdId].com_occurred_at
    $reviewAt = Get-ComparableInstant $sliceReceiptById[$reviewId].com_occurred_at
    if ($null -ne $createdAt -and $null -ne $reviewAt -and $reviewAt -le $createdAt) {
      Add-Issue $issues "$subject com_review_receipt ($reviewId) must occur after com_created_receipt ($createdId), found review $($sliceReceiptById[$reviewId].com_occurred_at) <= creation $($sliceReceiptById[$createdId].com_occurred_at)."
    }
  }
}

# ---- Deferred instruction promotion ----
$promotionDeferred = @($run.instructionPromotionDeferred | Where-Object { $null -ne $_ })
if ($promotionDeferred.Count -lt $candidates.Count) {
  Add-Issue $issues "Every candidate must have an instructionPromotionDeferred entry; found $($promotionDeferred.Count) for $($candidates.Count) candidates."
}
foreach ($deferred in $promotionDeferred) {
  $deferredCandidate = [string]$deferred.candidate
  $subject = "Deferred promotion $deferredCandidate"
  if ([string]::IsNullOrWhiteSpace($deferredCandidate) -or -not $sliceCandidateIds.ContainsKey($deferredCandidate)) {
    Add-Issue $issues "$subject must name a candidate that exists in this slice, found: $deferredCandidate."
    continue
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "$subject must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "$subject deferredUpdate must state that promotion is receipt-gated."
  }
  if ([string]$deferred.deferredUpdate -notmatch "memory_promoted") {
    Add-Issue $issues "$subject deferredUpdate must name the memory_promoted receipt gate for promotion."
  }
  if ([string]$deferred.deferredUpdate -notmatch "no live tenant write|no tenant write|no live write|no_tenant_write|no live") {
    Add-Issue $issues "$subject deferredUpdate must state that no live tenant write was performed in this slice."
  }
}
foreach ($candidateId in @($sliceCandidateIds.Keys)) {
  $deferred = $promotionDeferred | Where-Object { [string]$_.candidate -eq $candidateId } | Select-Object -First 1
  if (-not $deferred) {
    Add-Issue $issues "Missing instructionPromotionDeferred entry for candidate $candidateId."
  }
}

$memoryWritesDeferred = @($run.deferredMemoryWrites | Where-Object { $null -ne $_ })
if ($memoryWritesDeferred.Count -lt $candidates.Count) {
  Add-Issue $issues "Every candidate must have a deferredMemoryWrites entry; found $($memoryWritesDeferred.Count) for $($candidates.Count) candidates."
}
foreach ($deferred in $memoryWritesDeferred) {
  $deferredCandidate = [string]$deferred.candidate
  $subject = "Deferred memory write $deferredCandidate"
  if ([string]::IsNullOrWhiteSpace($deferredCandidate) -or -not $sliceCandidateIds.ContainsKey($deferredCandidate)) {
    Add-Issue $issues "$subject must name a candidate that exists in this slice, found: $deferredCandidate."
    continue
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "$subject must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "$subject deferredUpdate must state that the live row creation is receipt-gated."
  }
  if ([string]$deferred.deferredUpdate -notmatch "no live tenant write|no tenant write|no live write|no_tenant_write|no live") {
    Add-Issue $issues "$subject deferredUpdate must state that no live tenant write was performed in this slice."
  }
}

# No instruction created / no promotion in this slice: the slice must not carry
# any com_councilapprovedinstruction id or memory_promoted receipt.
foreach ($receipt in $receipts) {
  if ([string]$receipt.com_verb -eq "memory_promoted") {
    Add-Issue $issues "Slice must not carry a memory_promoted receipt; no promotion occurs in Story 4.3 (found $($receipt.com_receipt_id))."
  }
}
$rawSliceText = Get-Content -LiteralPath $MemorySlicePath -Raw
if ($rawSliceText -match "com_council_approved_instruction_id") {
  Add-Issue $issues "Slice must not mint any com_councilapprovedinstruction id; candidates stay distinct from instructions in Story 4.3."
}

# ---- Acceptance mapping ----
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
  # localEvidence must cite real slice ids (CR-LOCAL-MEMORY-*, CMC-LOCAL-*) that resolve,
  # and sibling ids it cites must resolve too. Self-asserting prose is not proof.
  $joinedEvidence = $evidenceItems -join " `n"
  $citedIds = [regex]::Matches($joinedEvidence, "(?:CR-LOCAL-MEMORY-[A-Z0-9-]+|CMC-LOCAL-[A-Z0-9-]+)") | ForEach-Object { [string]$_.Value } | Sort-Object -Unique
  $citedAny = $false
  foreach ($citedId in $citedIds) {
    $resolved = $false
    if ($citedId -like "CR-LOCAL-MEMORY-*") {
      if ($sliceReceiptIds.ContainsKey($citedId)) { $resolved = $true }
    }
    elseif ($citedId -like "CMC-LOCAL-*") {
      if ($sliceCandidateIds.ContainsKey($citedId)) { $resolved = $true }
    }
    if (-not $resolved) {
      Add-Issue $issues "Acceptance mapping for AC $criterion cites id '$citedId' which does not resolve to any receipt or memory candidate in this slice."
    }
    else {
      $citedAny = $true
    }
  }
  if (-not $citedAny) {
    Add-Issue $issues "Acceptance mapping for AC $criterion must cite at least one real slice id (CR-LOCAL-MEMORY-* or CMC-LOCAL-*) in localEvidence; self-asserting prose is not proof."
  }
  # Sibling ids cited in localEvidence must resolve to known sibling entities.
  $citedSiblingIds = [regex]::Matches($joinedEvidence, "(?:CR-LOCAL-DRIFT-[A-Z0-9-]+|CR-LOCAL-SUPERSEDE-[A-Z0-9-]+|CWI-LOCAL-[A-Z0-9-]+|CSR-[A-Z0-9-]+)") | ForEach-Object { [string]$_.Value } | Sort-Object -Unique
  foreach ($citedSiblingId in $citedSiblingIds) {
    $resolved = $false
    if ($citedSiblingId -like "CWI-LOCAL-*") {
      if ($siblingWorkItemIds.ContainsKey($citedSiblingId)) { $resolved = $true }
    }
    elseif ($citedSiblingId -like "CSR-*") {
      if ($siblingSourceRecordIds.ContainsKey($citedSiblingId)) { $resolved = $true }
    }
    elseif ($citedSiblingId -like "CR-LOCAL-DRIFT-*" -or $citedSiblingId -like "CR-LOCAL-SUPERSEDE-*") {
      if ($siblingReceiptIds.ContainsKey($citedSiblingId)) { $resolved = $true }
    }
    if (-not $resolved) {
      Add-Issue $issues "Acceptance mapping for AC $criterion cites sibling id '$citedSiblingId' which does not resolve to any known sibling entity."
    }
  }
}

if ($issues.Count -gt 0) {
  Write-Host "Memory candidates slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Memory candidates slice validation succeeded."
Write-Host "Memory candidates: $($candidates.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "Deferred instruction promotions: $($promotionDeferred.Count)"
Write-Host "Deferred memory writes: $($memoryWritesDeferred.Count)"
Write-Host "MEMORY_CANDIDATES_SLICE_VALIDATE_OK"
