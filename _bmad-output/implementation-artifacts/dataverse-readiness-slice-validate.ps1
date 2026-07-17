param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$ReadinessSlicePath = "$PSScriptRoot\dataverse-readiness-slice.json",
  [string]$DecisionPacketPath = "$PSScriptRoot\tenant-decision-packet.json",
  [string]$SprintStatusPath = "$PSScriptRoot\sprint-status.yaml",
  [string]$ManualSlicePath = "$PSScriptRoot\manual-source-record-slice.json",
  [string]$OutlookSlicePath = "$PSScriptRoot\outlook-source-reference-slice.json",
  [string]$Story13ExtractionPath = "$PSScriptRoot\proposed-work-item-extraction-slice.json",
  [string]$Story14ExtractionPath = "$PSScriptRoot\zero-multi-item-extraction-slice.json",
  [string]$DriftSlicePath = "$PSScriptRoot\source-drift-supersession-slice.json",
  [string]$WorkItemShellSlicePath = "$PSScriptRoot\work-item-execution-shell-slice.json",
  [string]$ApprovalSlicePath = "$PSScriptRoot\approval-boundaries-slice.json",
  [string]$ReceiptStateSlicePath = "$PSScriptRoot\receipt-backed-state-changes-slice.json",
  [string]$MemorySlicePath = "$PSScriptRoot\memory-candidates-slice.json",
  [string]$DemoEvidencePath = "$PSScriptRoot\state-transition-demo-evidence.json",
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

# ============================================================
# Self-test mode: corrupt a temp copy of the slice and confirm
# the validator FAILS on it. Encodes the story spec requirement
# "Verify a corrupted slice copy FAILS before finishing" as a
# repeatable regression guard. The default invocation (no
# -SelfTest) is unchanged and still emits
# DATAVERSE_READINESS_SLICE_VALIDATE_OK on success.
# ============================================================
if ($SelfTest) {
  if (-not (Test-Path -LiteralPath $ReadinessSlicePath)) {
    throw "SelfTest requires the genuine readiness slice at: $ReadinessSlicePath"
  }
  $selfExe = $PSCommandPath
  if ([string]::IsNullOrWhiteSpace($selfExe)) {
    throw "SelfTest could not resolve its own script path."
  }

  # Baseline: the genuine slice must pass before any corruption.
  $genuineArgs = @("-NoProfile", "-File", $selfExe, "-ReadinessSlicePath", $ReadinessSlicePath)
  & pwsh @genuineArgs | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "SelfTest FAILED: the genuine slice does not pass (exit $LASTEXITCODE); no baseline to corrupt."
    exit 1
  }

  # Corrupt a temp copy by flipping the strict guard writeScriptsDisabled to
  # false. This is a mandatory guard the validator must reject, so a corrupted
  # copy that still passes proves the guard is not enforced.
  $tempSlice = [System.IO.Path]::GetTempFileName()
  Copy-Item -LiteralPath $ReadinessSlicePath -Destination $tempSlice -Force
  try {
    $tempJson = Get-Content -LiteralPath $tempSlice -Raw | ConvertFrom-Json
    $tempJson.guards.writeScriptsDisabled = $false
    $tempJson | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempSlice -NoNewline

    $corruptArgs = @("-NoProfile", "-File", $selfExe, "-ReadinessSlicePath", $tempSlice)
    $corruptOutput = (& pwsh @corruptArgs 2>&1) -join "`n"
    $corruptExit = $LASTEXITCODE
    if ($corruptExit -eq 0) {
      Write-Host "SelfTest FAILED: the corrupted copy (writeScriptsDisabled=false) passed validation; the mandatory guard is not enforced."
      Write-Host $corruptOutput
      exit 1
    }
    if ($corruptOutput -notmatch "writeScriptsDisabled") {
      Write-Host "SelfTest FAILED: the corrupted copy failed for an unrelated reason; the writeScriptsDisabled guard did not trigger."
      Write-Host $corruptOutput
      exit 1
    }
    Write-Host "Dataverse readiness slice self-test succeeded: corrupted copy (writeScriptsDisabled=false) correctly failed (exit $corruptExit)."
    Write-Host "DATAVERSE_READINESS_SLICE_SELFTEST_OK"
    exit 0
  }
  finally {
    if (Test-Path -LiteralPath $tempSlice) { Remove-Item -LiteralPath $tempSlice -Force }
  }
}

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

  if ($null -eq $Record) { return $false }
  if (@($Record.PSObject.Properties.Name) -notcontains $Field) {
    return $false
  }
  if ($null -eq $Record.$Field -or [string]::IsNullOrWhiteSpace([string]$Record.$Field)) {
    return $false
  }
  return $true
}

function Test-StrictBooleanTrue {
  param(
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$Field
  )

  if ($null -eq $Record) { return $false }
  if (-not ($Record.PSObject.Properties.Name -contains $Field)) { return $false }
  return ($Record.$Field -is [bool] -and $Record.$Field)
}

function Read-JsonInput {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  try {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  }
  catch {
    Write-Host "Dataverse readiness slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

function Collect-Ids {
  param(
    [Parameter(Mandatory = $true)]$Node,
    [Parameter(Mandatory = $true)][string]$Pattern
  )

  $ids = [System.Collections.Generic.List[string]]::new()
  if ($null -eq $Node) {
    return @($ids)
  }
  $json = ConvertTo-Json $Node -Depth 20 -Compress
  $matches = [regex]::Matches($json, $Pattern)
  foreach ($m in $matches) {
    $ids.Add($m.Value) | Out-Null
  }
  @($ids)
}

# ============================================================
# Input loading
# ============================================================

$requiredInputs = @(
  $ManifestPath,
  $ReadinessSlicePath,
  $DecisionPacketPath,
  $SprintStatusPath,
  $ManualSlicePath,
  $OutlookSlicePath,
  $Story13ExtractionPath,
  $Story14ExtractionPath,
  $DriftSlicePath,
  $WorkItemShellSlicePath,
  $ApprovalSlicePath,
  $ReceiptStateSlicePath,
  $MemorySlicePath,
  $DemoEvidencePath
)
foreach ($path in $requiredInputs) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required Dataverse readiness validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$readiness = Read-JsonInput -Path $ReadinessSlicePath
$decisionPacket = Read-JsonInput -Path $DecisionPacketPath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$driftSlice = Read-JsonInput -Path $DriftSlicePath
$workItemShellSlice = Read-JsonInput -Path $WorkItemShellSlicePath
$approvalSlice = Read-JsonInput -Path $ApprovalSlicePath
$receiptStateSlice = Read-JsonInput -Path $ReceiptStateSlicePath
$memorySlice = Read-JsonInput -Path $MemorySlicePath
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath
$rawSliceText = Get-Content -LiteralPath $ReadinessSlicePath -Raw
$rawManifestText = Get-Content -LiteralPath $ManifestPath -Raw
$issues = [System.Collections.Generic.List[string]]::new()

# ============================================================
# Vocabulary harvest from manifest
# ============================================================

$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
foreach ($vocabulary in @(
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptverb"; Values = $receiptVerbs }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

# Manifest table/column index for story-scoped write policy checks.
$manifestTables = @($manifest.tables)
$manifestTableNames = @($manifestTables | ForEach-Object { [string]$_.schemaName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$manifestColumnsByTable = @{}
foreach ($table in $manifestTables) {
  $tname = [string]$table.schemaName
  $cols = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($col in @($table.columns)) {
    [void]$cols.Add([string]$col.name)
  }
  $manifestColumnsByTable[$tname] = $cols
}
if ($manifestTableNames.Count -eq 0) {
  Add-Issue $issues "No tables could be derived from dataverse-mvp-schema-manifest.json; story-scoped table checks would silently no-op."
}

# Manifest concrete tenant target values — the slice must NOT fabricate these.
$manifestEnvId = [string]$manifest.target.environmentId
$manifestOrgId = [string]$manifest.target.organizationId
$manifestEnvUrl = [string]$manifest.target.environmentUrl
$manifestEnvUniqueName = [string]$manifest.target.environmentUniqueName
if ([string]::IsNullOrWhiteSpace($manifestEnvId) -or [string]::IsNullOrWhiteSpace($manifestOrgId)) {
  Add-Issue $issues "dataverse-mvp-schema-manifest.json must carry non-empty target.environmentId and target.organizationId for the no-fabricated-tenant-value tripwire."
}

# ============================================================
# Cross-slice ID harvest (MINTED vs REFERENCED)
# ============================================================
# This slice mints no CWI/CR/CSR ids (it is a readiness contract, not a
# receipt/work-item/source event slice). It REFERENCES existing ids from
# sibling slices as example rows in scope of future writes. The harvest below
# builds the universe of resolvable sibling ids; every id the slice references
# must resolve here, and any CWI-LOCAL/CR-LOCAL/CSR id the slice declares as
# minted would have to be unique across this universe (there should be none).

$siblingSlices = @(
  $manualSlice,
  $outlookSlice,
  $story13Extraction,
  $story14Extraction,
  $driftSlice,
  $workItemShellSlice,
  $approvalSlice,
  $receiptStateSlice,
  $memorySlice
)
$priorCwiIds = [System.Collections.Generic.HashSet[string]]::new()
$priorCrIds = [System.Collections.Generic.HashSet[string]]::new()
$priorCsrIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($slice in $siblingSlices) {
  foreach ($id in (Collect-Ids -Node $slice -Pattern "CWI-[A-Za-z0-9-]+")) { [void]$priorCwiIds.Add($id) }
  foreach ($id in (Collect-Ids -Node $slice -Pattern "CR-[A-Za-z0-9-]+")) { [void]$priorCrIds.Add($id) }
  foreach ($id in (Collect-Ids -Node $slice -Pattern "CSR-[A-Za-z0-9-]+")) { [void]$priorCsrIds.Add($id) }
}
foreach ($id in @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
  [void]$priorCrIds.Add([string]$id)
}
foreach ($id in @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
  [void]$priorCwiIds.Add([string]$id)
}
$resolvableIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($id in @($priorCwiIds + $priorCrIds + $priorCsrIds)) { [void]$resolvableIds.Add($id) }

# Per-slice id map: for each sibling slice file, the set of CWI/CR/CSR ids it
# contains. Used to verify that referencedIds[].sourceSlice actually names the
# file the id lives in (bound attribution, not decorative prose).
$sliceFileByName = @{
  "manual-source-record-slice.json" = $manualSlice
  "outlook-source-reference-slice.json" = $outlookSlice
  "proposed-work-item-extraction-slice.json" = $story13Extraction
  "zero-multi-item-extraction-slice.json" = $story14Extraction
  "source-drift-supersession-slice.json" = $driftSlice
  "work-item-execution-shell-slice.json" = $workItemShellSlice
  "approval-boundaries-slice.json" = $approvalSlice
  "receipt-backed-state-changes-slice.json" = $receiptStateSlice
  "memory-candidates-slice.json" = $memorySlice
}
$idsBySliceFile = @{}
foreach ($fileName in @($sliceFileByName.Keys)) {
  $sliceObj = $sliceFileByName[$fileName]
  $sliceIds = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($id in (Collect-Ids -Node $sliceObj -Pattern "CWI-[A-Za-z0-9-]+")) { [void]$sliceIds.Add($id) }
  foreach ($id in (Collect-Ids -Node $sliceObj -Pattern "CR-[A-Za-z0-9-]+")) { [void]$sliceIds.Add($id) }
  foreach ($id in (Collect-Ids -Node $sliceObj -Pattern "CSR-[A-Za-z0-9-]+")) { [void]$sliceIds.Add($id) }
  $idsBySliceFile[$fileName] = $sliceIds
}

if ($priorCsrIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be loaded from sibling slices; cross-slice reference checks would silently no-op."
}
if ($priorCwiIds.Count -eq 0) {
  Add-Issue $issues "No Work Item IDs could be loaded from sibling slices; cross-slice reference checks would silently no-op."
}
if ($priorCrIds.Count -eq 0) {
  Add-Issue $issues "No Receipt IDs could be loaded from sibling slices; cross-slice reference checks would silently no-op."
}

# ============================================================
# Real epic story keys harvested from sprint-status.yaml
# ============================================================

$realStoryKeys = [System.Collections.Generic.HashSet[string]]::new()
$sprintStatusLines = Get-Content -LiteralPath $SprintStatusPath
foreach ($line in $sprintStatusLines) {
  if ($line -match '^\s+([0-9]+-[0-9]+-[a-z0-9-]+):\s') {
    [void]$realStoryKeys.Add($matches[1])
  }
}
# Also accept the sibling-slice storyKey values as resolvable story keys so the
# story-scoped mapping is checked against the actual implemented epic stories.
foreach ($slice in $siblingSlices) {
  $sk = [string]$slice.storyKey
  if (-not [string]::IsNullOrWhiteSpace($sk)) {
    [void]$realStoryKeys.Add($sk)
  }
}
if ($realStoryKeys.Count -eq 0) {
  Add-Issue $issues "No real epic story keys could be harvested from sprint-status.yaml or sibling slices; story-scoped mapping checks would silently no-op."
}

# ============================================================
# Slice header
# ============================================================

if ($readiness.storyKey -ne "5-5-validate-dataverse-mvp-operational-store-readiness") {
  Add-Issue $issues "Dataverse readiness slice storyKey must be 5-5-validate-dataverse-mvp-operational-store-readiness, found: $($readiness.storyKey)."
}
if ([string]$readiness.status -notmatch "^local-contract") {
  Add-Issue $issues "Dataverse readiness slice status must declare local contract evidence, found: $($readiness.status)."
}

# ============================================================
# Guards — all required, all strict boolean true
# ============================================================

$requiredGuards = @(
  "noTenantWrites",
  "noOutboundAction",
  "writeScriptsDisabled",
  "preflightEvidenceDeferredToTenant",
  "noApprovalReceiptFabricated",
  "fullShapeNotForcedUpfront",
  "schemaWritesTiedToStoryScope",
  "rollbackAuditBoundaryPerPlannedWriteScope",
  "receiptsAreLocalContractEvidenceOnly",
  "noLivePacCallInThisSlice"
)
foreach ($guard in $requiredGuards) {
  if (-not ($readiness.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Dataverse readiness slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($readiness.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Dataverse readiness guard must be boolean true: $($guardProperty.Name)."
  }
}

# ============================================================
# Run block
# ============================================================

$run = $readiness.dataverseReadinessRun
if ($null -eq $run) {
  Add-Issue $issues "Dataverse readiness slice must carry a dataverseReadinessRun block."
  Write-Host "Dataverse readiness slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

# Run header.
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Dataverse readiness run must declare a runId."
}
# RunId collision against every sibling slice's run block, regardless of property name.
$siblingRunIds = @()
foreach ($slice in $siblingSlices) {
  foreach ($prop in @($slice.PSObject.Properties)) {
    if ($null -ne $prop.Value -and $prop.Value.PSObject.Properties.Name -contains "runId") {
      $siblingRunIds += [string]$prop.Value.runId
    }
  }
}
if (@($siblingRunIds | Where-Object { $_ -eq [string]$run.runId }).Count -gt 0) {
  Add-Issue $issues "Dataverse readiness run must use a new local runId, not a sibling slice runId: $($run.runId)."
}

if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Dataverse readiness run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains [string]$run.actorType) {
  Add-Issue $issues "Dataverse readiness run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Dataverse readiness run must carry a non-empty ${field}."
  }
}
if ([string]$run.inputManifestRef -ne "dataverse-mvp-schema-manifest.json") {
  Add-Issue $issues "Dataverse readiness run inputManifestRef must reference the committed dataverse-mvp-schema-manifest.json, found: $($run.inputManifestRef)."
}
if ([string]$run.inputDecisionPacketRef -ne "tenant-decision-packet.json") {
  Add-Issue $issues "Dataverse readiness run inputDecisionPacketRef must reference the committed tenant-decision-packet.json, found: $($run.inputDecisionPacketRef)."
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "proposed-work-item-extraction-slice.json", "zero-multi-item-extraction-slice.json", "source-drift-supersession-slice.json")) {
  if (@($run.inputSourceRecordsFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Dataverse readiness run must reference $inputSlice as an input."
  }
}

# Decision policy — all required entries strict boolean true.
$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Dataverse readiness run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @(
    "preflightMustProveExpectedEnvironmentAndOrganizationBeforeAnyWrite",
    "writeScriptsStayDisabledUntilDougApprovesSandboxWritesAndPublisherPrefix",
    "noApprovalReceiptIsFabricatedWhileApprovalsArePending",
    "schemaWritesTiedToCurrentStoryNeededTablesColumnsRelationshipsViews",
    "dryRunManifestMayDescribeFullTargetShapeWithoutForcingItUpfront",
    "rollbackAndAuditBoundaryStatedPerPlannedWriteScope",
    "liveDataverseMutationReceiptGatedToEpic2Story23",
    "receiptsAreLocalContractEvidenceOnly"
  )) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Dataverse readiness run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Dataverse readiness run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# ============================================================
# Preflight contract — present-and-deferred, no fabricated tenant values
# ============================================================

$preflight = $run.preflightContract
if ($null -eq $preflight) {
  Add-Issue $issues "Dataverse readiness run must carry a preflightContract block."
}
else {
  if ([string]$preflight.evidenceState -ne "deferred-to-tenant") {
    Add-Issue $issues "preflightContract.evidenceState must be deferred-to-tenant, found: $($preflight.evidenceState)."
  }
  if ([string]$preflight.verificationMarker -ne "VERIFY IN TENANT") {
    Add-Issue $issues "preflightContract.verificationMarker must be 'VERIFY IN TENANT', found: $($preflight.verificationMarker)."
  }
  if (-not (Test-StrictBooleanTrue -Record $preflight -Field "noLivePacCallPerformed")) {
    Add-Issue $issues "preflightContract.noLivePacCallPerformed must be strict boolean true; no live pac call is allowed in this slice."
  }

  $expectedCommands = @("pac auth who", "pac env who", "pac env list-settings")
  # Each preflight command must pin the specific SHAPE fields the live preflight
  # is required to prove (story 5.5: environment ID, organization ID, user
  # context fields, environment settings). These are the contract vocabulary
  # the story mandates, not hardcoded id bindings.
  $preflightRequiredShapeFields = @{
    "pac auth who" = @("userContextUPN", "loggedInUser", "tenantId")
    "pac env who" = @("environmentId", "organizationId")
    "pac env list-settings" = @("organizationSettings", "settingsHash", "adminMode")
  }
  $commands = @($preflight.expectedCommands | Where-Object { $null -ne $_ })
  if ($commands.Count -lt 3) {
    Add-Issue $issues "preflightContract.expectedCommands must include all three preflight commands (pac auth who, pac env who, pac env list-settings), found $($commands.Count)."
  }
  $seenCommands = @{}
  foreach ($cmd in $commands) {
    $cmdName = [string]$cmd.command
    $subject = "Preflight command $cmdName"
    if ([string]::IsNullOrWhiteSpace($cmdName)) {
      Add-Issue $issues "Preflight command must declare its command name."
      continue
    }
    if ($seenCommands.ContainsKey($cmdName)) {
      Add-Issue $issues "Duplicate preflight command: $cmdName."
    }
    else {
      $seenCommands[$cmdName] = $true
    }
    if ($expectedCommands -notcontains $cmdName) {
      Add-Issue $issues "$subject is not one of the expected preflight commands: $expectedCommands."
    }
    if (-not (Test-HasNonEmptyField -Record $cmd -Field "purpose")) {
      Add-Issue $issues "$subject must carry a non-empty purpose."
    }
    if ([string]$cmd.evidenceState -ne "deferred-to-tenant") {
      Add-Issue $issues "$subject evidenceState must be deferred-to-tenant, found: $($cmd.evidenceState)."
    }
    if (-not (Test-HasNonEmptyField -Record $cmd -Field "deferredTo")) {
      Add-Issue $issues "$subject must state a non-empty deferredTo gate."
    }
    elseif ([string]$cmd.deferredTo -notmatch "receipt-gated|read-only preflight|tenant-readiness") {
      Add-Issue $issues "$subject deferredTo must name the read-only preflight / receipt gate / tenant-readiness gate, found: $($cmd.deferredTo)."
    }

    $shape = $cmd.evidenceShape
    if ($null -eq $shape) {
      Add-Issue $issues "$subject must carry an evidenceShape block."
      continue
    }
    if (@($shape.PSObject.Properties).Count -lt 1) {
      Add-Issue $issues "$subject evidenceShape must declare at least one expected field."
    }
    foreach ($fieldProp in @($shape.PSObject.Properties)) {
      $fieldValue = [string]$fieldProp.Value
      # Every preflight shape field must be marked VERIFY IN TENANT and must NOT
      # be a fabricated concrete tenant value.
      if ($fieldValue -ne "VERIFY IN TENANT") {
        Add-Issue $issues "$subject evidenceShape field '$($fieldProp.Name)' must be the literal 'VERIFY IN TENANT' (deferred), found: $fieldValue."
      }
      # No preflight shape field may carry a concrete UUID-style tenant value.
      if ($fieldValue -match "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$") {
        Add-Issue $issues "$subject evidenceShape field '$($fieldProp.Name)' must not carry a fabricated concrete tenant id, found: $fieldValue."
      }
    }
    # Pin the command-specific required SHAPE fields so the contract is bound
    # to the identity and user-context the story mandates, without fabricating
    # their values. A slice that drops a required field from the shape cannot
    # pass — the "present-and-deferred" assertion must hold for every command.
    $requiredFields = $preflightRequiredShapeFields[$cmdName]
    if ($null -ne $requiredFields) {
      foreach ($reqField in $requiredFields) {
        if (-not ($shape.PSObject.Properties.Name -contains $reqField)) {
          Add-Issue $issues "$subject evidenceShape must declare the required field '$reqField' the live preflight proves."
        }
      }
    }
  }
  foreach ($missingCmd in @($expectedCommands | Where-Object { -not $seenCommands.ContainsKey($_) })) {
    Add-Issue $issues "preflightContract.expectedCommands must include: $missingCmd."
  }

  if (-not (Test-HasNonEmptyField -Record $preflight -Field "matchPolicy")) {
    Add-Issue $issues "preflightContract must declare a non-empty matchPolicy stating the live env/org ID match rule."
  }
  elseif ([string]$preflight.matchPolicy -notmatch "environmentId|organizationId|manifest") {
    Add-Issue $issues "preflightContract.matchPolicy must bind the live environment ID and organization ID match against dataverse-mvp-schema-manifest.json, found: $($preflight.matchPolicy)."
  }

  # No-fabricated-tenant-value tripwire: the slice JSON text MUST NOT contain
  # the manifest's concrete environmentId / organizationId / environmentUrl /
  # environmentUniqueName values. Any concrete tenant value here would be a
  # fabricated tenant fact and FAILS validation.
  if (-not [string]::IsNullOrWhiteSpace($manifestEnvId) -and $rawSliceText.Contains($manifestEnvId)) {
    Add-Issue $issues "preflightContract must not fabricate the manifest's concrete target.environmentId ($manifestEnvId); preflight values stay VERIFY IN TENANT."
  }
  if (-not [string]::IsNullOrWhiteSpace($manifestOrgId) -and $rawSliceText.Contains($manifestOrgId)) {
    Add-Issue $issues "preflightContract must not fabricate the manifest's concrete target.organizationId ($manifestOrgId); preflight values stay VERIFY IN TENANT."
  }
  if (-not [string]::IsNullOrWhiteSpace($manifestEnvUrl) -and $rawSliceText.Contains($manifestEnvUrl)) {
    Add-Issue $issues "Dataverse readiness slice must not fabricate the manifest's concrete target.environmentUrl ($manifestEnvUrl); preflight values stay VERIFY IN TENANT."
  }
  if (-not [string]::IsNullOrWhiteSpace($manifestEnvUniqueName) -and $rawSliceText.Contains($manifestEnvUniqueName)) {
    Add-Issue $issues "Dataverse readiness slice must not fabricate the manifest's concrete target.environmentUniqueName ($manifestEnvUniqueName); preflight values stay VERIFY IN TENANT."
  }
}

# ============================================================
# writeScriptsDisabled + no approval receipt fabricated
# ============================================================

if (-not (Test-StrictBooleanTrue -Record $readiness.guards -Field "writeScriptsDisabled")) {
  Add-Issue $issues "guard writeScriptsDisabled must be strict boolean true; write scripts must stay disabled until Doug approves."
}
if (-not (Test-StrictBooleanTrue -Record $readiness.guards -Field "noApprovalReceiptFabricated")) {
  Add-Issue $issues "guard noApprovalReceiptFabricated must be strict boolean true."
}

# No receipt may be fabricated anywhere in the slice: scan the raw slice text for
# any com_receipt_id field, and scan the run block for receipt collections. This
# is a general (not id-binding) rule: the slice mints no receipt rows at all.
if ($rawSliceText -match '"com_receipt_id"\s*:\s*"') {
  Add-Issue $issues "Dataverse readiness slice must not fabricate any approval receipt; a com_receipt_id field appears in the slice while approvals are still PENDING."
}
# Defensive: no live-write marker fields anywhere in the run block.
foreach ($forbiddenField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "liveWriteAt", "tenantWriteAt", "solutionPublishAt", "publishAllXmlAt")) {
  if ($run.PSObject.Properties.Name -contains $forbiddenField) {
    Add-Issue $issues "Dataverse readiness run must not carry live-write marker field '$forbiddenField'; this slice is local contract evidence only."
  }
}

# ============================================================
# Pending approvals — present as PENDING, no backing receipt
# ============================================================

$pendingApprovals = @($run.pendingApprovals | Where-Object { $null -ne $_ })
if ($pendingApprovals.Count -lt 2) {
  Add-Issue $issues "Dataverse readiness run must include at least the two pending approvals (dataverseSandboxWrites and publisherPrefix), found $($pendingApprovals.Count)."
}

$seenApprovalEntryIds = @{}
$seenApprovalDecisions = @{}
foreach ($approval in $pendingApprovals) {
  $approvalId = [string]$approval.approvalEntryId
  $subject = "Pending approval $approvalId"
  foreach ($field in @("approvalEntryId", "decision", "requiredBefore", "state", "requiredApprover", "question", "allowedValues", "receiptGate")) {
    if (-not (Test-HasNonEmptyField -Record $approval -Field $field)) {
      Add-Issue $issues "$subject must carry a non-empty ${field}."
    }
  }
  if ([string]::IsNullOrWhiteSpace($approvalId)) {
    Add-Issue $issues "Pending approval must declare its approvalEntryId."
  }
  else {
    if ($approvalId -notmatch "^APPR-LOCAL-") {
      Add-Issue $issues "$subject must use a story-local APPR-LOCAL-* identity (approval entries are not CWI/CR/CSR receipt rows), found: $approvalId."
    }
    if ($seenApprovalEntryIds.ContainsKey($approvalId)) {
      Add-Issue $issues "Duplicate approval entry id in slice: $approvalId."
    }
    else {
      $seenApprovalEntryIds[$approvalId] = $true
    }
  }
  if ([string]$approval.state -ne "PENDING") {
    Add-Issue $issues "$subject state must be PENDING; no approval is granted in this slice, found: $($approval.state)."
  }
  if ([string]$approval.requiredApprover -ne "Doug") {
    Add-Issue $issues "$subject requiredApprover must be Doug (human approval owner), found: $($approval.requiredApprover)."
  }
  if ([string]$approval.receiptGate -notmatch "no approval receipt|not fabricated|receipt-gated|stay disabled") {
    Add-Issue $issues "$subject receiptGate must state that no approval receipt is fabricated and write scripts stay disabled, found: $($approval.receiptGate)."
  }
  # No backing receipt may be fabricated.
  if ($approval.PSObject.Properties.Name -contains "backingReceiptId") {
    $backing = $approval.backingReceiptId
    if ($null -ne $backing -and -not [string]::IsNullOrWhiteSpace([string]$backing)) {
      Add-Issue $issues "$subject backingReceiptId must be null; no approval receipt is fabricated while the approval is PENDING, found: $backing."
    }
  }
  # writeScriptsDisabledUntilApproved must be strict boolean true when present.
  if ($approval.PSObject.Properties.Name -contains "writeScriptsDisabledUntilApproved") {
    if (-not (Test-StrictBooleanTrue -Record $approval -Field "writeScriptsDisabledUntilApproved")) {
      Add-Issue $issues "$subject writeScriptsDisabledUntilApproved must be strict boolean true."
    }
  }
  $decisionName = [string]$approval.decision
  if (-not [string]::IsNullOrWhiteSpace($decisionName)) {
    if ($seenApprovalDecisions.ContainsKey($decisionName)) {
      Add-Issue $issues "Duplicate pending approval decision in slice: $decisionName."
    }
    else {
      $seenApprovalDecisions[$decisionName] = $true
    }
  }
}
# The two specific Doug approvals required by AC1.
if (-not $seenApprovalDecisions.ContainsKey("dataverseSandboxWrites")) {
  Add-Issue $issues "Dataverse readiness run must carry a PENDING dataverseSandboxWrites approval (Doug approval required before write scripts enable)."
}
if (-not $seenApprovalDecisions.ContainsKey("publisherPrefix")) {
  Add-Issue $issues "Dataverse readiness run must carry a PENDING publisherPrefix approval (Doug approval required before solution creation)."
}

# Cross-check against the tenant decision packet: the two pending approvals here
# must correspond to real decisions in the committed packet, so the readiness
# slice is bound to the real approval surface (not an invented one).
foreach ($decisionName in @($seenApprovalDecisions.Keys)) {
  if ($null -eq $decisionPacket.decisions.PSObject.Properties[$decisionName]) {
    Add-Issue $issues "Pending approval decision '$decisionName' must correspond to a real decision in tenant-decision-packet.json; the readiness slice must not invent an approval surface."
  }
}

# ============================================================
# Dry-run schema manifest — story-scoped write policy
# ============================================================

$dryRun = $run.dryRunSchemaManifest
if ($null -eq $dryRun) {
  Add-Issue $issues "Dataverse readiness run must carry a dryRunSchemaManifest block."
}
else {
  if ([string]$dryRun.manifestRef -ne "dataverse-mvp-schema-manifest.json") {
    Add-Issue $issues "dryRunSchemaManifest.manifestRef must reference the committed dataverse-mvp-schema-manifest.json, found: $($dryRun.manifestRef)."
  }
  if ([string]$dryRun.manifestVersion -ne [string]$manifest.manifestVersion) {
    Add-Issue $issues "dryRunSchemaManifest.manifestVersion must equal the committed manifest version ($($manifest.manifestVersion)), found: $($dryRun.manifestVersion)."
  }
  if (-not (Test-StrictBooleanTrue -Record $dryRun -Field "fullShapeNotForcedUpfront")) {
    Add-Issue $issues "dryRunSchemaManifest.fullShapeNotForcedUpfront must be strict boolean true; the full target shape must not be forced upfront."
  }
  if (-not (Test-HasNonEmptyField -Record $dryRun -Field "fullShapeDescription")) {
    Add-Issue $issues "dryRunSchemaManifest must carry a non-empty fullShapeDescription."
  }

  $policyEntries = @($dryRun.storyScopedWritePolicy | Where-Object { $null -ne $_ })
  if ($policyEntries.Count -eq 0) {
    Add-Issue $issues "dryRunSchemaManifest.storyScopedWritePolicy must be non-empty; the story-scoped mapping must cover at least one future implementation story."
  }

  $seenPolicyStoryKeys = @{}
  foreach ($entry in $policyEntries) {
    $storyKey = [string]$entry.storyKey
    $subject = "Story-scoped write policy $storyKey"
    if ([string]::IsNullOrWhiteSpace($storyKey)) {
      Add-Issue $issues "Story-scoped write policy entry must declare its storyKey."
    }
    else {
      if (-not $realStoryKeys.Contains($storyKey)) {
        Add-Issue $issues "$subject storyKey must reference a real epic story (from sprint-status.yaml or a sibling slice), found: $storyKey."
      }
      if ($seenPolicyStoryKeys.ContainsKey($storyKey)) {
        Add-Issue $issues "Duplicate story-scoped write policy entry for story: $storyKey."
      }
      else {
        $seenPolicyStoryKeys[$storyKey] = $true
      }
    }

    $tables = @($entry.tables | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    if ($tables.Count -eq 0) {
      Add-Issue $issues "$subject must declare at least one table."
    }
    foreach ($tname in $tables) {
      if ($manifestTableNames -notcontains $tname) {
        Add-Issue $issues "$subject table '$tname' does not exist in dataverse-mvp-schema-manifest.json."
      }
    }

    $columnsByTable = $entry.columnsByTable
    if ($null -ne $columnsByTable) {
      foreach ($colProp in @($columnsByTable.PSObject.Properties)) {
        $ctable = $colProp.Name
        if ($manifestTableNames -notcontains $ctable) {
          Add-Issue $issues "$subject columnsByTable key '$ctable' does not exist in dataverse-mvp-schema-manifest.json."
          continue
        }
        $manifestCols = $manifestColumnsByTable[$ctable]
        foreach ($colName in @($colProp.Value | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })) {
          if (-not $manifestCols.Contains($colName)) {
            Add-Issue $issues "$subject column '$ctable.$colName' does not exist in dataverse-mvp-schema-manifest.json."
          }
        }
      }
      # Every table declared must have a columnsByTable entry (no table listed without a column mapping).
      foreach ($tname in $tables) {
        if (-not ($columnsByTable.PSObject.Properties.Name -contains $tname)) {
          Add-Issue $issues "$subject table '$tname' is listed but has no columnsByTable entry; every scoped table must map its columns."
        }
      }
    }
    else {
      Add-Issue $issues "$subject must carry a columnsByTable mapping."
    }

    # Relationships, when present, must reference manifest tables.
    if ($entry.PSObject.Properties.Name -contains "relationships") {
      foreach ($rel in @($entry.relationships | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })) {
        if ($rel -notmatch "->") {
          Add-Issue $issues "$subject relationship '$rel' must use the 'from.column -> to.table' shape."
        }
        else {
          $relTables = [regex]::Matches($rel, "([a-zA-Z_][a-zA-Z0-9_]*)\.") | ForEach-Object { $_.Groups[1].Value }
          foreach ($relTable in @($relTables | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            if ($manifestTableNames -notcontains $relTable) {
              Add-Issue $issues "$subject relationship '$rel' references manifest-unknown table '$relTable'."
            }
          }
        }
      }
    }

    # exampleExistingRows are REFERENCED ids — they must resolve in the sibling harvest.
    if ($entry.PSObject.Properties.Name -contains "exampleExistingRows") {
      foreach ($rowId in @($entry.exampleExistingRows | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })) {
        if ([string]::IsNullOrWhiteSpace($rowId)) { continue }
        if (-not $resolvableIds.Contains($rowId)) {
          Add-Issue $issues "$subject exampleExistingRows references an id that does not resolve in any sibling slice or demo evidence: $rowId."
        }
      }
    }
  }
}

# ============================================================
# Rollback / audit boundaries — per planned write scope
# ============================================================

$boundaries = @($run.rollbackAuditBoundaries | Where-Object { $null -ne $_ })
if ($boundaries.Count -eq 0) {
  Add-Issue $issues "Dataverse readiness run must carry at least one rollbackAuditBoundaries entry."
}
$seenBoundaryStoryKeys = @{}
$seenBoundaryScopeKeys = @{}
foreach ($boundary in $boundaries) {
  $scope = [string]$boundary.plannedWriteScope
  $subject = "Rollback/audit boundary $scope"
  if ([string]::IsNullOrWhiteSpace($scope)) {
    Add-Issue $issues "Rollback/audit boundary must declare a non-empty plannedWriteScope."
  }
  foreach ($field in @("rollbackBoundary", "auditBoundary", "receiptGate")) {
    if (-not (Test-HasNonEmptyField -Record $boundary -Field $field)) {
      Add-Issue $issues "$subject must carry a non-empty ${field}."
    }
  }
  if (Test-HasNonEmptyField -Record $boundary -Field "rollbackBoundary") {
    if ([string]$boundary.rollbackBoundary -notmatch "roll back|append-only|supersession|solution|byte-identical|last append-only") {
      Add-Issue $issues "$subject rollbackBoundary must state a concrete rollback mechanism (append-only receipt boundary, supersession, or solution deletion), found: $($boundary.rollbackBoundary)."
    }
  }
  if (Test-HasNonEmptyField -Record $boundary -Field "auditBoundary") {
    if ([string]$boundary.auditBoundary -notmatch "receipt|audit|preflight|evidence") {
      Add-Issue $issues "$subject auditBoundary must state the audit/evidence trail (receipt or preflight), found: $($boundary.auditBoundary)."
    }
  }
  if (Test-HasNonEmptyField -Record $boundary -Field "receiptGate") {
    if ([string]$boundary.receiptGate -notmatch "receipt-gated|DRY RUN|writeScriptsDisabled|tenant decision packet") {
      Add-Issue $issues "$subject receiptGate must name the receipt gate, DRY RUN boundary, or tenant decision packet, found: $($boundary.receiptGate)."
    }
  }
  if ($boundary.PSObject.Properties.Name -contains "storyKey") {
    $bStoryKey = [string]$boundary.storyKey
    if (-not [string]::IsNullOrWhiteSpace($bStoryKey)) {
      if (-not $realStoryKeys.Contains($bStoryKey)) {
        Add-Issue $issues "$subject storyKey must reference a real epic story, found: $bStoryKey."
      }
      if ($seenBoundaryStoryKeys.ContainsKey($bStoryKey)) {
        Add-Issue $issues "Duplicate rollback/audit boundary storyKey: $bStoryKey."
      }
      else {
        $seenBoundaryStoryKeys[$bStoryKey] = $true
      }
    }
  }
  # exampleExistingRows on a boundary must resolve.
  if ($boundary.PSObject.Properties.Name -contains "exampleExistingRows") {
    foreach ($rowId in @($boundary.exampleExistingRows | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })) {
      if ([string]::IsNullOrWhiteSpace($rowId)) { continue }
      if (-not $resolvableIds.Contains($rowId)) {
        Add-Issue $issues "$subject exampleExistingRows references an id that does not resolve in any sibling slice or demo evidence: $rowId."
      }
    }
  }
  # writeScopeKey links this boundary to a writesDeferred entry so coverage is
  # derived per planned write scope, not counted.
  $bScopeKey = [string]$boundary.writeScopeKey
  if ([string]::IsNullOrWhiteSpace($bScopeKey)) {
    Add-Issue $issues "$subject must declare a writeScopeKey linking it to a writesDeferred entry."
  }
  else {
    if ($seenBoundaryScopeKeys.ContainsKey($bScopeKey)) {
      Add-Issue $issues "Duplicate rollback/audit boundary writeScopeKey: $bScopeKey."
    }
    else {
      $seenBoundaryScopeKeys[$bScopeKey] = $true
    }
  }
}
# The schema-apply boundary must be covered (the story is about Dataverse readiness before schema writes).
if (@($boundaries | Where-Object { [string]$_.plannedWriteScope -match "schema apply|dataverse-apply-mvp-schema" }).Count -lt 1) {
  Add-Issue $issues "rollbackAuditBoundaries must include a boundary for the Dataverse MVP schema apply (dataverse-apply-mvp-schema.ps1 with -ExecuteWrites)."
}

# ============================================================
# Referenced IDs block — every referenced id must resolve; idType must match prefix
# ============================================================

$referencedIds = @($run.referencedIds | Where-Object { $null -ne $_ })
if ($referencedIds.Count -eq 0) {
  Add-Issue $issues "Dataverse readiness run must carry a referencedIds block listing the sibling-slice ids this slice references; the cross-slice reference check would otherwise silently no-op."
}
$seenReferencedIds = @{}
foreach ($ref in $referencedIds) {
  $refId = [string]$ref.id
  $subject = "Referenced id $refId"
  if ([string]::IsNullOrWhiteSpace($refId)) {
    Add-Issue $issues "referencedIds entry must declare its id."
    continue
  }
  if ($seenReferencedIds.ContainsKey($refId)) {
    Add-Issue $issues "Duplicate referenced id: $refId."
  }
  else {
    $seenReferencedIds[$refId] = $true
  }
  if (-not $resolvableIds.Contains($refId)) {
    Add-Issue $issues "$subject does not resolve in any sibling slice or demo evidence; every referenced id must be a real existing Council id."
  }
  $idType = [string]$ref.idType
  $expectedPrefix = switch ($idType) {
    "CWI" { "^CWI-" }
    "CR" { "^CR-" }
    "CSR" { "^CSR-" }
    default { $null }
  }
  if ($null -eq $expectedPrefix) {
    Add-Issue $issues "$subject idType must be CWI, CR, or CSR, found: $idType."
  }
  elseif ($refId -cnotmatch $expectedPrefix) {
    Add-Issue $issues "$subject id '$refId' does not match its declared idType prefix ($idType)."
  }
  else {
    # idType must match the id's actual membership in the right harvested set.
    $membershipOk = switch ($idType) {
      "CWI" { $priorCwiIds.Contains($refId) }
      "CR" { $priorCrIds.Contains($refId) }
      "CSR" { $priorCsrIds.Contains($refId) }
    }
    if (-not $membershipOk) {
      Add-Issue $issues "$subject idType $idType does not match the id's harvested membership; $refId is not present as a $idType id in sibling slices."
    }
  }
  if (-not (Test-HasNonEmptyField -Record $ref -Field "sourceSlice")) {
    Add-Issue $issues "$subject must declare a non-empty sourceSlice."
  }
  else {
    $sourceSliceName = [string]$ref.sourceSlice
    if ($sourceSliceName -notmatch "\.json$") {
      Add-Issue $issues "$subject sourceSlice must name a sibling slice file, found: $sourceSliceName."
    }
    elseif (-not $idsBySliceFile.ContainsKey($sourceSliceName)) {
      Add-Issue $issues "$subject sourceSlice '$sourceSliceName' is not a known sibling slice file; the id must be attributed to the file it actually lives in."
    }
    else {
      $sourceIds = $idsBySliceFile[$sourceSliceName]
      if (-not $sourceIds.Contains($refId)) {
        Add-Issue $issues "$subject sourceSlice '$sourceSliceName' does not contain id '$refId'; the id was harvested from a different sibling slice. sourceSlice must name the file the id actually lives in."
      }
    }
  }
  if (-not (Test-HasNonEmptyField -Record $ref -Field "referenceRole")) {
    Add-Issue $issues "$subject must declare a non-empty referenceRole."
  }
}

# ============================================================
# Minted-ids uniqueness: this slice mints NO CWI/CR/CSR ids.
# Confirm by scanning the slice for CWI-LOCAL/CR-LOCAL/CSR ids that are NOT in
# the referencedIds set (i.e. declared as new/minted) — any such id must be
# unique across the sibling universe. Because this slice mints none, the set
# should be empty; if an id appears as minted it must not collide.
# ============================================================

$referencedIdSet = [System.Collections.Generic.HashSet[string]]::new()
foreach ($r in $referencedIds) { [void]$referencedIdSet.Add([string]$r.id) }

$mintedCandidates = @(
  (Collect-Ids -Node $readiness -Pattern "CWI-LOCAL-[A-Za-z0-9-]+") +
  (Collect-Ids -Node $readiness -Pattern "CR-LOCAL-[A-Za-z0-9-]+") +
  (Collect-Ids -Node $readiness -Pattern "CSR-[A-Za-z0-9-]+")
) | Sort-Object -Unique
foreach ($mintedId in $mintedCandidates) {
  if ($referencedIdSet.Contains($mintedId)) { continue }
  # This id is minted by the slice (not in the referenced set). It must not
  # collide with any existing sibling id.
  if ($resolvableIds.Contains($mintedId)) {
    Add-Issue $issues "Dataverse readiness slice mints id '$mintedId' that collides with an existing sibling-slice id; new ids must be unique across all slices."
  }
}

# ============================================================
# Writes deferred — every would-be live write named with its receipt gate
# ============================================================

$writesDeferred = @($run.writesDeferred | Where-Object { $null -ne $_ })
if ($writesDeferred.Count -eq 0) {
  Add-Issue $issues "Dataverse readiness run must carry a writesDeferred block naming every would-be live write with its receipt gate."
}
$writeDeferredScopeKeys = @{}
foreach ($deferred in $writesDeferred) {
  $subject = "Deferred write"
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredWrite")) {
    Add-Issue $issues "$subject must declare a non-empty deferredWrite."
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "receiptGate")) {
    Add-Issue $issues "$subject must declare a non-empty receiptGate."
  }
  elseif ([string]$deferred.receiptGate -notmatch "receipt-gated|read-only preflight|tenant-readiness|stay disabled|Doug appro") {
    Add-Issue $issues "$subject receiptGate must name the receipt gate / read-only preflight / Doug approval, found: $($deferred.receiptGate)."
  }
  if ([string]$deferred.evidenceState -ne "deferred-to-tenant") {
    Add-Issue $issues "$subject evidenceState must be deferred-to-tenant, found: $($deferred.evidenceState)."
  }
  # writeScopeKey links a live-write deferred entry to a rollback/audit boundary.
  # Read-only preflight entries (pac auth/env who/list-settings) do not need a
  # rollback boundary; every other deferred write MUST declare a writeScopeKey.
  $deferredWrite = [string]$deferred.deferredWrite
  if ($deferredWrite -match "preflight|pac auth who|pac env who|pac env list-settings") {
    continue
  }
  $wScopeKey = [string]$deferred.writeScopeKey
  if ([string]::IsNullOrWhiteSpace($wScopeKey)) {
    Add-Issue $issues "Deferred write '$deferredWrite' is a live write and must declare a writeScopeKey linking it to a rollback/audit boundary."
    continue
  }
  if ($writeDeferredScopeKeys.ContainsKey($wScopeKey)) {
    Add-Issue $issues "Duplicate writesDeferred writeScopeKey: $wScopeKey."
  }
  else {
    $writeDeferredScopeKeys[$wScopeKey] = $true
  }
}
# The live preflight and the schema apply must both be present as deferred writes.
if (@($writesDeferred | Where-Object { [string]$_.deferredWrite -match "preflight|pac auth who|pac env who|pac env list-settings" }).Count -lt 1) {
  Add-Issue $issues "writesDeferred must include the live preflight (pac auth who / pac env who / pac env list-settings) as a deferred write."
}
if (@($writesDeferred | Where-Object { [string]$_.deferredWrite -match "dataverse-apply-mvp-schema|schema apply|ExecuteWrites" }).Count -lt 1) {
  Add-Issue $issues "writesDeferred must include the dataverse-apply-mvp-schema.ps1 -ExecuteWrites schema apply as a deferred write."
}

# ============================================================
# Bidirectional boundary ↔ writesDeferred coverage (DERIVED, not counted)
# ============================================================
# Every planned write scope (writesDeferred writeScopeKey) must have a matching
# rollback/audit boundary, and every boundary must correspond to a planned
# write. This derives coverage per scope instead of counting ≥1 boundary.

foreach ($scopeKey in @($writeDeferredScopeKeys.Keys)) {
  if (-not $seenBoundaryScopeKeys.ContainsKey($scopeKey)) {
    Add-Issue $issues "writesDeferred writeScopeKey '$scopeKey' has no matching rollback/audit boundary; every planned write scope must have a boundary."
  }
}
foreach ($scopeKey in @($seenBoundaryScopeKeys.Keys)) {
  if (-not $writeDeferredScopeKeys.ContainsKey($scopeKey)) {
    Add-Issue $issues "rollback/audit boundary writeScopeKey '$scopeKey' has no matching writesDeferred entry; every boundary must correspond to a planned write."
  }
}

# ============================================================
# Acceptance mapping — AC 1 and AC 2
# ============================================================

foreach ($criterion in @(1, 2)) {
  $mapping = @($readiness.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
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

# ============================================================
# Decision
# ============================================================

if ($issues.Count -gt 0) {
  Write-Host "Dataverse readiness slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Dataverse readiness slice validation succeeded."
Write-Host "Preflight commands: $(@($run.preflightContract.expectedCommands).Count)"
Write-Host "Pending approvals: $($pendingApprovals.Count)"
Write-Host "Story-scoped write policy entries: $(@($run.dryRunSchemaManifest.storyScopedWritePolicy).Count)"
Write-Host "Rollback/audit boundaries: $($boundaries.Count)"
Write-Host "Referenced ids: $($referencedIds.Count)"
Write-Host "Deferred writes: $($writesDeferred.Count)"
Write-Host "DATAVERSE_READINESS_SLICE_VALIDATE_OK"
