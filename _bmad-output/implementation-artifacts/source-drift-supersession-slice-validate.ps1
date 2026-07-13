param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$DriftSlicePath = "$PSScriptRoot\source-drift-supersession-slice.json",
  [string]$ManualSlicePath = "$PSScriptRoot\manual-source-record-slice.json",
  [string]$OutlookSlicePath = "$PSScriptRoot\outlook-source-reference-slice.json",
  [string]$Story13ExtractionPath = "$PSScriptRoot\proposed-work-item-extraction-slice.json",
  [string]$Story14ExtractionPath = "$PSScriptRoot\zero-multi-item-extraction-slice.json",
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
    # ConvertFrom-Json auto-parses ISO 8601 JSON strings; Kind=Unspecified means the original carried no UTC offset.
    if ($rawValue.Kind -eq [System.DateTimeKind]::Unspecified) {
      Add-Issue $Issues "$Subject ${Field} must be ISO 8601 with an explicit UTC offset so drift ordering is not host-timezone dependent, found: $rawValue."
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
    Add-Issue $Issues "$Subject ${Field} must be ISO 8601 with an explicit UTC offset so drift ordering is not host-timezone dependent, found: $rawValue."
    return $null
  }
  return $parsed
}

function Test-PriorRationaleRestated {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)][string]$RawSliceText,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PriorRationale,
    [Parameter(Mandatory = $true)][string]$Subject
  )

  if ([string]::IsNullOrWhiteSpace($PriorRationale)) {
    return
  }
  # Normalize whitespace and compare case-insensitively so trivial reflows or case tweaks cannot evade the tripwire.
  $normalizedSlice = [string]($RawSliceText -replace "\s+", " ")
  $escaped = (ConvertTo-Json $PriorRationale -Compress).Trim('"')
  foreach ($candidate in @($PriorRationale, $escaped)) {
    $needle = [string]($candidate -replace "\s+", " ")
    if ([string]::IsNullOrWhiteSpace($needle)) {
      continue
    }
    if ($normalizedSlice.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
      Add-Issue $Issues "$Subject must not restate the prior source's rationale in-slice; prior rationale stays only in its own slice."
      return
    }
  }
}

function Get-ComparableInstant {
  param($Value)

  # Normalizes either a raw ISO 8601 string (Windows PowerShell 5.1) or an already-parsed [datetime]
  # (pwsh 7 ConvertFrom-Json) to a [datetimeoffset] instant, so ordering and equality checks do not
  # depend on the engine's JSON datetime handling or on culture-sensitive string round-trips.
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

function Test-NoPriorMutationFields {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$Subject
  )

  foreach ($mutationField in @("com_extraction_status", "com_source_to_work_item_rationale", "com_state_group")) {
    if ($Record.PSObject.Properties.Name -contains $mutationField) {
      Add-Issue $Issues "$Subject must not apply '$mutationField' in-slice; prior IDs may be referenced but never carry replacement rationale or status fields."
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
    Write-Host "Source drift and supersession slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

foreach ($path in @($ManifestPath, $DriftSlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required source drift and supersession validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$drift = Read-JsonInput -Path $DriftSlicePath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath
$rawSliceText = Get-Content -LiteralPath $DriftSlicePath -Raw
$issues = [System.Collections.Generic.List[string]]::new()

$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$extractionStatuses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_extractionstatus"
$sourceSystems = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_sourcesystem"
$sourceKinds = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_sourcekind"
$dataBoundaryPolicies = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_databoundarypolicy"
$evidenceRoles = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilreceiptsource" -ColumnName "com_evidence_role"
$workItemSourceRoles = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilworkitemsource" -ColumnName "com_source_role"

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_extractionstatus"; Values = $extractionStatuses },
    @{ Name = "com_sourcesystem"; Values = $sourceSystems },
    @{ Name = "com_sourcekind"; Values = $sourceKinds },
    @{ Name = "com_databoundarypolicy"; Values = $dataBoundaryPolicies },
    @{ Name = "com_councilreceiptsource.com_evidence_role"; Values = $evidenceRoles },
    @{ Name = "com_councilworkitemsource.com_source_role"; Values = $workItemSourceRoles }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

if ($receiptVerbs -notcontains "source_drifted") {
  Add-Issue $issues "Manifest com_receiptverb is missing the drift verb: source_drifted."
}
if ($extractionStatuses -notcontains "superseded") {
  Add-Issue $issues "Manifest com_extractionstatus is missing the supersession status: superseded."
}
if ($evidenceRoles -notcontains "drift_evidence") {
  Add-Issue $issues "Manifest com_councilreceiptsource.com_evidence_role is missing: drift_evidence."
}
if ($workItemSourceRoles -notcontains "superseding") {
  Add-Issue $issues "Manifest com_councilworkitemsource.com_source_role is missing: superseding."
}

if ($drift.storyKey -ne "1-5-handle-source-drift-and-supersession") {
  Add-Issue $issues "Drift slice storyKey must be 1-5-handle-source-drift-and-supersession."
}
if ([string]$drift.status -notmatch "^local-contract") {
  Add-Issue $issues "Drift slice status must declare local contract evidence, found: $($drift.status)."
}

foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "requiresExplicitHumanApprovalForExecution", "sourceRecordsRemainSeparate", "receiptsAreLocalContractEvidenceOnly", "priorRationaleAndReceiptsUnchanged", "noWorkItemStateChangeInThisSlice")) {
  if (-not ($drift.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Drift slice must declare guard: $guard."
  }
}
if ($drift.guards.PSObject.Properties.Name -contains "noReceiptCreationInThisSlice") {
  Add-Issue $issues "Drift slice must not declare noReceiptCreationInThisSlice; drift receipts are the sanctioned Story 1.5 deliverable."
}
foreach ($guardProperty in @($drift.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Drift guard must be boolean true: $($guardProperty.Name)."
  }
}

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

$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$knownWorkItems = @($story13Items + $story14Items)
$knownWorkItemIds = @($knownWorkItems | ForEach-Object { [string]$_.com_council_work_item_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$story13WorkItemLinks = @($story13Extraction.extractionRun.workItemSourceLinks | Where-Object { $null -ne $_ })
$story14WorkItemLinks = @($story14Extraction.extractionRun.workItemSourceLinks | Where-Object { $null -ne $_ })
# A Work Item is affected by drift through any of its linked sources (manifest com_councilworkitemsource),
# not only its primary source; FR30 speaks of sources that affect a Work Item, in any role.
$workItemSourceIdsByItem = @{}
foreach ($item in $knownWorkItems) {
  $itemId = [string]$item.com_council_work_item_id
  if ([string]::IsNullOrWhiteSpace($itemId)) {
    continue
  }
  $itemSourceIds = [System.Collections.Generic.List[string]]::new()
  if (-not [string]::IsNullOrWhiteSpace([string]$item.com_primary_source_record)) {
    $itemSourceIds.Add([string]$item.com_primary_source_record)
  }
  $workItemSourceIdsByItem[$itemId] = $itemSourceIds
}
foreach ($workItemLink in @($story13WorkItemLinks + $story14WorkItemLinks)) {
  $linkItemId = [string]$workItemLink.com_work_item
  $linkSourceId = [string]$workItemLink.com_source_record
  if (-not [string]::IsNullOrWhiteSpace($linkItemId) -and -not [string]::IsNullOrWhiteSpace($linkSourceId) -and $workItemSourceIdsByItem.ContainsKey($linkItemId)) {
    if ($workItemSourceIdsByItem[$linkItemId] -notcontains $linkSourceId) {
      $workItemSourceIdsByItem[$linkItemId].Add($linkSourceId)
    }
  }
}
$story14ZeroItemOutcomes = @($story14Extraction.extractionRun.zeroItemOutcomes | Where-Object { $null -ne $_ })
$rationaleProducingSourceIds = @(
  @($knownWorkItems | ForEach-Object { [string]$_.com_primary_source_record }) +
  @($story14ZeroItemOutcomes | ForEach-Object { [string]$_.sourceRecord })
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
$demoReceiptIds = @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

foreach ($sliceLoad in @(
    @{ Name = "manual-source-record-slice sampleRecords"; Count = $manualSources.Count },
    @{ Name = "outlook-source-reference-slice sampleRecords"; Count = $outlookSources.Count },
    @{ Name = "zero-multi-item-extraction-slice embeddedSampleSourceRecords"; Count = $story14EmbeddedSources.Count },
    @{ Name = "proposed-work-item-extraction-slice proposedWorkItems"; Count = $story13Items.Count },
    @{ Name = "zero-multi-item-extraction-slice proposedWorkItems"; Count = $story14Items.Count },
    @{ Name = "zero-multi-item-extraction-slice zeroItemOutcomes"; Count = $story14ZeroItemOutcomes.Count },
    @{ Name = "proposed-work-item-extraction-slice workItemSourceLinks"; Count = $story13WorkItemLinks.Count },
    @{ Name = "zero-multi-item-extraction-slice workItemSourceLinks"; Count = $story14WorkItemLinks.Count }
  )) {
  if ($sliceLoad.Count -eq 0) {
    Add-Issue $issues "No records loaded from $($sliceLoad.Name); its cross-slice checks would silently no-op."
  }
}

if ($knownPriorSourceIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be loaded from the Story 1.1/1.2/1.4 slices; cross-slice checks would silently no-op."
}
if ($knownWorkItemIds.Count -eq 0) {
  Add-Issue $issues "No Work Item IDs could be loaded from the Story 1.3/1.4 slices; cross-slice checks would silently no-op."
}
if (@($rationaleProducingSourceIds).Count -eq 0) {
  Add-Issue $issues "No rationale-producing Source Record IDs could be derived from the Story 1.3/1.4 slices; drift-eligibility checks would silently no-op."
}
if ($demoReceiptIds.Count -eq 0) {
  Add-Issue $issues "No reserved receipt IDs could be loaded from state-transition-demo-evidence.json; receipt collision checks would silently no-op."
}

$run = $drift.driftRun
if ($null -eq $run) {
  Add-Issue $issues "Drift slice must carry a driftRun block."
  Write-Host "Source drift and supersession slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Drift run must declare a runId."
}
elseif (@([string]$story13Extraction.extractionRun.runId, [string]$story14Extraction.extractionRun.runId) -contains [string]$run.runId) {
  Add-Issue $issues "Drift run must use a new local runId, not a Story 1.3/1.4 runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Drift run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Drift run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Drift run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "zero-multi-item-extraction-slice.json")) {
  if (@($run.inputSourceRecordsFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Drift run must reference $inputSlice as an input."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Drift run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("driftNeverRewritesPriorRationaleOrReceipts", "driftCreatesNewVersionEvidenceOrSupersedingRecord", "affectedWorkItemsAreFlaggedForReviewOnly", "stateChangesRequireNewReceiptAndStayDeferredToEpic2", "liveSourceMutationReceiptGatedToStory23")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Drift run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Drift run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

$driftEvents = @($run.driftEvents | Where-Object { $null -ne $_ })
if ($driftEvents.Count -lt 1) {
  Add-Issue $issues "Drift slice must include at least one drift event."
}
if (@($driftEvents | Where-Object { $_.sourceRecord -eq "CSR-MANUAL-MEETING-001" }).Count -ne 1) {
  Add-Issue $issues "Drift slice must record exactly one drift event for the Work-Item-producing source CSR-MANUAL-MEETING-001."
}

$driftEventSourceIds = @()
$seenDriftSourceIds = @{}
foreach ($driftEvent in $driftEvents) {
  $driftSourceId = [string]$driftEvent.sourceRecord
  $subject = "Drift event $driftSourceId"
  if ([string]::IsNullOrWhiteSpace($driftSourceId)) {
    Add-Issue $issues "Drift event must name its sourceRecord."
    continue
  }
  if ($seenDriftSourceIds.ContainsKey($driftSourceId)) {
    Add-Issue $issues "Duplicate drift event for Source Record: $driftSourceId."
  } else {
    $seenDriftSourceIds[$driftSourceId] = $true
  }
  $driftEventSourceIds += $driftSourceId

  if ($knownPriorSourceIds -notcontains $driftSourceId) {
    Add-Issue $issues "Drift event references an unknown Source Record: $driftSourceId."
    continue
  }
  if ($rationaleProducingSourceIds -notcontains $driftSourceId) {
    Add-Issue $issues "Drift event source must already have produced Work Items or rationale in Story 1.3/1.4: $driftSourceId."
  }

  $priorRecord = $priorSourcesById[$driftSourceId]

  if (-not (Test-HasNonEmptyField -Record $driftEvent -Field "driftRationale")) {
    Add-Issue $issues "$subject must carry a non-empty driftRationale."
  }
  if (-not (Test-HasNonEmptyField -Record $driftEvent -Field "driftKind")) {
    Add-Issue $issues "$subject must carry a non-empty driftKind."
  }
  Test-NoPriorMutationFields -Issues $issues -Record $driftEvent -Subject $subject

  $driftPriorRationaleTexts = @()
  if ($null -ne $priorRecord -and (Test-HasNonEmptyField -Record $priorRecord -Field "com_source_to_work_item_rationale")) {
    $driftPriorRationaleTexts += [string]$priorRecord.com_source_to_work_item_rationale
  }
  foreach ($outcome in @($story14ZeroItemOutcomes | Where-Object { $_.sourceRecord -eq $driftSourceId })) {
    if (Test-HasNonEmptyField -Record $outcome -Field "extraction_rationale") {
      $driftPriorRationaleTexts += [string]$outcome.extraction_rationale
    }
  }
  foreach ($item in @($knownWorkItems | Where-Object { $_.com_primary_source_record -eq $driftSourceId })) {
    foreach ($rationaleField in @("extraction_rationale", "com_rationale")) {
      if (Test-HasNonEmptyField -Record $item -Field $rationaleField) {
        $driftPriorRationaleTexts += [string]$item.$rationaleField
      }
    }
  }
  foreach ($priorRationale in $driftPriorRationaleTexts) {
    Test-PriorRationaleRestated -Issues $issues -RawSliceText $rawSliceText -PriorRationale $priorRationale -Subject $subject
  }

  $observed = $driftEvent.observedEvidence
  if ($null -eq $observed) {
    Add-Issue $issues "$subject must carry an observedEvidence block."
    continue
  }
  Test-NoPriorMutationFields -Issues $issues -Record $observed -Subject "$subject observedEvidence"

  # priorEvidence is audited whenever it is present, regardless of whether the prior slice records a version ref.
  $prior = $driftEvent.priorEvidence
  if ($null -ne $prior) {
    Test-NoPriorMutationFields -Issues $issues -Record $prior -Subject "$subject priorEvidence"
    if ((Test-HasNonEmptyField -Record $prior -Field "com_captured_at") -and $null -ne $priorRecord -and (Test-HasNonEmptyField -Record $priorRecord -Field "com_captured_at")) {
      $echoedCapturedAt = Get-ComparableInstant $prior.com_captured_at
      $actualCapturedAt = Get-ComparableInstant $priorRecord.com_captured_at
      $capturedAtMismatch = if ($null -ne $echoedCapturedAt -and $null -ne $actualCapturedAt) { $echoedCapturedAt -ne $actualCapturedAt } else { [string]$prior.com_captured_at -ne [string]$priorRecord.com_captured_at }
      if ($capturedAtMismatch) {
        Add-Issue $issues "$subject priorEvidence com_captured_at must match the prior record's actual value ($($priorRecord.com_captured_at)), found: $($prior.com_captured_at)."
      }
    }
    foreach ($echoField in @("com_content_snapshot_ref", "com_source_version_ref")) {
      if ((Test-HasNonEmptyField -Record $prior -Field $echoField) -and $null -ne $priorRecord -and (Test-HasNonEmptyField -Record $priorRecord -Field $echoField)) {
        if ([string]$prior.$echoField -ne [string]$priorRecord.$echoField) {
          Add-Issue $issues "$subject priorEvidence $echoField must match the prior record's actual value ($($priorRecord.$echoField)), found: $($prior.$echoField)."
        }
      }
    }
  }

  if (-not (Test-HasNonEmptyField -Record $observed -Field "com_source_version_ref")) {
    Add-Issue $issues "$subject must record a non-empty new com_source_version_ref."
  }
  else {
    $priorVersionRef = ""
    if (Test-HasNonEmptyField -Record $priorRecord -Field "com_source_version_ref") {
      $priorVersionRef = [string]$priorRecord.com_source_version_ref
    }
    if (-not [string]::IsNullOrWhiteSpace($priorVersionRef)) {
      if ([string]$observed.com_source_version_ref -eq $priorVersionRef) {
        Add-Issue $issues "$subject new com_source_version_ref must differ from the prior slice's version ref: $priorVersionRef."
      }
    }
    else {
      if ($null -eq $prior) {
        Add-Issue $issues "$subject prior slice records no com_source_version_ref, so the drift event must carry a priorEvidence block stating that explicitly."
      }
      else {
        if (-not ($prior.PSObject.Properties.Name -contains "com_source_version_ref") -or (Test-HasNonEmptyField -Record $prior -Field "com_source_version_ref")) {
          Add-Issue $issues "$subject priorEvidence must state an explicitly empty com_source_version_ref because the prior slice records none."
        }
        if (-not (Test-HasNonEmptyField -Record $prior -Field "priorVersionRefNote") -or ([string]$prior.priorVersionRefNote -notmatch "no\s+com_source_version_ref|no\s+prior\s+version")) {
          Add-Issue $issues "$subject priorEvidence must carry a priorVersionRefNote explicitly stating the prior capture records no version ref."
        }
      }
    }
  }

  if (-not (Test-HasNonEmptyField -Record $observed -Field "com_content_hash") -or ([string]$observed.com_content_hash -notmatch "^sha256:[0-9a-f]{64}$")) {
    Add-Issue $issues "$subject observed com_content_hash must use sha256:<64 hex> format, found: $($observed.com_content_hash)."
  }
  elseif ($null -ne $priorRecord -and (Test-HasNonEmptyField -Record $priorRecord -Field "com_content_hash")) {
    if ([string]$observed.com_content_hash -eq [string]$priorRecord.com_content_hash) {
      Add-Issue $issues "$subject observed com_content_hash must differ from the prior record's hash; identical content is not drift."
    }
  }

  $observedModifiedAt = Test-IsoTimestamp -Issues $issues -Record $observed -Field "com_observed_modified_at" -Subject "$subject observedEvidence"
  if ($null -ne $observedModifiedAt -and $null -ne $priorRecord) {
    $capturedAt = Get-ComparableInstant $priorRecord.com_captured_at
    if ($null -eq $capturedAt) {
      Add-Issue $issues "$subject prior record com_captured_at could not be parsed for drift ordering: $($priorRecord.com_captured_at)."
    }
    elseif ($observedModifiedAt -le $capturedAt) {
      Add-Issue $issues "$subject com_observed_modified_at must be later than the source's com_captured_at ($($priorRecord.com_captured_at)), found: $($observed.com_observed_modified_at)."
    }
  }
}

$requiredSourceFields = @(
  "com_name",
  "com_council_source_record_id",
  "com_source_system",
  "com_source_kind",
  "com_source_object_ref",
  "com_captured_at",
  "com_captured_by",
  "com_extraction_status",
  "com_source_to_work_item_rationale",
  "com_data_boundary_policy"
)

$supersessions = @($run.supersessions | Where-Object { $null -ne $_ })
if ($supersessions.Count -lt 1) {
  Add-Issue $issues "Drift slice must include at least one supersession."
}
if (@($supersessions | Where-Object { $_.supersededSourceRecord -eq "CSR-OUTLOOK-THREAD-MOCK-001" }).Count -ne 1) {
  Add-Issue $issues "Drift slice must record exactly one supersession of the rationale-producing source CSR-OUTLOOK-THREAD-MOCK-001."
}

$supersededSourceIds = @()
$supersedingSourceIds = @()
$seenSupersededIds = @{}
foreach ($supersession in $supersessions) {
  $supersededId = [string]$supersession.supersededSourceRecord
  $subject = "Supersession of $supersededId"
  if ([string]::IsNullOrWhiteSpace($supersededId)) {
    Add-Issue $issues "Supersession must name its supersededSourceRecord."
    continue
  }
  if ($seenSupersededIds.ContainsKey($supersededId)) {
    Add-Issue $issues "Duplicate supersession for Source Record: $supersededId."
  } else {
    $seenSupersededIds[$supersededId] = $true
  }
  $supersededSourceIds += $supersededId

  if ($knownPriorSourceIds -notcontains $supersededId) {
    Add-Issue $issues "Supersession references an unknown Source Record: $supersededId."
    continue
  }
  if ($rationaleProducingSourceIds -notcontains $supersededId) {
    Add-Issue $issues "Superseded source must already have produced Work Items or rationale in Story 1.3/1.4: $supersededId."
  }
  if (-not (Test-HasNonEmptyField -Record $supersession -Field "supersessionRationale")) {
    Add-Issue $issues "$subject must carry a non-empty supersessionRationale."
  }
  if (-not (Test-HasNonEmptyField -Record $supersession -Field "supersededRecordDisposition")) {
    Add-Issue $issues "$subject must state the superseded record's disposition (supersededRecordDisposition)."
  }
  Test-NoPriorMutationFields -Issues $issues -Record $supersession -Subject $subject

  $priorRationaleTexts = @()
  $priorRecord = $priorSourcesById[$supersededId]
  if ($null -ne $priorRecord -and (Test-HasNonEmptyField -Record $priorRecord -Field "com_source_to_work_item_rationale")) {
    $priorRationaleTexts += [string]$priorRecord.com_source_to_work_item_rationale
  }
  foreach ($outcome in @($story14ZeroItemOutcomes | Where-Object { $_.sourceRecord -eq $supersededId })) {
    if (Test-HasNonEmptyField -Record $outcome -Field "extraction_rationale") {
      $priorRationaleTexts += [string]$outcome.extraction_rationale
    }
  }
  foreach ($item in @($knownWorkItems | Where-Object { $_.com_primary_source_record -eq $supersededId })) {
    foreach ($rationaleField in @("extraction_rationale", "com_rationale")) {
      if (Test-HasNonEmptyField -Record $item -Field $rationaleField) {
        $priorRationaleTexts += [string]$item.$rationaleField
      }
    }
  }
  foreach ($priorRationale in $priorRationaleTexts) {
    Test-PriorRationaleRestated -Issues $issues -RawSliceText $rawSliceText -PriorRationale $priorRationale -Subject $subject
  }

  $superseding = $supersession.supersedingRecord
  if ($null -eq $superseding) {
    Add-Issue $issues "$subject must embed a supersedingRecord."
    continue
  }

  foreach ($field in $requiredSourceFields) {
    if (-not (Test-HasNonEmptyField -Record $superseding -Field $field)) {
      Add-Issue $issues "$subject superseding record missing required field: $field."
    }
  }

  $supersedingId = [string]$superseding.com_council_source_record_id
  if ($supersedingId -notmatch "^CSR-") {
    Add-Issue $issues "$subject superseding record must use fresh Council-level CSR-* identity: $supersedingId."
  }
  if ($knownPriorSourceIds -contains $supersedingId) {
    Add-Issue $issues "$subject superseding record reuses an existing CSR ID from a prior slice: $supersedingId."
  }
  if ($supersedingSourceIds -contains $supersedingId) {
    Add-Issue $issues "$subject superseding record duplicates another superseding record ID in this slice: $supersedingId."
  }
  if (-not [string]::IsNullOrWhiteSpace($supersedingId)) {
    $supersedingSourceIds += $supersedingId
  }
  if ($supersededId -eq "CSR-OUTLOOK-THREAD-MOCK-001" -and $supersedingId -ne "CSR-OUTLOOK-THREAD-MOCK-002") {
    Add-Issue $issues "The superseding record for CSR-OUTLOOK-THREAD-MOCK-001 must be CSR-OUTLOOK-THREAD-MOCK-002, found: $supersedingId."
  }

  if ([string]$superseding.com_parent_ref -ne $supersededId) {
    Add-Issue $issues "$subject superseding record com_parent_ref must name the superseded record $supersededId, found: $($superseding.com_parent_ref)."
  }
  if ($superseding.evidenceStatus -ne "mock_manual_not_tenant_verified") {
    Add-Issue $issues "$subject superseding record must be marked mock_manual_not_tenant_verified evidence, found: $($superseding.evidenceStatus)."
  }
  if ($sourceSystems -notcontains $superseding.com_source_system) {
    Add-Issue $issues "$subject superseding record has invalid source system: $($superseding.com_source_system)."
  }
  if ($sourceKinds -notcontains $superseding.com_source_kind) {
    Add-Issue $issues "$subject superseding record has invalid source kind: $($superseding.com_source_kind)."
  }
  if ($dataBoundaryPolicies -notcontains $superseding.com_data_boundary_policy) {
    Add-Issue $issues "$subject superseding record has invalid data boundary policy: $($superseding.com_data_boundary_policy)."
  }
  if ($extractionStatuses -notcontains $superseding.com_extraction_status) {
    Add-Issue $issues "$subject superseding record has invalid extraction status: $($superseding.com_extraction_status)."
  }
  elseif ([string]$superseding.com_extraction_status -eq "superseded") {
    Add-Issue $issues "$subject superseding record must not itself start superseded; the superseded status belongs to the prior record and only as a deferred update."
  }
  elseif ([string]$superseding.com_extraction_status -ne "new") {
    Add-Issue $issues "$subject superseding record must start with extraction status new; extraction has not yet run on the superseding capture, found: $($superseding.com_extraction_status)."
  }
  if ($supersededId -eq "CSR-OUTLOOK-THREAD-MOCK-001" -and $superseding.com_data_boundary_policy -ne "hash_only") {
    Add-Issue $issues "$subject superseding record must stay hash_only until richer capture is approved, found: $($superseding.com_data_boundary_policy)."
  }
  if ([string]$superseding.com_data_boundary_policy -eq "hash_only" -and -not (Test-HasNonEmptyField -Record $superseding -Field "com_content_hash")) {
    Add-Issue $issues "$subject superseding record is hash_only and must carry com_content_hash."
  }
  if ((Test-HasNonEmptyField -Record $superseding -Field "com_content_hash") -and ([string]$superseding.com_content_hash -notmatch "^sha256:[0-9a-f]{64}$")) {
    Add-Issue $issues "$subject superseding record com_content_hash must use sha256:<64 hex> format, found: $($superseding.com_content_hash)."
  }
  if ($null -ne $priorRecord -and (Test-HasNonEmptyField -Record $priorRecord -Field "com_content_hash") -and (Test-HasNonEmptyField -Record $superseding -Field "com_content_hash")) {
    if ([string]$superseding.com_content_hash -eq [string]$priorRecord.com_content_hash) {
      Add-Issue $issues "$subject superseding record com_content_hash must differ from the superseded record's hash; identical content is not a supersession."
    }
  }
  if ($null -ne $priorRecord -and (Test-HasNonEmptyField -Record $priorRecord -Field "com_source_version_ref") -and (Test-HasNonEmptyField -Record $superseding -Field "com_source_version_ref")) {
    if ([string]$superseding.com_source_version_ref -eq [string]$priorRecord.com_source_version_ref) {
      Add-Issue $issues "$subject superseding record com_source_version_ref must differ from the superseded record's version ref."
    }
  }
  $supersedingCapturedAt = Test-IsoTimestamp -Issues $issues -Record $superseding -Field "com_captured_at" -Subject "$subject superseding record"
  $supersededCapturedAt = $null
  if ($null -ne $priorRecord -and (Test-HasNonEmptyField -Record $priorRecord -Field "com_captured_at")) {
    $supersededCapturedAt = Get-ComparableInstant $priorRecord.com_captured_at
    if ($null -eq $supersededCapturedAt) {
      Add-Issue $issues "$subject superseded record com_captured_at could not be parsed for supersession ordering: $($priorRecord.com_captured_at)."
    }
  }
  if ($null -ne $supersedingCapturedAt -and $null -ne $supersededCapturedAt -and $supersedingCapturedAt -le $supersededCapturedAt) {
    Add-Issue $issues "$subject superseding record com_captured_at must be later than the superseded record's com_captured_at ($($priorRecord.com_captured_at)), found: $($superseding.com_captured_at)."
  }
  if (Test-HasNonEmptyField -Record $superseding -Field "com_observed_modified_at") {
    $supersedingObservedAt = Test-IsoTimestamp -Issues $issues -Record $superseding -Field "com_observed_modified_at" -Subject "$subject superseding record"
    if ($null -ne $supersedingObservedAt -and $null -ne $supersededCapturedAt -and $supersedingObservedAt -le $supersededCapturedAt) {
      Add-Issue $issues "$subject superseding record com_observed_modified_at must be later than the superseded record's com_captured_at ($($priorRecord.com_captured_at)); a supersession cannot observe change before the superseded capture, found: $($superseding.com_observed_modified_at)."
    }
  }
}

# Drift-scoped source IDs: only sources that drifted, were superseded, or supersede in this slice
# may anchor receipts, receipt-source links, or deferred updates.
$affectedSourceIds = @(@($driftEventSourceIds) + @($supersededSourceIds) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
$driftScopedSourceIds = @($affectedSourceIds + @($supersedingSourceIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }))

$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 2) {
  Add-Issue $issues "Drift slice must include at least two receipts (drift and supersession)."
}
if ($receipts.Count -ne ($driftEvents.Count + $supersessions.Count)) {
  Add-Issue $issues "Receipts must correspond one-to-one with drift events and supersessions; a receipt with no backing drift evidence is not allowed. Found $($receipts.Count) receipts for $($driftEvents.Count) drift events and $($supersessions.Count) supersessions."
}
$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
# Manifest-required columns, plus the Council receipt contract fields this story additionally pins.
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique
$sliceReceiptIds = @{}
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
    if ($sliceReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "Duplicate receipt ID in slice: $receiptId."
    } else {
      $sliceReceiptIds[$receiptId] = $true
    }
    if ($demoReceiptIds -contains $receiptId) {
      Add-Issue $issues "$subject collides with a reserved state-transition-demo receipt ID."
    }
  }

  if ($receiptVerbs -notcontains $receipt.com_verb) {
    Add-Issue $issues "$subject verb is not in manifest com_receiptverb vocabulary: $($receipt.com_verb)."
  }
  elseif ($receipt.com_verb -ne "source_drifted") {
    Add-Issue $issues "$subject must use verb source_drifted for Story 1.5 drift evidence, found: $($receipt.com_verb)."
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
    } else {
      $seenIdempotencyKeys[$idempotencyKey] = $true
    }
  }

  if ($receipt.com_append_only_locked -isnot [bool] -or -not $receipt.com_append_only_locked) {
    Add-Issue $issues "$subject com_append_only_locked must be strict boolean true."
  }
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 1.5 receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 1.5 receipts are local contract evidence only."
      }
    }
  }
}

foreach ($expectedReceiptId in @("CR-LOCAL-DRIFT-001", "CR-LOCAL-SUPERSEDE-001")) {
  if (-not $sliceReceiptIds.ContainsKey($expectedReceiptId)) {
    Add-Issue $issues "Drift slice must include receipt $expectedReceiptId."
  }
}
$supersedeReceipt = $receipts | Where-Object { $_.com_receipt_id -eq "CR-LOCAL-SUPERSEDE-001" } | Select-Object -First 1
if ($supersedeReceipt) {
  if ([string]$supersedeReceipt.com_before_state -ne "held") {
    Add-Issue $issues "Receipt CR-LOCAL-SUPERSEDE-001 com_before_state must be held, found: $($supersedeReceipt.com_before_state)."
  }
  if ([string]$supersedeReceipt.com_after_state -ne "superseded") {
    Add-Issue $issues "Receipt CR-LOCAL-SUPERSEDE-001 com_after_state must be superseded, found: $($supersedeReceipt.com_after_state)."
  }
}
$driftReceipt = $receipts | Where-Object { $_.com_receipt_id -eq "CR-LOCAL-DRIFT-001" } | Select-Object -First 1
if ($driftReceipt) {
  # Drift alone moves no status: the drift receipt records version evidence, not an extraction-status transition.
  foreach ($stateField in @("com_before_state", "com_after_state")) {
    if ($extractionStatuses -contains ([string]$driftReceipt.$stateField).Trim()) {
      Add-Issue $issues "Receipt CR-LOCAL-DRIFT-001 $stateField must record version evidence, not a bare extraction-status transition; drift alone moves no status, found: $($driftReceipt.$stateField)."
    }
  }
  $meetingDriftEvent = $driftEvents | Where-Object { $_.sourceRecord -eq "CSR-MANUAL-MEETING-001" } | Select-Object -First 1
  if ($meetingDriftEvent -and $null -ne $meetingDriftEvent.observedEvidence -and (Test-HasNonEmptyField -Record $meetingDriftEvent.observedEvidence -Field "com_source_version_ref")) {
    if (([string]$driftReceipt.com_after_state).IndexOf([string]$meetingDriftEvent.observedEvidence.com_source_version_ref, [System.StringComparison]::Ordinal) -lt 0) {
      Add-Issue $issues "Receipt CR-LOCAL-DRIFT-001 com_after_state must record the newly observed com_source_version_ref as drift evidence."
    }
  }
}

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
  if ($driftScopedSourceIds -notcontains [string]$link.com_source_record) {
    Add-Issue $issues "$linkSubject must bind a source that drifted, was superseded, or supersedes in this slice, found: $($link.com_source_record)."
  }
  if ($evidenceRoles -notcontains $link.com_evidence_role) {
    Add-Issue $issues "$linkSubject evidence role is not in manifest vocabulary: $($link.com_evidence_role)."
  }
  elseif ($link.com_evidence_role -ne "drift_evidence") {
    Add-Issue $issues "$linkSubject must use the drift_evidence role, found: $($link.com_evidence_role)."
  }
}
foreach ($receiptId in @($sliceReceiptIds.Keys)) {
  if (@($links | Where-Object { $_.com_receipt -eq $receiptId }).Count -lt 1) {
    Add-Issue $issues "Receipt $receiptId must be bound to its source evidence by at least one drift_evidence receipt source link."
  }
}
if (@($links | Where-Object { $_.com_receipt -eq "CR-LOCAL-DRIFT-001" -and $_.com_source_record -eq "CSR-MANUAL-MEETING-001" }).Count -lt 1) {
  Add-Issue $issues "Receipt CR-LOCAL-DRIFT-001 must be linked to the drifted source CSR-MANUAL-MEETING-001 with a drift_evidence role."
}
if (@($links | Where-Object { $_.com_receipt -eq "CR-LOCAL-SUPERSEDE-001" -and $_.com_source_record -eq "CSR-OUTLOOK-THREAD-MOCK-001" }).Count -lt 1) {
  Add-Issue $issues "Receipt CR-LOCAL-SUPERSEDE-001 must be linked to the superseded source CSR-OUTLOOK-THREAD-MOCK-001 with a drift_evidence role."
}
foreach ($supersedingId in @($supersedingSourceIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
  if (@($links | Where-Object { $_.com_source_record -eq $supersedingId }).Count -lt 1) {
    Add-Issue $issues "Superseding record $supersedingId must be bound to its supersession receipt by a drift_evidence receipt source link."
  }
}

$flaggedItems = @($run.workItemsFlaggedForReview | Where-Object { $null -ne $_ })
$unaffectedItems = @($run.workItemsUnaffected | Where-Object { $null -ne $_ })
if ($flaggedItems.Count -ne 1) {
  Add-Issue $issues "Review flagging must be targeted: exactly one Work Item flagged for review, found $($flaggedItems.Count)."
}
$flaggedWorkItemIds = @()
foreach ($flag in $flaggedItems) {
  $flagWorkItemId = [string]$flag.workItem
  $subject = "Review flag $flagWorkItemId"
  $flaggedWorkItemIds += $flagWorkItemId

  if ([string]::IsNullOrWhiteSpace($flagWorkItemId) -or $knownWorkItemIds -notcontains $flagWorkItemId) {
    Add-Issue $issues "Review flag references an unknown Work Item: $flagWorkItemId."
  }
  else {
    $flaggedItemSourceIds = @()
    if ($workItemSourceIdsByItem.ContainsKey($flagWorkItemId)) {
      $flaggedItemSourceIds = @($workItemSourceIdsByItem[$flagWorkItemId])
    }
    if (@($flaggedItemSourceIds | Where-Object { $affectedSourceIds -contains $_ }).Count -lt 1) {
      Add-Issue $issues "$subject must target a Work Item linked (in any source role) to a source that drifted or was superseded in this slice; linked sources are: $($flaggedItemSourceIds -join ', ')."
    }
  }
  if (-not (Test-HasNonEmptyField -Record $flag -Field "reason")) {
    Add-Issue $issues "$subject must carry a non-empty reason."
  }
  if (-not (Test-HasNonEmptyField -Record $flag -Field "flagMechanism")) {
    Add-Issue $issues "$subject must carry a non-empty flagMechanism."
  }
  if (-not (Test-HasNonEmptyField -Record $flag -Field "flaggedBy") -or -not $sliceReceiptIds.ContainsKey([string]$flag.flaggedBy)) {
    Add-Issue $issues "$subject must name the slice receipt that backs the flag, found: $($flag.flaggedBy)."
  }
  if ($flag.stateGroupChangedInThisSlice -isnot [bool] -or $flag.stateGroupChangedInThisSlice) {
    Add-Issue $issues "$subject must state stateGroupChangedInThisSlice=false (strict boolean); Work Item state changes are receipt-gated to Epic 2."
  }
  Test-NoPriorMutationFields -Issues $issues -Record $flag -Subject $subject
}
if ($flaggedWorkItemIds -notcontains "CWI-LOCAL-MEETING-ACTION-001") {
  Add-Issue $issues "The drift-affected Work Item CWI-LOCAL-MEETING-ACTION-001 must be flagged for review."
}

$unaffectedWorkItemIds = @()
foreach ($unaffected in $unaffectedItems) {
  $unaffectedId = [string]$unaffected.workItem
  if ($unaffectedWorkItemIds -contains $unaffectedId -and -not [string]::IsNullOrWhiteSpace($unaffectedId)) {
    Add-Issue $issues "Duplicate unaffected-item note for Work Item: $unaffectedId."
  }
  $unaffectedWorkItemIds += $unaffectedId
  if ([string]::IsNullOrWhiteSpace($unaffectedId) -or $knownWorkItemIds -notcontains $unaffectedId) {
    Add-Issue $issues "Unaffected-item note references an unknown Work Item: $unaffectedId."
  }
  else {
    $unaffectedItemSourceIds = @()
    if ($workItemSourceIdsByItem.ContainsKey($unaffectedId)) {
      $unaffectedItemSourceIds = @($workItemSourceIdsByItem[$unaffectedId])
    }
    if (@($unaffectedItemSourceIds | Where-Object { $affectedSourceIds -contains $_ }).Count -lt 1) {
      Add-Issue $issues "Unaffected-item note must reference a Work Item linked to a drifted or superseded source: $unaffectedId."
    }
  }
  if ($flaggedWorkItemIds -contains $unaffectedId) {
    Add-Issue $issues "Work Item cannot be both flagged for review and noted unaffected: $unaffectedId."
  }
  if (-not (Test-HasNonEmptyField -Record $unaffected -Field "note")) {
    Add-Issue $issues "Unaffected-item entry must carry a non-empty note: $unaffectedId."
  }
  Test-NoPriorMutationFields -Issues $issues -Record $unaffected -Subject "Unaffected-item note $unaffectedId"
}
foreach ($coverageItemId in @($workItemSourceIdsByItem.Keys)) {
  $coverageSourceIds = @($workItemSourceIdsByItem[$coverageItemId] | Where-Object { $affectedSourceIds -contains $_ })
  if ($coverageSourceIds.Count -ge 1) {
    if ($flaggedWorkItemIds -notcontains $coverageItemId -and $unaffectedWorkItemIds -notcontains $coverageItemId) {
      Add-Issue $issues "Work Item $coverageItemId linked to drifted or superseded source $($coverageSourceIds -join ', ') must be either flagged for review or explicitly noted unaffected."
    }
  }
}

$sourceUpdatesDeferred = @($run.sourceUpdatesDeferred | Where-Object { $null -ne $_ })
foreach ($deferred in $sourceUpdatesDeferred) {
  Test-NoPriorMutationFields -Issues $issues -Record $deferred -Subject "Deferred source update $($deferred.sourceRecord)"
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "sourceRecord")) {
    Add-Issue $issues "Deferred source update must name its sourceRecord."
  }
  elseif ($driftScopedSourceIds -notcontains [string]$deferred.sourceRecord) {
    Add-Issue $issues "Deferred source update must name a source that drifted, was superseded, or supersedes in this slice, found: $($deferred.sourceRecord)."
  }
}
foreach ($sourceId in @(@($driftEventSourceIds) + @($supersededSourceIds) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)) {
  $deferred = $sourceUpdatesDeferred | Where-Object { $_.sourceRecord -eq $sourceId } | Select-Object -First 1
  if (-not $deferred -or -not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Missing deferred source update entry for $sourceId."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred source update for $sourceId must state that the live mutation is receipt-gated."
  }
}
foreach ($supersededId in $supersededSourceIds) {
  $deferred = $sourceUpdatesDeferred | Where-Object { $_.sourceRecord -eq $supersededId } | Select-Object -First 1
  if ($deferred -and ([string]$deferred.deferredUpdate -notmatch "superseded")) {
    Add-Issue $issues "Deferred source update for $supersededId must record the pending superseded extraction status."
  }
}

$workItemStateChangesDeferred = @($run.workItemStateChangesDeferred | Where-Object { $null -ne $_ })
foreach ($deferred in $workItemStateChangesDeferred) {
  Test-NoPriorMutationFields -Issues $issues -Record $deferred -Subject "Deferred Work Item state change $($deferred.workItem)"
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "workItem")) {
    Add-Issue $issues "Deferred Work Item state change must name its workItem."
  }
  elseif ($knownWorkItemIds -notcontains [string]$deferred.workItem) {
    Add-Issue $issues "Deferred Work Item state change references an unknown Work Item: $($deferred.workItem)."
  }
}
foreach ($flagWorkItemId in @($flaggedWorkItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
  $deferred = $workItemStateChangesDeferred | Where-Object { $_.workItem -eq $flagWorkItemId } | Select-Object -First 1
  if (-not $deferred -or -not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Missing deferred Work Item state change entry for flagged Work Item $flagWorkItemId."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred Work Item state change for $flagWorkItemId must state that any state move is receipt-gated."
  }
}

foreach ($criterion in @(1, 2)) {
  $mapping = @($drift.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
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
  Write-Host "Source drift and supersession slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Source drift and supersession slice validation succeeded."
Write-Host "Drift events: $($driftEvents.Count)"
Write-Host "Supersessions: $($supersessions.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "Work Items flagged for review: $($flaggedItems.Count)"
Write-Host "SOURCE_DRIFT_SUPERSESSION_SLICE_VALIDATE_OK"
