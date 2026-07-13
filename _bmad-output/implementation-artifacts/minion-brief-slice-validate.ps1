param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$BriefSlicePath = "$PSScriptRoot\minion-brief-slice.json",
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
    Write-Host "Minion brief slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

function Invoke-CollectSiblingIds {
  # Recursively walk a parsed sibling slice JSON and harvest every canonical
  # Council id / idempotency key / runId by property name, plus the demo-evidence
  # workItemIds/receiptIds arrays. This is the single source of truth for
  # cross-slice collision checks so they cover ALL co-located slices (Story hard
  # rule: ids unique across ALL slices), not just the named 1.1-1.5 siblings.
  param(
    [Parameter(Mandatory = $false)][AllowNull()]$Node,
    [Parameter(Mandatory = $true)][hashtable]$WorkItems,
    [Parameter(Mandatory = $true)][hashtable]$Receipts,
    [Parameter(Mandatory = $true)][hashtable]$Keys,
    [Parameter(Mandatory = $true)][hashtable]$SourceRecords,
    [Parameter(Mandatory = $true)][hashtable]$Briefs,
    [Parameter(Mandatory = $true)][hashtable]$RunIds
  )

  if ($null -eq $Node) { return }
  if ($Node -is [System.Collections.IList]) {
    foreach ($item in $Node) {
      Invoke-CollectSiblingIds -Node $item -WorkItems $WorkItems -Receipts $Receipts -Keys $Keys -SourceRecords $SourceRecords -Briefs $Briefs -RunIds $RunIds
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
        "com_council_brief_id" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $Briefs[$id] = $true }
          break
        }
        "runId" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $RunIds[$id] = $true }
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
          Invoke-CollectSiblingIds -Node $prop.Value -WorkItems $WorkItems -Receipts $Receipts -Keys $Keys -SourceRecords $SourceRecords -Briefs $Briefs -RunIds $RunIds
        }
      }
    }
  }
}

foreach ($path in @($ManifestPath, $BriefSlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $Story15DriftPath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required minion brief validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$brief = Read-JsonInput -Path $BriefSlicePath
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

if ($receiptVerbs -notcontains "reviewed") {
  Add-Issue $issues "Manifest com_receiptverb is missing the brief-generation verb: reviewed."
}

# ---------------------------------------------------------------------------
# Slice identity and guards
# ---------------------------------------------------------------------------

if ($brief.storyKey -ne "3-1-create-a-minion-brief-snapshot") {
  Add-Issue $issues "Brief slice storyKey must be 3-1-create-a-minion-brief-snapshot."
}
if ([string]$brief.status -notmatch "^local-contract") {
  Add-Issue $issues "Brief slice status must declare local contract evidence, found: $($brief.status)."
}

$requiredGuards = @(
  "noTenantWrites",
  "noOutboundAction",
  "noApprovalExecution",
  "requiresExplicitHumanApprovalForExecution",
  "receiptsAreLocalContractEvidenceOnly",
  "briefsAreImmutableSnapshots",
  "briefsAreProjectionsNotSourceOfTruth",
  "noLiveBriefMutation",
  "briefRefreshCreatesNewSnapshotNeverRewritesPrior",
  "sourceOfTruthIsWorkItemsAndReceiptsNotBriefs"
)
foreach ($guard in $requiredGuards) {
  if (-not ($brief.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Brief slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($brief.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Brief guard must be boolean true: $($guardProperty.Name)."
  }
}

# ---------------------------------------------------------------------------
# Collect known IDs from sibling slices for cross-slice resolution
# ---------------------------------------------------------------------------

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
}

# Superseding source from story 1-5
$story15Supersessions = @($story15Drift.driftRun.supersessions | Where-Object { $null -ne $_ })
foreach ($supersession in $story15Supersessions) {
  $supersedingId = [string]$supersession.supersedingRecord.com_council_source_record_id
  if (-not [string]::IsNullOrWhiteSpace($supersedingId) -and -not $priorSourcesById.ContainsKey($supersedingId)) {
    $priorSourcesById[$supersedingId] = $supersession.supersedingRecord
  }
}
$knownSourceIds = @($priorSourcesById.Keys)

$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$knownWorkItemIds = @(($story13Items + $story14Items) | ForEach-Object { [string]$_.com_council_work_item_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$demoWorkItemIds = @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$allKnownWorkItemIds = @($knownWorkItemIds + $demoWorkItemIds)

# Story 1-5 receipts
$story15Receipts = @($story15Drift.driftRun.receipts | Where-Object { $null -ne $_ })
$story15ReceiptIds = @($story15Receipts | ForEach-Object { [string]$_.com_receipt_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$demoReceiptIds = @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$allKnownReceiptIds = @($story15ReceiptIds + $demoReceiptIds)

# Story 1-5 work items referenced in drift (flagged/unaffected)
$story15FlaggedIds = @($story15Drift.driftRun.workItemsFlaggedForReview | ForEach-Object { [string]$_.workItem } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$story15UnaffectedIds = @($story15Drift.driftRun.workItemsUnaffected | ForEach-Object { [string]$_.workItem } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$allKnownWorkItemIds = @($allKnownWorkItemIds + $story15FlaggedIds + $story15UnaffectedIds) | Sort-Object -Unique

foreach ($sliceLoad in @(
    @{ Name = "manual-source-record-slice sampleRecords"; Count = $manualSources.Count },
    @{ Name = "outlook-source-reference-slice sampleRecords"; Count = $outlookSources.Count },
    @{ Name = "zero-multi-item-extraction-slice embeddedSampleSourceRecords"; Count = $story14EmbeddedSources.Count },
    @{ Name = "proposed-work-item-extraction-slice proposedWorkItems"; Count = $story13Items.Count },
    @{ Name = "zero-multi-item-extraction-slice proposedWorkItems"; Count = $story14Items.Count },
    @{ Name = "source-drift-supersession-slice receipts"; Count = $story15Receipts.Count },
    @{ Name = "state-transition-demo-evidence receiptIds"; Count = $demoReceiptIds.Count }
  )) {
  if ($sliceLoad.Count -eq 0) {
    Add-Issue $issues "No records loaded from $($sliceLoad.Name); its cross-slice checks would silently no-op."
  }
}

# ---------------------------------------------------------------------------
# Generic all-slice id harvest: walk EVERY sibling slice JSON in this folder so
# collision tripwires cover ALL co-located slices (Story hard rule: ids unique
# across ALL slices), not only the named 1.1-1.5 + demo siblings. This makes the
# CB-LOCAL-* / CR-LOCAL-* / idempotency-key / runId collision checks genuinely
# live: a rename into any co-located slice namespace (including epic-2 slices
# receipt-backed-state-changes, work-item-execution-shell, idempotent-mutations,
# delegation-support, failure-policy-denial, handoff-drafts, approval-boundaries,
# auto-creation-policy) will fire here. Hashtables make membership O(1).
# ---------------------------------------------------------------------------

$allSliceWorkItemIds = @{}
$allSliceReceiptIds = @{}
$allSliceIdempotencyKeys = @{}
$allSliceSourceIds = @{}
$allSliceBriefIds = @{}
$allSliceRunIds = @{}
$selfSliceBasename = (Split-Path -Leaf $BriefSlicePath)
$siblingSliceFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.json" -File |
  Where-Object { $_.Name -ne "dataverse-mvp-schema-manifest.json" -and $_.Name -ne $selfSliceBasename } |
  ForEach-Object { $_.FullName })
if ($siblingSliceFiles.Count -eq 0) {
  Add-Issue $issues "No sibling slice JSON files found in $PSScriptRoot; all-slice id-collision checks would silently no-op."
}
foreach ($siblingFile in $siblingSliceFiles) {
  $siblingJson = Read-JsonInput -Path $siblingFile
  Invoke-CollectSiblingIds -Node $siblingJson -WorkItems $allSliceWorkItemIds -Receipts $allSliceReceiptIds -Keys $allSliceIdempotencyKeys -SourceRecords $allSliceSourceIds -Briefs $allSliceBriefIds -RunIds $allSliceRunIds
}

if ($allSliceWorkItemIds.Count -eq 0) {
  Add-Issue $issues "No CWI-* ids harvested from sibling slices; Work Item collision checks would silently no-op."
}
if ($allSliceReceiptIds.Count -eq 0) {
  Add-Issue $issues "No CR-* ids harvested from sibling slices; receipt collision checks would silently no-op."
}
if ($allSliceSourceIds.Count -eq 0) {
  Add-Issue $issues "No CSR-* ids harvested from sibling slices; source-record collision checks would silently no-op."
}

# Resolution sets: the named epic-2 siblings are authoritative for "references a
# real epic-2 id", unioned with the broad harvest so a referenced id resolves if
# it appears in ANY co-located slice (superset, conservative).
$resolvableWorkItemIds = @{}
foreach ($id in @($allKnownWorkItemIds + @($allSliceWorkItemIds.Keys))) { if (-not [string]::IsNullOrWhiteSpace($id)) { $resolvableWorkItemIds[$id] = $true } }
$resolvableReceiptIds = @{}
foreach ($id in @($allKnownReceiptIds + @($allSliceReceiptIds.Keys))) { if (-not [string]::IsNullOrWhiteSpace($id)) { $resolvableReceiptIds[$id] = $true } }
$resolvableSourceIds = @{}
foreach ($id in @($knownSourceIds + @($allSliceSourceIds.Keys))) { if (-not [string]::IsNullOrWhiteSpace($id)) { $resolvableSourceIds[$id] = $true } }

# ---------------------------------------------------------------------------
# Brief run structure
# ---------------------------------------------------------------------------

$run = $brief.briefRun
if ($null -eq $run) {
  Add-Issue $issues "Brief slice must carry a briefRun block."
  Write-Host "Minion brief slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Brief run must declare a runId."
}
elseif (@([string]$story13Extraction.extractionRun.runId, [string]$story14Extraction.extractionRun.runId, [string]$story15Drift.driftRun.runId) -contains [string]$run.runId) {
  Add-Issue $issues "Brief run must use a new local runId, not a sibling-slice runId: $($run.runId)."
}
elseif ($allSliceRunIds.ContainsKey([string]$run.runId)) {
  Add-Issue $issues "Brief run runId collides with a runId harvested from a sibling slice: $($run.runId); new run ids must be unique across ALL slices."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Brief run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Brief run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Brief run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("proposed-work-item-extraction-slice.json", "zero-multi-item-extraction-slice.json", "source-drift-supersession-slice.json", "state-transition-demo-evidence.json")) {
  if (@($run.inputQueueFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Brief run must reference $inputSlice as an input."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Brief run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("briefsAreProjectionsOverWorkItemsAndReceipts", "briefsNeverMutateWorkItemsOrReceipts", "briefRefreshCreatesNewSnapshotNeverRewritesPrior", "sourceOfTruthIsWorkItemsAndReceiptsNotBriefs", "briefGenerationReceiptBacked", "liveBriefCreationGatedToEpic2Story23")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Brief run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Brief run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# ---------------------------------------------------------------------------
# Snapshots — all eight sections, projection guards, frozen hash
# ---------------------------------------------------------------------------

$snapshots = @($run.snapshots | Where-Object { $null -ne $_ })
if ($snapshots.Count -lt 2) {
  Add-Issue $issues "Brief slice must include at least two snapshots (original and refreshed)."
}

$requiredEightSections = @(
  "priorityWork",
  "decisionsNeeded",
  "delegationsReady",
  "risksIfIgnored",
  "blockers",
  "recentReceipts",
  "memoryCandidates",
  "projectionDisclaimer"
)

$sliceBriefIds = @{}
$seenFrozenHashes = @{}
$referencedWorkItemIds = @()
$referencedReceiptIds = @()
$referencedSourceIds = @()

foreach ($snapshot in $snapshots) {
  $briefId = [string]$snapshot.com_council_brief_id
  $subject = "Snapshot $briefId"

  foreach ($field in @("com_name", "com_council_brief_id", "com_brief_date", "evidenceStatus", "isProjection", "sourceOfTruth", "sections")) {
    if (-not (Test-HasNonEmptyField -Record $snapshot -Field $field)) {
      if ($field -eq "isProjection" -or $field -eq "sourceOfTruth" -or $field -eq "sections") {
        Add-Issue $issues "$subject must carry field: $field."
      }
      else {
        Add-Issue $issues "$subject must carry a non-empty ${field}."
      }
    }
  }

  if ([string]::IsNullOrWhiteSpace($briefId)) {
    continue
  }

  if ($briefId -notmatch "^CB-LOCAL-") {
    Add-Issue $issues "$subject must use Council-level CB-LOCAL-* identity."
  }
  if ($sliceBriefIds.ContainsKey($briefId)) {
    Add-Issue $issues "Duplicate brief ID in slice: $briefId."
  }
  else {
    $sliceBriefIds[$briefId] = $true
  }

  Test-IsoTimestamp -Issues $issues -Record $snapshot -Field "com_brief_date" -Subject $subject | Out-Null

  # Projection guards
  if ($snapshot.isProjection -isnot [bool] -or -not $snapshot.isProjection) {
    Add-Issue $issues "$subject isProjection must be strict boolean true."
  }
  if ([string]$snapshot.sourceOfTruth -ne "work-items+receipts") {
    Add-Issue $issues "$subject sourceOfTruth must be exactly \"work-items+receipts\", found: $($snapshot.sourceOfTruth)."
  }
  if ([string]$snapshot.evidenceStatus -ne "local_contract_not_tenant_verified") {
    Add-Issue $issues "$subject evidenceStatus must be local_contract_not_tenant_verified, found: $($snapshot.evidenceStatus)."
  }

  # All eight sections present and non-empty-or-declared
  $sections = $snapshot.sections
  if ($null -eq $sections) {
    Add-Issue $issues "$subject must carry a sections block."
    continue
  }
  foreach ($sectionName in $requiredEightSections) {
    if (-not ($sections.PSObject.Properties.Name -contains $sectionName)) {
      Add-Issue $issues "$subject must declare section: $sectionName."
    }
    else {
      $sectionValue = $sections.$sectionName
      if ($sectionName -eq "projectionDisclaimer") {
        if (-not (Test-HasNonEmptyField -Record $sections -Field $sectionName)) {
          Add-Issue $issues "$sectionName must be non-empty."
        }
      }
      else {
        $sectionArray = @($sectionValue | Where-Object { $null -ne $_ })
        if ($sectionArray.Count -eq 0) {
          Add-Issue $issues "$subject section $sectionName must be non-empty (at least one entry)."
        }
      }
    }
  }

  # Collect referenced IDs from sections for cross-slice resolution
  foreach ($sectionName in @("priorityWork", "decisionsNeeded", "delegationsReady", "risksIfIgnored", "blockers")) {
    if ($sections.PSObject.Properties.Name -contains $sectionName) {
      foreach ($entry in @($sections.$sectionName | Where-Object { $null -ne $_ })) {
        if (Test-HasNonEmptyField -Record $entry -Field "workItem") {
          $referencedWorkItemIds += [string]$entry.workItem
        }
        if (Test-HasNonEmptyField -Record $entry -Field "sourceRecord") {
          $referencedSourceIds += [string]$entry.sourceRecord
        }
      }
    }
  }
  if ($sections.PSObject.Properties.Name -contains "recentReceipts") {
    foreach ($entry in @($sections.recentReceipts | Where-Object { $null -ne $_ })) {
      if (Test-HasNonEmptyField -Record $entry -Field "receipt") {
        $referencedReceiptIds += [string]$entry.receipt
      }
    }
  }
  if ($sections.PSObject.Properties.Name -contains "memoryCandidates") {
    foreach ($entry in @($sections.memoryCandidates | Where-Object { $null -ne $_ })) {
      if (Test-HasNonEmptyField -Record $entry -Field "sourceRecord") {
        $referencedSourceIds += [string]$entry.sourceRecord
      }
    }
  }

  # Frozen projection hash — byte-stability recheck
  if (-not (Test-HasNonEmptyField -Record $snapshot -Field "frozenProjectionJson")) {
    Add-Issue $issues "$subject must carry frozenProjectionJson for byte-stability recheck."
  }
  elseif (-not (Test-HasNonEmptyField -Record $snapshot -Field "frozenProjectionHash")) {
    Add-Issue $issues "$subject must carry frozenProjectionHash for byte-stability recheck."
  }
  else {
    $frozenJson = [string]$snapshot.frozenProjectionJson
    $frozenHash = [string]$snapshot.frozenProjectionHash
    if ($frozenHash -notmatch "^sha256:[0-9a-f]{64}$") {
      Add-Issue $issues "$subject frozenProjectionHash must use sha256:<64 hex> format, found: $frozenHash."
    }
    else {
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($frozenJson)
      $sha = [System.Security.Cryptography.SHA256]::Create()
      $hashBytes = $sha.ComputeHash($bytes)
      $recomputed = "sha256:" + [BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
      if ($recomputed -ne $frozenHash) {
        Add-Issue $issues "$subject frozenProjectionHash must match recomputed SHA-256 of frozenProjectionJson; expected $frozenHash, recomputed $recomputed. The original Brief is not byte-stable."
      }
    }

    # Verify frozenProjectionJson matches the inline sections/isProjection/sourceOfTruth
    try {
      $frozenObj = $frozenJson | ConvertFrom-Json
      $inlineObj = $snapshot | Select-Object -Property isProjection, sourceOfTruth, sections
      $frozenReserialized = $frozenObj | ConvertTo-Json -Depth 20 -Compress
      $inlineReserialized = $inlineObj | ConvertTo-Json -Depth 20 -Compress
      if ($frozenReserialized -ne $inlineReserialized) {
        Add-Issue $issues "$subject frozenProjectionJson must match inline isProjection/sourceOfTruth/sections; the inline content was changed after the hash was recorded."
      }
    }
    catch {
      Add-Issue $issues "$subject frozenProjectionJson must be valid JSON; parse failed: $($_.Exception.Message)"
    }

    if ($seenFrozenHashes.ContainsKey($frozenHash)) {
      Add-Issue $issues "$subject frozenProjectionHash must differ from $($seenFrozenHashes[$frozenHash]); identical frozen content is not a refresh."
    }
    else {
      $seenFrozenHashes[$frozenHash] = $briefId
    }
  }
}

# ---------------------------------------------------------------------------
# Required brief IDs present
# ---------------------------------------------------------------------------

if (-not $sliceBriefIds.ContainsKey("CB-LOCAL-BRIEF-001")) {
  Add-Issue $issues "Brief slice must include snapshot CB-LOCAL-BRIEF-001 (original)."
}
if (-not $sliceBriefIds.ContainsKey("CB-LOCAL-BRIEF-002")) {
  Add-Issue $issues "Brief slice must include snapshot CB-LOCAL-BRIEF-002 (refreshed)."
}

# ---------------------------------------------------------------------------
# Cross-slice ID resolution — every referenced CWI-/CR-/CSR- id resolves
# ---------------------------------------------------------------------------

$referencedWorkItemIds = @($referencedWorkItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$referencedReceiptIds = @($referencedReceiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$referencedSourceIds = @($referencedSourceIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

foreach ($cwiId in $referencedWorkItemIds) {
  if (-not $resolvableWorkItemIds.ContainsKey($cwiId)) {
    Add-Issue $issues "Referenced Work Item does not resolve in sibling slices: $cwiId."
  }
}
foreach ($crId in $referencedReceiptIds) {
  if (-not $resolvableReceiptIds.ContainsKey($crId)) {
    Add-Issue $issues "Referenced receipt does not resolve in sibling slices: $crId."
  }
}
foreach ($csrId in $referencedSourceIds) {
  if (-not $resolvableSourceIds.ContainsKey($csrId)) {
    Add-Issue $issues "Referenced source record does not resolve in sibling slices: $csrId."
  }
}

# ---------------------------------------------------------------------------
# Cross-slice ID uniqueness — new slice IDs must not collide with ANY co-located
# slice (live harvest), not just the named 1.1-1.5 + demo siblings. The generic
# all-slice harvest above is the collision surface; the expected-id constants
# below are a story-fixture presence check only.
# ---------------------------------------------------------------------------

$expectedReceiptIds = @("CR-LOCAL-BRIEF-CREATE-001", "CR-LOCAL-BRIEF-REFRESH-001")
foreach ($receiptId in $expectedReceiptIds) {
  if ($allSliceReceiptIds.ContainsKey($receiptId)) {
    Add-Issue $issues "New receipt ID collides with a receipt id harvested from a sibling slice (unique across ALL slices required): $receiptId."
  }
}

# New CB-LOCAL-* brief IDs must not collide with ANY id harvested from any
# sibling slice (work items, receipts, source records, briefs, run ids,
# idempotency keys). Union into one membership set so the tripwire is live for
# every id family — a rename into any sibling namespace fires here.
$allSiblingAnyIds = @{}
foreach ($id in @($allSliceWorkItemIds.Keys + $allSliceReceiptIds.Keys + $allSliceSourceIds.Keys + $allSliceBriefIds.Keys + $allSliceRunIds.Keys + $allSliceIdempotencyKeys.Keys)) {
  if (-not [string]::IsNullOrWhiteSpace($id)) { $allSiblingAnyIds[$id] = $true }
}
foreach ($briefId in @($sliceBriefIds.Keys)) {
  if ($allSiblingAnyIds.ContainsKey($briefId)) {
    Add-Issue $issues "New brief ID collides with an id harvested from a sibling slice (unique across ALL slices required): $briefId."
  }
}

# ---------------------------------------------------------------------------
# Queue-change scenario
# ---------------------------------------------------------------------------

$queueChange = $run.queueChangeScenario
if ($null -eq $queueChange) {
  Add-Issue $issues "Brief slice must carry a queueChangeScenario block."
}
else {
  $originalId = [string]$queueChange.originalSnapshot
  $refreshedId = [string]$queueChange.refreshedSnapshot

  if ([string]::IsNullOrWhiteSpace($originalId) -or -not $sliceBriefIds.ContainsKey($originalId)) {
    Add-Issue $issues "queueChangeScenario.originalSnapshot must name a snapshot in this slice, found: $originalId."
  }
  if ([string]::IsNullOrWhiteSpace($refreshedId) -or -not $sliceBriefIds.ContainsKey($refreshedId)) {
    Add-Issue $issues "queueChangeScenario.refreshedSnapshot must name a snapshot in this slice, found: $refreshedId."
  }
  if ($originalId -eq $refreshedId) {
    Add-Issue $issues "queueChangeScenario original and refreshed snapshots must differ."
  }
  if ($originalId -ne "CB-LOCAL-BRIEF-001") {
    Add-Issue $issues "queueChangeScenario.originalSnapshot must be CB-LOCAL-BRIEF-001, found: $originalId."
  }
  if ($refreshedId -ne "CB-LOCAL-BRIEF-002") {
    Add-Issue $issues "queueChangeScenario.refreshedSnapshot must be CB-LOCAL-BRIEF-002, found: $refreshedId."
  }

  # Resolve snapshot handles WITHOUT wrapping in @(...) so a missed selection is
  # $null (not an empty array that always tests non-null). Hard-fail if a name
  # that passed the ContainsKey check above nevertheless fails to select.
  $originalSnap = $snapshots | Where-Object { [string]$_.com_council_brief_id -eq $originalId } | Select-Object -First 1
  $refreshedSnap = $snapshots | Where-Object { [string]$_.com_council_brief_id -eq $refreshedId } | Select-Object -First 1
  if ($null -eq $originalSnap) {
    Add-Issue $issues "queueChangeScenario.originalSnapshot could not be resolved to a snapshot handle: $originalId."
  }
  if ($null -eq $refreshedSnap) {
    Add-Issue $issues "queueChangeScenario.refreshedSnapshot could not be resolved to a snapshot handle: $refreshedId."
  }

  if ($null -ne $originalSnap -and $null -ne $refreshedSnap) {
    $originalDate = Get-ComparableInstant $originalSnap.com_brief_date
    $refreshedDate = Get-ComparableInstant $refreshedSnap.com_brief_date
    if ($null -ne $originalDate -and $null -ne $refreshedDate -and $refreshedDate -le $originalDate) {
      Add-Issue $issues "Refreshed snapshot com_brief_date must be later than the original's ($($originalSnap.com_brief_date)), found: $($refreshedSnap.com_brief_date)."
    }
  }

  # Original must be untouched — proven by recomputing the original's
  # frozenProjectionHash from its frozenProjectionJson AND requiring the inline
  # isProjection/sourceOfTruth/sections still match the frozen JSON. This is a
  # real SHA-256 crypto check, NOT a self-asserted boolean authored by the slice.
  if ($null -ne $originalSnap) {
    if (-not (Test-HasNonEmptyField -Record $originalSnap -Field "frozenProjectionJson")) {
      Add-Issue $issues "Original snapshot must carry frozenProjectionJson so its byte-stability (untouched) can be rechecked."
    }
    elseif (-not (Test-HasNonEmptyField -Record $originalSnap -Field "frozenProjectionHash")) {
      Add-Issue $issues "Original snapshot must carry frozenProjectionHash so its byte-stability (untouched) can be rechecked."
    }
    else {
      $oFrozenJson = [string]$originalSnap.frozenProjectionJson
      $oFrozenHash = [string]$originalSnap.frozenProjectionHash
      if ($oFrozenHash -notmatch "^sha256:[0-9a-f]{64}$") {
        Add-Issue $issues "Original snapshot frozenProjectionHash must use sha256:<64 hex> format, found: $oFrozenHash."
      }
      else {
        $oBytes = [System.Text.Encoding]::UTF8.GetBytes($oFrozenJson)
        $oSha = [System.Security.Cryptography.SHA256]::Create()
        $oHashBytes = $oSha.ComputeHash($oBytes)
        $oRecomputed = "sha256:" + [BitConverter]::ToString($oHashBytes).Replace("-", "").ToLower()
        if ($oRecomputed -ne $oFrozenHash) {
          Add-Issue $issues "Original snapshot frozenProjectionHash must match recomputed SHA-256 of frozenProjectionJson; the original Brief is not byte-stable (it was touched). Expected $oFrozenHash, recomputed $oRecomputed."
        }
      }
      try {
        $oFrozenObj = $oFrozenJson | ConvertFrom-Json
        $oInlineObj = $originalSnap | Select-Object -Property isProjection, sourceOfTruth, sections
        $oFrozenReserialized = $oFrozenObj | ConvertTo-Json -Depth 20 -Compress
        $oInlineReserialized = $oInlineObj | ConvertTo-Json -Depth 20 -Compress
        if ($oFrozenReserialized -ne $oInlineReserialized) {
          Add-Issue $issues "Original snapshot inline isProjection/sourceOfTruth/sections must match its frozenProjectionJson; the original Brief was rewritten after its hash was recorded (not untouched)."
        }
      }
      catch {
        Add-Issue $issues "Original snapshot frozenProjectionJson must be valid JSON; parse failed: $($_.Exception.Message)"
      }
    }
  }

  # sectionsThatDiffer must be a FAITHFUL, COMPLETE declaration of the delta:
  # every listed section must actually differ in content between original and
  # refreshed, and every UNLISTED section must be byte-identical. A slice cannot
  # game this by listing arbitrary names or omitting the true delta sections.
  $sectionsDiffer = @($queueChange.sectionsThatDiffer | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($sectionsDiffer.Count -eq 0) {
    Add-Issue $issues "queueChangeScenario.sectionsThatDiffer must list at least one section name."
  }
  if (-not (Test-HasNonEmptyField -Record $queueChange -Field "differReason")) {
    Add-Issue $issues "queueChangeScenario.differReason must be non-empty."
  }
  $sectionsDifferSet = @{}
  foreach ($name in $sectionsDiffer) { $sectionsDifferSet[$name] = $true }
  if ($null -ne $originalSnap -and $null -ne $refreshedSnap -and $null -ne $originalSnap.sections -and $null -ne $refreshedSnap.sections) {
    foreach ($sectionName in $requiredEightSections) {
      $origHas = $originalSnap.sections.PSObject.Properties.Name -contains $sectionName
      $refreshHas = $refreshedSnap.sections.PSObject.Properties.Name -contains $sectionName
      if (-not $origHas -or -not $refreshHas) {
        Add-Issue $issues "queueChangeScenario section content diff requires section $sectionName to exist on both snapshots."
        continue
      }
      $origSig = ($originalSnap.sections.$sectionName | ConvertTo-Json -Depth 20 -Compress)
      $refreshSig = ($refreshedSnap.sections.$sectionName | ConvertTo-Json -Depth 20 -Compress)
      $actuallyDiffers = ($origSig -ne $refreshSig)
      if ($sectionsDifferSet.ContainsKey($sectionName) -and -not $actuallyDiffers) {
        Add-Issue $issues "queueChangeScenario.sectionsThatDiffer lists $sectionName but the section content is identical between original and refreshed; the list is unfaithful."
      }
      if (-not $sectionsDifferSet.ContainsKey($sectionName) -and $actuallyDiffers) {
        Add-Issue $issues "queueChangeScenario.sectionsThatDiffer omits $sectionName but the section content actually differs between original and refreshed; the list is incomplete."
      }
    }
  }

  # Change events must reference real receipts from sibling slices
  $changeEvents = @($queueChange.changeEvents | Where-Object { $null -ne $_ })
  if ($changeEvents.Count -lt 1) {
    Add-Issue $issues "queueChangeScenario must include at least one change event."
  }
  $changeReceipts = @()
  foreach ($event in $changeEvents) {
    $eventReceipt = [string]$event.receipt
    $eventSubject = "Change event for receipt $eventReceipt"
    if ([string]::IsNullOrWhiteSpace($eventReceipt)) {
      Add-Issue $issues "Change event must name its receipt."
    }
    else {
      $changeReceipts += $eventReceipt
      if (-not $resolvableReceiptIds.ContainsKey($eventReceipt)) {
        Add-Issue $issues "$eventSubject references an unknown receipt in sibling slices."
      }
    }
    if (-not (Test-HasNonEmptyField -Record $event -Field "changeDescription")) {
      Add-Issue $issues "$eventSubject must carry a non-empty changeDescription."
    }
  }

  # The refreshed snapshot must reference change-event receipts that the original does not
  $originalReceipts = @()
  $refreshedReceipts = @()
  if ($null -ne $originalSnap -and $null -ne $originalSnap.sections -and ($originalSnap.sections.PSObject.Properties.Name -contains "recentReceipts")) {
    $originalReceipts = @($originalSnap.sections.recentReceipts | ForEach-Object { [string]$_.receipt } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  }
  if ($null -ne $refreshedSnap -and $null -ne $refreshedSnap.sections -and ($refreshedSnap.sections.PSObject.Properties.Name -contains "recentReceipts")) {
    $refreshedReceipts = @($refreshedSnap.sections.recentReceipts | ForEach-Object { [string]$_.receipt } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  }

  # The change-event receipts must appear in the refreshed snapshot but not the original
  foreach ($changeReceipt in @($changeReceipts | Sort-Object -Unique)) {
    if ($refreshedReceipts -notcontains $changeReceipt) {
      Add-Issue $issues "Refreshed snapshot must reference change-event receipt $changeReceipt in its recentReceipts section."
    }
    if ($originalReceipts -contains $changeReceipt) {
      Add-Issue $issues "Original snapshot must NOT reference change-event receipt $changeReceipt; the original Brief was generated before the change."
    }
  }

  # The two frozen hashes must differ
  if ($null -ne $originalSnap -and $null -ne $refreshedSnap) {
    $origHash = [string]$originalSnap.frozenProjectionHash
    $refreshHash = [string]$refreshedSnap.frozenProjectionHash
    if (-not [string]::IsNullOrWhiteSpace($origHash) -and -not [string]::IsNullOrWhiteSpace($refreshHash) -and $origHash -eq $refreshHash) {
      Add-Issue $issues "Original and refreshed snapshots must have different frozenProjectionHash values; identical hashes mean the refresh changed nothing."
    }
  }

  # Each change event must DRIVE a real content delta: its anchor id (workItem or
  # sourceRecord) must appear in at least one section listed in sectionsThatDiffer
  # of the refreshed snapshot, and the matching entry in the original's same
  # section must be absent or carry a different reason. This proves the queue
  # change is reflected where the change dictates — not just in receipts/hash.
  if ($null -ne $originalSnap -and $null -ne $refreshedSnap -and $null -ne $originalSnap.sections -and $null -ne $refreshedSnap.sections) {
    foreach ($event in $changeEvents) {
      $anchorField = $null
      $anchorId = $null
      if (Test-HasNonEmptyField -Record $event -Field "workItem") {
        $anchorField = "workItem"
        $anchorId = [string]$event.workItem
      }
      elseif (Test-HasNonEmptyField -Record $event -Field "sourceRecord") {
        $anchorField = "sourceRecord"
        $anchorId = [string]$event.sourceRecord
      }
      if ([string]::IsNullOrWhiteSpace($anchorId)) { continue }

      $droveDelta = $false
      foreach ($sectionName in $sectionsDiffer) {
        if (-not ($originalSnap.sections.PSObject.Properties.Name -contains $sectionName)) { continue }
        if (-not ($refreshedSnap.sections.PSObject.Properties.Name -contains $sectionName)) { continue }
        $refreshedAnchorEntries = @($refreshedSnap.sections.$sectionName | Where-Object { $null -ne $_ -and (Test-HasNonEmptyField -Record $_ -Field $anchorField) -and [string]$_.$anchorField -eq $anchorId })
        if ($refreshedAnchorEntries.Count -eq 0) { continue }
        $originalAnchorEntries = @($originalSnap.sections.$sectionName | Where-Object { $null -ne $_ -and (Test-HasNonEmptyField -Record $_ -Field $anchorField) -and [string]$_.$anchorField -eq $anchorId })
        if ($originalAnchorEntries.Count -eq 0) {
          $droveDelta = $true
          break
        }
        $refreshedReasons = @($refreshedAnchorEntries | ForEach-Object { [string]$_.reason } | Sort-Object) -join "|"
        $originalReasons = @($originalAnchorEntries | ForEach-Object { [string]$_.reason } | Sort-Object) -join "|"
        if ($refreshedReasons -ne $originalReasons) {
          $droveDelta = $true
          break
        }
      }
      if (-not $droveDelta) {
        Add-Issue $issues "Change event anchor $anchorId did not drive a content delta in any section listed in sectionsThatDiffer; the queue change must be reflected where the change dictates, not only in receipts/hash."
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Receipts — manifest verb, full field set, strict booleans, no live-write
# ---------------------------------------------------------------------------

$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 2) {
  Add-Issue $issues "Brief slice must include at least two receipts (create and refresh)."
}

$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique

$sliceReceiptIdMap = @{}
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
    if ($sliceReceiptIdMap.ContainsKey($receiptId)) {
      Add-Issue $issues "Duplicate receipt ID in slice: $receiptId."
    }
    else {
      $sliceReceiptIdMap[$receiptId] = $true
    }
    if ($allSliceReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "$subject collides with a receipt id harvested from a sibling slice (unique across ALL slices required)."
    }
    if ($demoReceiptIds -contains $receiptId) {
      Add-Issue $issues "$subject collides with a reserved state-transition-demo receipt ID."
    }
  }

  if ($receiptVerbs -notcontains $receipt.com_verb) {
    Add-Issue $issues "$subject verb is not in manifest com_receiptverb vocabulary: $($receipt.com_verb)."
  }
  elseif ($receipt.com_verb -ne "reviewed") {
    Add-Issue $issues "$subject must use verb reviewed for Story 3.1 brief evidence, found: $($receipt.com_verb)."
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
      Add-Issue $issues "$subject reuses an idempotency key already used in this slice: $idempotencyKey."
    }
    else {
      $seenIdempotencyKeys[$idempotencyKey] = $true
    }
    if ($allSliceIdempotencyKeys.ContainsKey($idempotencyKey)) {
      Add-Issue $issues "$subject idempotency key collides with one harvested from a sibling slice (unique across ALL slices required): $idempotencyKey."
    }
  }

  if ($receipt.com_append_only_locked -isnot [bool] -or -not $receipt.com_append_only_locked) {
    Add-Issue $issues "$subject com_append_only_locked must be strict boolean true."
  }
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject

  # No live-write marker fields
  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 3.1 receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 3.1 receipts are local contract evidence only."
      }
    }
  }
}

foreach ($expectedReceiptId in $expectedReceiptIds) {
  if (-not $sliceReceiptIdMap.ContainsKey($expectedReceiptId)) {
    Add-Issue $issues "Brief slice must include receipt $expectedReceiptId."
  }
}

# Receipt-before/after states: create receipt must reference the original brief, refresh must reference the refreshed brief
$createReceipt = @($receipts | Where-Object { $_.com_receipt_id -eq "CR-LOCAL-BRIEF-CREATE-001" } | Select-Object -First 1)
if ($createReceipt) {
  if (([string]$createReceipt.com_after_state).IndexOf("CB-LOCAL-BRIEF-001", [System.StringComparison]::Ordinal) -lt 0) {
    Add-Issue $issues "Receipt CR-LOCAL-BRIEF-CREATE-001 com_after_state must reference CB-LOCAL-BRIEF-001."
  }
}
$refreshReceipt = @($receipts | Where-Object { $_.com_receipt_id -eq "CR-LOCAL-BRIEF-REFRESH-001" } | Select-Object -First 1)
if ($refreshReceipt) {
  if (([string]$refreshReceipt.com_after_state).IndexOf("CB-LOCAL-BRIEF-002", [System.StringComparison]::Ordinal) -lt 0) {
    Add-Issue $issues "Receipt CR-LOCAL-BRIEF-REFRESH-001 com_after_state must reference CB-LOCAL-BRIEF-002."
  }
  if (([string]$refreshReceipt.com_before_state).IndexOf("CB-LOCAL-BRIEF-001", [System.StringComparison]::Ordinal) -lt 0) {
    Add-Issue $issues "Receipt CR-LOCAL-BRIEF-REFRESH-001 com_before_state must reference the prior brief CB-LOCAL-BRIEF-001."
  }
}

# ---------------------------------------------------------------------------
# Receipt source links
# ---------------------------------------------------------------------------

$links = @($run.receiptSourceLinks | Where-Object { $null -ne $_ })
foreach ($link in $links) {
  $linkSubject = "Receipt source link $($link.com_name)"
  if (-not (Test-HasNonEmptyField -Record $link -Field "com_name")) {
    Add-Issue $issues "Receipt source link must carry a non-empty com_name."
  }
  $linkReceiptId = [string]$link.com_receipt
  if ([string]::IsNullOrWhiteSpace($linkReceiptId) -or -not $sliceReceiptIdMap.ContainsKey($linkReceiptId)) {
    Add-Issue $issues "$linkSubject references unknown receipt: $linkReceiptId."
  }
  $linkSourceId = [string]$link.com_source_record
  if ([string]::IsNullOrWhiteSpace($linkSourceId) -or $knownSourceIds -notcontains $linkSourceId) {
    Add-Issue $issues "$linkSubject must bind a source record that resolves in sibling slices, found: $linkSourceId."
  }
  if ($evidenceRoles -notcontains $link.com_evidence_role) {
    Add-Issue $issues "$linkSubject evidence role is not in manifest vocabulary: $($link.com_evidence_role)."
  }
}
foreach ($receiptId in @($sliceReceiptIdMap.Keys)) {
  if (@($links | Where-Object { $_.com_receipt -eq $receiptId }).Count -lt 1) {
    Add-Issue $issues "Receipt $receiptId must be bound to its source evidence by at least one receipt source link."
  }
}

# ---------------------------------------------------------------------------
# Brief creation deferred — live mutation stays receipt-gated to Epic 2
# ---------------------------------------------------------------------------

$briefCreationDeferred = @($run.briefCreationDeferred | Where-Object { $null -ne $_ })
if ($briefCreationDeferred.Count -lt 2) {
  Add-Issue $issues "Brief slice must include deferred entries for both snapshots."
}
foreach ($deferred in $briefCreationDeferred) {
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "brief")) {
    Add-Issue $issues "Deferred brief creation entry must name its brief."
  }
  elseif (-not $sliceBriefIds.ContainsKey([string]$deferred.brief)) {
    Add-Issue $issues "Deferred brief creation entry references an unknown brief: $($deferred.brief)."
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred brief creation entry for $($deferred.brief) must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred brief creation entry for $($deferred.brief) must state that the live mutation is receipt-gated."
  }
}

# ---------------------------------------------------------------------------
# Acceptance mapping
# ---------------------------------------------------------------------------

foreach ($criterion in @(1, 2, 3)) {
  $mapping = @($brief.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
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
  Write-Host "Minion brief slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Minion brief slice validation succeeded."
Write-Host "Snapshots: $($snapshots.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "Referenced Work Item IDs: $(($referencedWorkItemIds -join ', '))"
Write-Host "Referenced Receipt IDs: $(($referencedReceiptIds -join ', '))"
Write-Host "Referenced Source Record IDs: $(($referencedSourceIds -join ', '))"
Write-Host "MINION_BRIEF_SLICE_VALIDATE_OK"
