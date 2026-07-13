param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$IdempotentSlicePath = "$PSScriptRoot\idempotent-mutations-slice.json",
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

function Get-ColumnChoiceName {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)][string]$TableSchemaName,
    [Parameter(Mandatory = $true)][string]$ColumnName
  )

  $table = @($Manifest.tables) | Where-Object { $_.schemaName -eq $TableSchemaName } | Select-Object -First 1
  $column = @($table.columns) | Where-Object { $_.name -eq $ColumnName } | Select-Object -First 1
  [string]$column.choice
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

function Read-JsonInput {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  try {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  }
  catch {
    Write-Host "Idempotent mutations slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

foreach ($path in @($ManifestPath, $IdempotentSlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $DriftSlicePath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required idempotent mutations validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$slice = Read-JsonInput -Path $IdempotentSlicePath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$driftSlice = Read-JsonInput -Path $DriftSlicePath
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath
$rawSliceText = Get-Content -LiteralPath $IdempotentSlicePath -Raw
$issues = [System.Collections.Generic.List[string]]::new()

$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$workItemTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemtype"
$workItemStateGroups = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemstategroup"
$riskClasses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_riskclass"
$sourceSystems = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_sourcesystem"
$sourceKinds = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_sourcekind"
$dataBoundaryPolicies = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_databoundarypolicy"
$extractionStatuses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_extractionstatus"

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_workitemtype"; Values = $workItemTypes },
    @{ Name = "com_workitemstategroup"; Values = $workItemStateGroups },
    @{ Name = "com_riskclass"; Values = $riskClasses },
    @{ Name = "com_sourcesystem"; Values = $sourceSystems },
    @{ Name = "com_sourcekind"; Values = $sourceKinds },
    @{ Name = "com_databoundarypolicy"; Values = $dataBoundaryPolicies },
    @{ Name = "com_extractionstatus"; Values = $extractionStatuses }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

foreach ($requiredVerb in @("proposed", "policy_denied")) {
  if ($receiptVerbs -notcontains $requiredVerb) {
    Add-Issue $issues "Manifest com_receiptverb is missing a verb required by Story 2.4: $requiredVerb."
  }
}
foreach ($requiredResult in @("accepted", "no_op", "rejected")) {
  if ($receiptResults -notcontains $requiredResult) {
    Add-Issue $issues "Manifest com_receiptresult is missing a result required by Story 2.4: $requiredResult."
  }
}
foreach ($requiredActor in @("connector", "system", "minion")) {
  if ($actorTypes -notcontains $requiredActor) {
    Add-Issue $issues "Manifest com_actortype is missing an actor type required by Story 2.4: $requiredActor."
  }
}

if ($slice.storyKey -ne "2-4-enforce-idempotent-mutations") {
  Add-Issue $issues "Slice storyKey must be 2-4-enforce-idempotent-mutations."
}
if ([string]$slice.status -notmatch "^local-contract") {
  Add-Issue $issues "Slice status must declare local contract evidence, found: $($slice.status)."
}

foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "requiresExplicitHumanApprovalForExecution", "receiptsAreLocalContractEvidenceOnly", "mutationsAreIdempotent", "everyMutationCarriesIdempotencyKey", "duplicateKeysRejectedWithoutSecondWorkItem", "unverifiableKeysRequireHumanReviewBeforeRetry", "receiptsAreAppendOnly")) {
  if (-not ($slice.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($slice.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Slice guard must be boolean true: $($guardProperty.Name)."
  }
}

# Cross-slice prior source IDs (for com_primary_source_record validation).
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

# Cross-slice Work Item IDs (Story 1.3/1.4 proposed Work Items + demo state-transition work items).
$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$siblingWorkItemIds = @($story13Items + $story14Items | ForEach-Object { [string]$_.com_council_work_item_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$demoWorkItemIds = @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
$siblingWorkItemIds = @($siblingWorkItemIds + $demoWorkItemIds | Sort-Object -Unique)

# Cross-slice Receipt IDs (Story 1.5 receipts + demo state-transition receipts).
$driftReceipts = @($driftSlice.driftRun.receipts | Where-Object { $null -ne $_ })
$siblingReceiptIds = @($driftReceipts | ForEach-Object { [string]$_.com_receipt_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$demoReceiptIds = @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
$siblingReceiptIds = @($siblingReceiptIds + $demoReceiptIds | Sort-Object -Unique)

# Sibling idempotency keys (Story 1.5 receipts carry com_idempotency_key).
$siblingIdempotencyKeys = @($driftReceipts | ForEach-Object { [string]$_.com_idempotency_key } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

foreach ($sliceLoad in @(
    @{ Name = "manual-source-record-slice sampleRecords"; Count = $manualSources.Count },
    @{ Name = "outlook-source-reference-slice sampleRecords"; Count = $outlookSources.Count },
    @{ Name = "zero-multi-item-extraction-slice embeddedSampleSourceRecords"; Count = $story14EmbeddedSources.Count },
    @{ Name = "proposed-work-item-extraction-slice proposedWorkItems"; Count = $story13Items.Count },
    @{ Name = "zero-multi-item-extraction-slice proposedWorkItems"; Count = $story14Items.Count },
    @{ Name = "source-drift-supersession-slice receipts"; Count = $driftReceipts.Count }
  )) {
  if ($sliceLoad.Count -eq 0) {
    Add-Issue $issues "No records loaded from $($sliceLoad.Name); its cross-slice checks would silently no-op."
  }
}

if ($knownPriorSourceIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be loaded from the Story 1.1/1.2/1.4 slices; com_primary_source_record checks would silently no-op."
}
if ($siblingWorkItemIds.Count -eq 0) {
  Add-Issue $issues "No Work Item IDs could be loaded from sibling slices; Work Item collision checks would silently no-op."
}
if ($siblingReceiptIds.Count -eq 0) {
  Add-Issue $issues "No Receipt IDs could be loaded from sibling slices; receipt collision checks would silently no-op."
}

$run = $slice.idempotencyRun
if ($null -eq $run) {
  Add-Issue $issues "Slice must carry an idempotencyRun block."
  Write-Host "Idempotent mutations slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Idempotency run must declare a runId."
}
elseif (@([string]$story13Extraction.extractionRun.runId, [string]$story14Extraction.extractionRun.runId, [string]$driftSlice.driftRun.runId) -contains [string]$run.runId) {
  Add-Issue $issues "Idempotency run must use a new local runId, not a sibling slice runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Idempotency run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Idempotency run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Idempotency run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "zero-multi-item-extraction-slice.json")) {
  if (@($run.inputSourceRecordsFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Idempotency run must reference $inputSlice as an input."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Idempotency run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("everyMutationMustCarryIdempotencyKey", "duplicateKeyHandlingIsNoOpOrRejectedWithOneReceiptReferencingOriginal", "duplicateKeyHandlingMintsNoSecondWorkItemOrPayloadReceipt", "unverifiableKeyYieldsFailureOrPolicyDenialReceiptAndHumanReviewFlag", "noRetryBeforeHumanReviewOnUnverifiableKey", "liveWorkItemCreationReceiptGatedToEpic2", "receiptsAreAppendOnlyCorrectionsAreNewReceipts")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Idempotency run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Idempotency run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

$declaredTriggerKinds = @("connector", "schedule", "agent")
if (@($run.triggerKinds | Where-Object { $null -ne $_ }).Count -ne 3) {
  Add-Issue $issues "Idempotency run triggerKinds must list exactly the three trigger kinds (connector, schedule, agent)."
}
foreach ($kind in $declaredTriggerKinds) {
  if (@($run.triggerKinds | Where-Object { [string]$_ -eq $kind }).Count -ne 1) {
    Add-Issue $issues "Idempotency run triggerKinds must include exactly one '$kind'."
  }
}

$mutations = @($run.mutations | Where-Object { $null -ne $_ })
if ($mutations.Count -lt 5) {
  Add-Issue $issues "Idempotency run must include at least five mutations (three trigger kinds, one duplicate, one unverifiable), found $($mutations.Count)."
}

$allowedTriggerKinds = @("connector", "schedule", "agent")
$allowedDuplicateOutcomes = @("no_op", "rejected", "flagged")
$mutationIds = @{}
$mutationKeys = @{}
$keyToMutations = @{}
$nonDuplicateTriggerKinds = @{}
foreach ($mutation in $mutations) {
  $mutationId = [string]$mutation.mutationId
  $subject = "Mutation $mutationId"
  if ([string]::IsNullOrWhiteSpace($mutationId)) {
    Add-Issue $issues "Mutation must declare a mutationId."
  }
  else {
    if ($mutationIds.ContainsKey($mutationId)) {
      Add-Issue $issues "Duplicate mutationId in slice: $mutationId."
    }
    else {
      $mutationIds[$mutationId] = $mutation
    }
  }

  if (-not (Test-HasNonEmptyField -Record $mutation -Field "idempotencyKey")) {
    Add-Issue $issues "$subject must carry a non-empty idempotencyKey (every mutation must be idempotent)."
  }
  else {
    $key = [string]$mutation.idempotencyKey
    if ($mutationKeys.ContainsKey($key)) {
      $mutationKeys[$key] += 1
    }
    else {
      $mutationKeys[$key] = 1
    }
    if (-not $keyToMutations.ContainsKey($key)) {
      $keyToMutations[$key] = [System.Collections.Generic.List[object]]::new()
    }
    $keyToMutations[$key].Add($mutation)
  }

  if (-not (Test-HasNonEmptyField -Record $mutation -Field "triggerKind")) {
    Add-Issue $issues "$subject must carry a non-empty triggerKind."
  }
  elseif ($allowedTriggerKinds -notcontains [string]$mutation.triggerKind) {
    Add-Issue $issues "$subject triggerKind must be one of connector, schedule, agent, found: $($mutation.triggerKind)."
  }
  elseif (-not (($mutation.PSObject.Properties.Name -contains "isDuplicate" -and $mutation.isDuplicate -is [bool] -and $mutation.isDuplicate) -or ($mutation.PSObject.Properties.Name -contains "unverifiableKey" -and $mutation.unverifiableKey -is [bool] -and $mutation.unverifiableKey))) {
    if ($nonDuplicateTriggerKinds.ContainsKey([string]$mutation.triggerKind)) {
      Add-Issue $issues "Accepted mutation for triggerKind '$($mutation.triggerKind)' must appear exactly once; a second accepted attempt would weaken the duplicate-key story."
    }
    else {
      $nonDuplicateTriggerKinds[[string]$mutation.triggerKind] = $true
    }
  }

  if ($actorTypes -notcontains [string]$mutation.actorType) {
    Add-Issue $issues "$subject actorType must use manifest com_actortype vocabulary, found: $($mutation.actorType)."
  }
  foreach ($field in @("actorId", "payloadIntent")) {
    if (-not (Test-HasNonEmptyField -Record $mutation -Field $field)) {
      Add-Issue $issues "$subject must carry a non-empty ${field}."
    }
  }
  if (-not (Test-HasNonEmptyField -Record $mutation -Field "outcome")) {
    Add-Issue $issues "$subject must carry a non-empty outcome."
  }

  $isDuplicate = $false
  if ($mutation.PSObject.Properties.Name -contains "isDuplicate" -and $mutation.isDuplicate -is [bool]) {
    $isDuplicate = $mutation.isDuplicate
  }
  if ($isDuplicate) {
    if (-not (Test-HasNonEmptyField -Record $mutation -Field "isDuplicateOf") -or -not $mutationIds.ContainsKey([string]$mutation.isDuplicateOf)) {
      Add-Issue $issues "$subject (isDuplicate=true) must reference an existing original mutation via isDuplicateOf, found: $($mutation.isDuplicateOf)."
    }
    else {
      $original = $mutationIds[[string]$mutation.isDuplicateOf]
      if ([string]$original.idempotencyKey -ne [string]$mutation.idempotencyKey) {
        Add-Issue $issues "$subject must reuse the original mutation's idempotency key ($($original.idempotencyKey)), found: $($mutation.idempotencyKey)."
      }
    }
    if (-not (Test-HasNonEmptyField -Record $mutation -Field "duplicateOutcome") -or $allowedDuplicateOutcomes -notcontains [string]$mutation.duplicateOutcome) {
      Add-Issue $issues "$subject duplicateOutcome must be one of no_op, rejected, flagged, found: $($mutation.duplicateOutcome)."
    }
    if (Test-HasNonEmptyField -Record $mutation -Field "producesWorkItem") {
      Add-Issue $issues "$subject (isDuplicate=true) must NOT mint a second Work Item (producesWorkItem must be null/absent), found: $($mutation.producesWorkItem)."
    }
    if (-not (Test-HasNonEmptyField -Record $mutation -Field "producesReceipt")) {
      Add-Issue $issues "$subject must produce exactly one no-op/rejection receipt (producesReceipt)."
    }
    if (-not (Test-HasNonEmptyField -Record $mutation -Field "referencesOriginalReceipt")) {
      Add-Issue $issues "$subject must reference the original attempt's receipt (referencesOriginalReceipt)."
    }
    if (-not (Test-HasNonEmptyField -Record $mutation -Field "referencesOriginalAttempt")) {
      Add-Issue $issues "$subject must reference the original attempt (referencesOriginalAttempt)."
    }
  }

  $unverifiable = $false
  if ($mutation.PSObject.Properties.Name -contains "unverifiableKey" -and $mutation.unverifiableKey -is [bool]) {
    $unverifiable = $mutation.unverifiableKey
  }
  if ($unverifiable) {
    if (@("rejected", "failed") -notcontains [string]$mutation.outcome) {
      Add-Issue $issues "$subject (unverifiableKey=true) outcome must be rejected or failed, found: $($mutation.outcome)."
    }
    if (Test-HasNonEmptyField -Record $mutation -Field "producesWorkItem") {
      Add-Issue $issues "$subject (unverifiableKey=true) must NOT mint a Work Item, found: $($mutation.producesWorkItem)."
    }
    if (-not (Test-HasNonEmptyField -Record $mutation -Field "producesReceipt")) {
      Add-Issue $issues "$subject (unverifiableKey=true) must produce a failure/policy-denial receipt (producesReceipt)."
    }
    if (-not (Test-HasNonEmptyField -Record $mutation -Field "flagsWorkItemForHumanReview")) {
      Add-Issue $issues "$subject (unverifiableKey=true) must flag a Work Item for human review (flagsWorkItemForHumanReview)."
    }
    if (-not (Test-HasNonEmptyField -Record $mutation -Field "unverifiableReason")) {
      Add-Issue $issues "$subject (unverifiableKey=true) must carry a non-empty unverifiableReason."
    }
  }
}

foreach ($kind in $declaredTriggerKinds) {
  if (-not $nonDuplicateTriggerKinds.ContainsKey($kind)) {
    Add-Issue $issues "Idempotency run must include an accepted (non-duplicate) mutation for triggerKind '$kind'."
  }
}

# Idempotency keys must be unique across mutations EXCEPT exactly one declared duplicate pair.
$dupKeyPairs = 0
foreach ($key in @($mutationKeys.Keys)) {
  if ($mutationKeys[$key] -eq 1) {
    continue
  }
  if ($mutationKeys[$key] -eq 2) {
    $pair = @($keyToMutations[$key])
    $dupCount = @($pair | Where-Object { $_.PSObject.Properties.Name -contains "isDuplicate" -and $_.isDuplicate -is [bool] -and $_.isDuplicate }).Count
    $origCount = @($pair | Where-Object { -not ($_.PSObject.Properties.Name -contains "isDuplicate" -and $_.isDuplicate -is [bool] -and $_.isDuplicate) }).Count
    if ($dupCount -eq 1 -and $origCount -eq 1) {
      $dupKeyPairs += 1
      continue
    }
  }
  Add-Issue $issues "Mutation idempotency key '$key' is used $($mutationKeys[$key]) time(s); keys must be unique except for exactly one declared duplicate pair (one original + one isDuplicate=true)."
}
if ($dupKeyPairs -ne 1) {
  Add-Issue $issues "Idempotency run must declare exactly one duplicate key pair (a key shared by one original mutation and one isDuplicate=true mutation); found $dupKeyPairs."
}

# Sibling idempotency-key collision: this slice's mutation keys must not collide with sibling receipt keys.
foreach ($key in @($mutationKeys.Keys | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })) {
  if ($siblingIdempotencyKeys -contains $key) {
    Add-Issue $issues "Mutation idempotency key '$key' collides with a sibling slice receipt idempotency key; keys must be unique across all slices."
  }
}

# Work Items
$workItemTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilworkitem" } | Select-Object -First 1
$manifestRequiredWorkItemFields = @(@($workItemTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredWorkItemFields.Count -eq 0) {
  Add-Issue $issues "No required Work Item columns could be derived from manifest com_councilworkitem; Work Item required-field checks would silently no-op."
}
$workItems = @($run.proposedWorkItems | Where-Object { $null -ne $_ })
$sliceWorkItemIds = @{}
foreach ($workItem in $workItems) {
  $workItemId = [string]$workItem.com_council_work_item_id
  $subject = "Work Item $workItemId"
  foreach ($field in $manifestRequiredWorkItemFields) {
    if (-not (Test-HasNonEmptyField -Record $workItem -Field $field)) {
      Add-Issue $issues "$subject missing required manifest Work Item field: $field."
    }
  }
  if ([string]::IsNullOrWhiteSpace($workItemId)) {
    Add-Issue $issues "Work Item must declare com_council_work_item_id."
  }
  else {
    if ($workItemId -notmatch "^CWI-LOCAL-IDEMPOTENT-") {
      Add-Issue $issues "$subject must use fresh CWI-LOCAL-IDEMPOTENT-* identity."
    }
    if ($sliceWorkItemIds.ContainsKey($workItemId)) {
      Add-Issue $issues "Duplicate Work Item id in slice: $workItemId."
    }
    else {
      $sliceWorkItemIds[$workItemId] = $true
    }
    if ($siblingWorkItemIds -contains $workItemId) {
      Add-Issue $issues "$subject collides with a Work Item id from a sibling slice or demo evidence."
    }
  }
  if ($workItemTypes -notcontains [string]$workItem.com_type) {
    Add-Issue $issues "$subject com_type is not in manifest com_workitemtype vocabulary, found: $($workItem.com_type)."
  }
  if ($workItemStateGroups -notcontains [string]$workItem.com_state_group) {
    Add-Issue $issues "$subject com_state_group is not in manifest com_workitemstategroup vocabulary, found: $($workItem.com_state_group)."
  }
  if ($riskClasses -notcontains [string]$workItem.com_risk_class) {
    Add-Issue $issues "$subject com_risk_class is not in manifest com_riskclass vocabulary, found: $($workItem.com_risk_class)."
  }
  if ((Test-HasNonEmptyField -Record $workItem -Field "com_primary_source_record")) {
    $primarySource = [string]$workItem.com_primary_source_record
    if ($knownPriorSourceIds -notcontains $primarySource) {
      Add-Issue $issues "$subject com_primary_source_record must reference a known Source Record from a sibling slice, found: $primarySource."
    }
  }
  if ($workItem.com_approval_required -isnot [bool]) {
    Add-Issue $issues "$subject com_approval_required must be a strict boolean."
  }
  if (Test-HasNonEmptyField -Record $workItem -Field "com_owner_candidate_confidence") {
    Test-ConfidenceInRange -Issues $issues -Record $workItem -Field "com_owner_candidate_confidence" -Subject $subject
  }
}

# Receipts
$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique

$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 5) {
  Add-Issue $issues "Slice must include at least five receipts (three accepted, one duplicate no-op, one unverifiable denial), found $($receipts.Count)."
}
$sliceReceiptIds = @{}
$seenReceiptIdempotencyKeys = @{}
$receiptByMutationId = @{}
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
    if ($receiptId -notmatch "^CR-LOCAL-IDEMPOTENT-") {
      Add-Issue $issues "$subject must use Council-level CR-LOCAL-IDEMPOTENT-* identity."
    }
    if ($sliceReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "Duplicate receipt ID in slice: $receiptId."
    }
    else {
      $sliceReceiptIds[$receiptId] = $receipt
    }
    if ($siblingReceiptIds -contains $receiptId) {
      Add-Issue $issues "$subject collides with a receipt ID from a sibling slice or demo evidence."
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

  $receiptKey = [string]$receipt.com_idempotency_key
  if (-not [string]::IsNullOrWhiteSpace($receiptKey)) {
    if ($seenReceiptIdempotencyKeys.ContainsKey($receiptKey)) {
      Add-Issue $issues "$subject reuses an idempotency key already used by another receipt in this slice: $receiptKey. Receipt idempotency keys are alternate keys and must be unique (append-only)."
    }
    else {
      $seenReceiptIdempotencyKeys[$receiptKey] = $true
    }
    if ($siblingIdempotencyKeys -contains $receiptKey) {
      Add-Issue $issues "$subject idempotency key collides with a sibling slice receipt idempotency key: $receiptKey."
    }
  }

  if ($receipt.com_append_only_locked -isnot [bool] -or -not $receipt.com_append_only_locked) {
    Add-Issue $issues "$subject com_append_only_locked must be strict boolean true (receipts are append-only)."
  }
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 2.4 receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 2.4 receipts are local contract evidence only."
      }
    }
  }
}

foreach ($expectedReceiptId in @("CR-LOCAL-IDEMPOTENT-001", "CR-LOCAL-IDEMPOTENT-002", "CR-LOCAL-IDEMPOTENT-003", "CR-LOCAL-IDEMPOTENT-DUP-001", "CR-LOCAL-IDEMPOTENT-FAIL-001")) {
  if (-not $sliceReceiptIds.ContainsKey($expectedReceiptId)) {
    Add-Issue $issues "Slice must include receipt $expectedReceiptId."
  }
}

# Duplicate-handling receipt specifics.
$dupReceipt = $receipts | Where-Object { $_.com_receipt_id -eq "CR-LOCAL-IDEMPOTENT-DUP-001" } | Select-Object -First 1
if ($dupReceipt) {
  if ([string]$dupReceipt.com_result -ne "no_op") {
    Add-Issue $issues "Receipt CR-LOCAL-IDEMPOTENT-DUP-001 com_result must be no_op for a duplicate-key handling, found: $($dupReceipt.com_result)."
  }
  $dupMutation = $mutations | Where-Object { [string]$_.producesReceipt -eq "CR-LOCAL-IDEMPOTENT-DUP-001" } | Select-Object -First 1
  if (-not $dupMutation) {
    Add-Issue $issues "Receipt CR-LOCAL-IDEMPOTENT-DUP-001 must be produced by a mutation declared as isDuplicate=true."
  }
  elseif (-not ($dupMutation.PSObject.Properties.Name -contains "isDuplicate" -and $dupMutation.isDuplicate -is [bool] -and $dupMutation.isDuplicate)) {
    Add-Issue $issues "Receipt CR-LOCAL-IDEMPOTENT-DUP-001 must be produced by a mutation with isDuplicate=true."
  }
  else {
    $originalReceiptId = [string]$dupMutation.referencesOriginalReceipt
    if (-not $sliceReceiptIds.ContainsKey($originalReceiptId)) {
      Add-Issue $issues "Receipt CR-LOCAL-IDEMPOTENT-DUP-001 must reference an original receipt that exists in this slice, found: $originalReceiptId."
    }
    $originalAttemptId = [string]$dupMutation.referencesOriginalAttempt
    if (-not $mutationIds.ContainsKey($originalAttemptId)) {
      Add-Issue $issues "Receipt CR-LOCAL-IDEMPOTENT-DUP-001 must reference an original attempt that exists in this slice, found: $originalAttemptId."
    }
    $dupEvidenceRefs = [string]$dupReceipt.com_evidence_refs
    if ($dupEvidenceRefs -notmatch [regex]::Escape($originalReceiptId)) {
      Add-Issue $issues "Receipt CR-LOCAL-IDEMPOTENT-DUP-001 com_evidence_refs must reference the original receipt $originalReceiptId."
    }
  }
  # Exactly one receipt minted by the duplicate handling (no second payload receipt).
  $dupProducedReceipts = @($mutations | Where-Object { $_.PSObject.Properties.Name -contains "isDuplicate" -and $_.isDuplicate -is [bool] -and $_.isDuplicate } | ForEach-Object { [string]$_.producesReceipt } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
  if ($dupProducedReceipts.Count -ne 1) {
    Add-Issue $issues "Duplicate handling must mint exactly one no-op/rejection receipt, found $($dupProducedReceipts.Count)."
  }
}

# Unverifiable-key receipt specifics.
$failReceipt = $receipts | Where-Object { $_.com_receipt_id -eq "CR-LOCAL-IDEMPOTENT-FAIL-001" } | Select-Object -First 1
if ($failReceipt) {
  if (@("policy_denied", "failed") -notcontains [string]$failReceipt.com_verb) {
    Add-Issue $issues "Receipt CR-LOCAL-IDEMPOTENT-FAIL-001 verb must be policy_denied or failed, found: $($failReceipt.com_verb)."
  }
  if (@("rejected", "failed") -notcontains [string]$failReceipt.com_result) {
    Add-Issue $issues "Receipt CR-LOCAL-IDEMPOTENT-FAIL-001 result must be rejected or failed, found: $($failReceipt.com_result)."
  }
  if (-not (Test-HasNonEmptyField -Record $failReceipt -Field "com_failure_code")) {
    Add-Issue $issues "Receipt CR-LOCAL-IDEMPOTENT-FAIL-001 must carry a non-empty com_failure_code for the unverifiable-key denial."
  }
}

# Work Items flagged for human review.
$flaggedItems = @($run.workItemsFlaggedForHumanReview | Where-Object { $null -ne $_ })
if ($flaggedItems.Count -lt 1) {
  Add-Issue $issues "Slice must flag at least one Work Item for human review (the unverifiable-key scenario)."
}
$flaggedWorkItemIds = @()
foreach ($flag in $flaggedItems) {
  $flagWorkItemId = [string]$flag.workItem
  $subject = "Human-review flag $flagWorkItemId"
  $flaggedWorkItemIds += $flagWorkItemId
  if ([string]::IsNullOrWhiteSpace($flagWorkItemId) -or -not $sliceWorkItemIds.ContainsKey($flagWorkItemId)) {
    Add-Issue $issues "$subject must reference a Work Item that exists in this slice, found: $flagWorkItemId."
  }
  if ($flag.humanReviewRequired -isnot [bool] -or -not $flag.humanReviewRequired) {
    Add-Issue $issues "$subject humanReviewRequired must be strict boolean true."
  }
  if (-not (Test-HasNonEmptyField -Record $flag -Field "flaggedBy") -or -not $sliceReceiptIds.ContainsKey([string]$flag.flaggedBy)) {
    Add-Issue $issues "$subject must name a slice receipt that backs the flag (flaggedBy), found: $($flag.flaggedBy)."
  }
  else {
    $flagReceipt = $sliceReceiptIds[[string]$flag.flaggedBy]
    if (@("policy_denied", "failed") -notcontains [string]$flagReceipt.com_verb) {
      Add-Issue $issues "$subject flaggedBy receipt must be a failure/policy-denial receipt, found verb: $($flagReceipt.com_verb)."
    }
  }
  if (-not (Test-HasNonEmptyField -Record $flag -Field "reason")) {
    Add-Issue $issues "$subject must carry a non-empty reason."
  }
  if (-not (Test-HasNonEmptyField -Record $flag -Field "flagMechanism")) {
    Add-Issue $issues "$subject must carry a non-empty flagMechanism."
  }
  if ($flag.PSObject.Properties.Name -contains "stateGroupChangedInThisSlice") {
    if ($flag.stateGroupChangedInThisSlice -isnot [bool] -or $flag.stateGroupChangedInThisSlice) {
      Add-Issue $issues "$subject stateGroupChangedInThisSlice must be strict boolean false; Work Item state changes are receipt-gated."
    }
  }
}
if ($flaggedWorkItemIds -notcontains "CWI-LOCAL-IDEMPOTENT-AGENT-001") {
  Add-Issue $issues "The unverifiable-key scenario must flag CWI-LOCAL-IDEMPOTENT-AGENT-001 for human review."
}

# Deferred mutations: every accepted mutation's live Work Item creation must be a deferred entry naming a receipt gate.
$deferredMutations = @($run.deferredMutations | Where-Object { $null -ne $_ })
$acceptedMutations = @($mutations | Where-Object {
  -not ($_.PSObject.Properties.Name -contains "isDuplicate" -and $_.isDuplicate -is [bool] -and $_.isDuplicate) -and
  -not ($_.PSObject.Properties.Name -contains "unverifiableKey" -and $_.unverifiableKey -is [bool] -and $_.unverifiableKey)
})
foreach ($deferred in $deferredMutations) {
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "mutation")) {
    Add-Issue $issues "Deferred mutation entry must name its mutation."
  }
  elseif (-not $mutationIds.ContainsKey([string]$deferred.mutation)) {
    Add-Issue $issues "Deferred mutation entry references an unknown mutation: $($deferred.mutation)."
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred mutation entry must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred mutation entry for $($deferred.mutation) must state that the live mutation is receipt-gated."
  }
}
foreach ($accepted in $acceptedMutations) {
  $acceptedId = [string]$accepted.mutationId
  $deferred = $deferredMutations | Where-Object { [string]$_.mutation -eq $acceptedId } | Select-Object -First 1
  if (-not $deferred) {
    Add-Issue $issues "Missing deferred mutation entry for accepted mutation $acceptedId; live Work Item creation must be receipt-gated."
  }
}

# Accepted mutations produce receipts whose idempotency key matches the mutation key (append-only binding).
foreach ($accepted in $acceptedMutations) {
  $acceptedId = [string]$accepted.mutationId
  $receiptId = [string]$accepted.producesReceipt
  if (-not $sliceReceiptIds.ContainsKey($receiptId)) {
    Add-Issue $issues "Accepted mutation $acceptedId producesReceipt must reference a receipt that exists in this slice, found: $receiptId."
    continue
  }
  $prodReceipt = $sliceReceiptIds[$receiptId]
  if ([string]$prodReceipt.com_idempotency_key -ne [string]$accepted.idempotencyKey) {
    Add-Issue $issues "Accepted mutation $acceptedId receipt $receiptId com_idempotency_key must match the mutation's idempotency key ($($accepted.idempotencyKey)), found: $($prodReceipt.com_idempotency_key)."
  }
  if ([string]$prodReceipt.com_result -ne "accepted") {
    Add-Issue $issues "Accepted mutation $acceptedId receipt $receiptId com_result must be accepted, found: $($prodReceipt.com_result)."
  }
  if (Test-HasNonEmptyField -Record $accepted -Field "producesWorkItem") {
    $prodWorkItemId = [string]$accepted.producesWorkItem
    if (-not $sliceWorkItemIds.ContainsKey($prodWorkItemId)) {
      Add-Issue $issues "Accepted mutation $acceptedId producesWorkItem must reference a Work Item that exists in this slice, found: $prodWorkItemId."
    }
  }
}

# Acceptance mapping for AC 1, 2, 3.
foreach ($criterion in @(1, 2, 3)) {
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

if ($issues.Count -gt 0) {
  Write-Host "Idempotent mutations slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Idempotent mutations slice validation succeeded."
Write-Host "Mutations: $($mutations.Count)"
Write-Host "Work Items: $($workItems.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Work Items flagged for human review: $($flaggedItems.Count)"
Write-Host "Deferred mutations: $($deferredMutations.Count)"
Write-Host "IDEMPOTENT_MUTATIONS_SLICE_VALIDATE_OK"
