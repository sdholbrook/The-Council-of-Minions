param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$SkillSlicePath = "$PSScriptRoot\skill-registry-slice.json"
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

function Invoke-CollectSiblingIds {
  # Recursively walk a parsed sibling slice JSON and harvest every canonical
  # Council id / idempotency key by property name, plus the demo-evidence
  # receiptIds array. This is the single source of truth for cross-slice
  # collision checks so they cover ALL co-located slices, not just named
  # siblings (Story 5.1 hard rule: ids unique across ALL slices).
  param(
    [Parameter(Mandatory = $false)][AllowNull()]$Node,
    [Parameter(Mandatory = $true)][hashtable]$WorkItems,
    [Parameter(Mandatory = $true)][hashtable]$Receipts,
    [Parameter(Mandatory = $true)][hashtable]$Keys,
    [Parameter(Mandatory = $true)][hashtable]$SourceRecords,
    [Parameter(Mandatory = $true)][hashtable]$Skills,
    [Parameter(Mandatory = $true)][hashtable]$Scenarios,
    [Parameter(Mandatory = $true)][hashtable]$RunIds
  )

  if ($null -eq $Node) { return }
  if ($Node -is [System.Collections.IList]) {
    foreach ($item in $Node) {
      Invoke-CollectSiblingIds -Node $item -WorkItems $WorkItems -Receipts $Receipts -Keys $Keys -SourceRecords $SourceRecords -Skills $Skills -Scenarios $Scenarios -RunIds $RunIds
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
        "com_council_skill_id" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $Skills[$id] = $true }
          break
        }
        "scenarioId" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $Scenarios[$id] = $true }
          break
        }
        "runId" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $RunIds[$id] = $true }
          break
        }
        "receiptIds" {
          if ($prop.Value -is [System.Collections.IList]) {
            foreach ($v in $prop.Value) { $id = [string]$v; if (-not [string]::IsNullOrWhiteSpace($id)) { $Receipts[$id] = $true } }
          }
          break
        }
        default {
          Invoke-CollectSiblingIds -Node $prop.Value -WorkItems $WorkItems -Receipts $Receipts -Keys $Keys -SourceRecords $SourceRecords -Skills $Skills -Scenarios $Scenarios -RunIds $RunIds
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
    Write-Host "Skill registry slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

foreach ($path in @($ManifestPath, $SkillSlicePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required skill registry validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$slice = Read-JsonInput -Path $SkillSlicePath
$issues = [System.Collections.Generic.List[string]]::new()

$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$recordStatuses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_recordstatus"
$authorityClasses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_authorityclass"
$evidenceRoles = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilreceiptsource" -ColumnName "com_evidence_role"

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_recordstatus"; Values = $recordStatuses },
    @{ Name = "com_authorityclass"; Values = $authorityClasses },
    @{ Name = "com_councilreceiptsource.com_evidence_role"; Values = $evidenceRoles }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

foreach ($requiredVerb in @("held", "policy_denied")) {
  if ($receiptVerbs -notcontains $requiredVerb) {
    Add-Issue $issues "Manifest com_receiptverb is missing a verb required by Story 5.1: $requiredVerb."
  }
}
foreach ($requiredResult in @("accepted", "rejected")) {
  if ($receiptResults -notcontains $requiredResult) {
    Add-Issue $issues "Manifest com_receiptresult is missing a result required by Story 5.1: $requiredResult."
  }
}
foreach ($requiredStatus in @("active", "deprecated", "suspended")) {
  if ($recordStatuses -notcontains $requiredStatus) {
    Add-Issue $issues "Manifest com_recordstatus is missing a status required by Story 5.1: $requiredStatus."
  }
}
foreach ($requiredAuthority in @("manual_only", "ask_before_use", "approved_automatic")) {
  if ($authorityClasses -notcontains $requiredAuthority) {
    Add-Issue $issues "Manifest com_authorityclass is missing an authority class required by Story 5.1: $requiredAuthority."
  }
}
foreach ($requiredRole in @("supporting")) {
  if ($evidenceRoles -notcontains $requiredRole) {
    Add-Issue $issues "Manifest com_councilreceiptsource.com_evidence_role is missing a role required by Story 5.1: $requiredRole."
  }
}

if ($slice.storyKey -ne "5-1-maintain-the-minion-skill-registry") {
  Add-Issue $issues "Slice storyKey must be 5-1-maintain-the-minion-skill-registry."
}
if ([string]$slice.status -notmatch "^local-contract") {
  Add-Issue $issues "Slice status must declare local contract evidence, found: $($slice.status)."
}

foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "requiresExplicitHumanApprovalForExecution", "sourceRecordsRemainSeparate", "meaningGraphDoesNotOwnWorkflowState", "dataverseRowsNotUsedAsCouncilIdentity", "receiptsAreLocalContractEvidenceOnly", "receiptsAreAppendOnlyCorrectionsAreNewReceipts", "statusGovernsSkillUse", "outcomesDerivedFromSkillRecordsNotBooleans", "noWorkItemStateChangeInThisSlice")) {
  if (-not ($slice.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($slice.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Slice guard must be boolean true: $($guardProperty.Name)."
  }
}

# Generic cross-slice id harvest: walk EVERY sibling slice JSON in this folder so
# collision checks cover ALL co-located slices (Story 5.1 hard rule: ids unique
# across ALL slices). The slice's own file is excluded so its ids are checked
# only for intra-slice uniqueness below, not false-flagged as collisions.
$siblingWorkItemIds = @{}
$siblingReceiptIds = @{}
$siblingIdempotencyKeys = @{}
$siblingSourceRecordIds = @{}
$siblingSkillIds = @{}
$siblingScenarioIds = @{}
$siblingRunIds = @{}
$siblingSliceFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.json" |
  Where-Object { $_.Name -ne "dataverse-mvp-schema-manifest.json" -and $_.Name -ne "skill-registry-slice.json" } |
  ForEach-Object { $_.FullName })
if ($siblingSliceFiles.Count -eq 0) {
  Add-Issue $issues "No sibling slice JSON files found in $PSScriptRoot; cross-slice id-collision checks would silently no-op."
}
foreach ($siblingFile in $siblingSliceFiles) {
  $siblingJson = Read-JsonInput -Path $siblingFile
  Invoke-CollectSiblingIds -Node $siblingJson -WorkItems $siblingWorkItemIds -Receipts $siblingReceiptIds -Keys $siblingIdempotencyKeys -SourceRecords $siblingSourceRecordIds -Skills $siblingSkillIds -Scenarios $siblingScenarioIds -RunIds $siblingRunIds
}

$knownPriorSourceIds = @($siblingSourceRecordIds.Keys)

if ($knownPriorSourceIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be harvested from sibling slices; provenance / receipt-source-link checks would silently no-op."
}
if ($siblingReceiptIds.Count -eq 0) {
  Add-Issue $issues "No Receipt IDs could be harvested from sibling slices; receipt collision checks would silently no-op."
}
if ($siblingIdempotencyKeys.Count -eq 0) {
  Add-Issue $issues "No idempotency keys could be harvested from sibling slices; key collision checks would silently no-op."
}

$run = $slice.skillRegistryRun
if ($null -eq $run) {
  Add-Issue $issues "Slice must carry a skillRegistryRun block."
  Write-Host "Skill registry slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Skill registry run must declare a runId."
}
elseif ($siblingRunIds.ContainsKey([string]$run.runId)) {
  Add-Issue $issues "Skill registry run must use a new local runId, not a runId from a sibling slice: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Skill registry run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Skill registry run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Skill registry run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "zero-multi-item-extraction-slice.json")) {
  if (@($run.inputSlicesFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Skill registry run must reference $inputSlice as an input."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Skill registry run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("skillUseIsGovernedByRecordStatus", "deprecatedSkillRecommendedIsFlaggedForHumanReview", "suspendedSkillRecommendedIsPrevented", "activeSkillMayBeRecommended", "outcomesDerivedFromSkillRecordStatusAndAuthorityClass", "recommendationOutcomesAreReceiptBacked", "liveSkillMutationReceiptGatedToEpic2", "receiptsAreAppendOnlyCorrectionsAreNewReceipts")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Skill registry run decisionPolicy must declare: $policyName."
    }
  }
}

# decisionPolicy entries are INTENT labels, never proof. Each is backed by a
# structural derivation accumulated in $decisionPolicyProof and verified at the
# end, so a self-asserted boolean can never stand in for proof on its own: the
# slice only passes when the derived evidence actually supports the claim.
$decisionPolicyProof = @{
  skillUseIsGovernedByRecordStatus = $true
  deprecatedSkillRecommendedIsFlaggedForHumanReview = $true
  suspendedSkillRecommendedIsPrevented = $true
  activeSkillMayBeRecommended = $true
  outcomesDerivedFromSkillRecordStatusAndAuthorityClass = $true
  recommendationOutcomesAreReceiptBacked = $true
  liveSkillMutationReceiptGatedToEpic2 = $true
  receiptsAreAppendOnlyCorrectionsAreNewReceipts = $true
}

# Council Skill records.
$skillTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilskill" } | Select-Object -First 1
$skillRequiredFields = @(@($skillTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($skillRequiredFields.Count -eq 0) {
  Add-Issue $issues "No required Council Skill columns could be derived from manifest com_councilskill; skill required-field checks would silently no-op."
}
# Story 5.1 additionally requires every skill to declare its required inputs
# (story.md "Slice must prove" item 1). The manifest marks com_required_inputs
# optional, so this story pins it as story-required on top of the manifest set,
# the same way receipt fields are pinned below.
$storyRequiredSkillFields = @($skillRequiredFields + @("com_required_inputs") | Sort-Object -Unique)
$skills = @($run.skills | Where-Object { $null -ne $_ })
if ($skills.Count -lt 3) {
  Add-Issue $issues "Skill registry run must include at least three Council Skill records (active, deprecated, suspended), found $($skills.Count)."
}
$sliceSkillIds = @{}
$skillById = @{}
$skillsByStatus = @{}
foreach ($skill in $skills) {
  $skillId = [string]$skill.com_council_skill_id
  $subject = "Skill $skillId"
  foreach ($field in $storyRequiredSkillFields) {
    if (-not (Test-HasNonEmptyField -Record $skill -Field $field)) {
      Add-Issue $issues "$subject missing required Council Skill field: $field."
    }
  }
  if ([string]::IsNullOrWhiteSpace($skillId)) {
    Add-Issue $issues "Skill must declare com_council_skill_id."
  }
  else {
    if ($skillId -notmatch "^CSK-LOCAL-") {
      Add-Issue $issues "$subject must use fresh CSK-LOCAL-* identity, found: $skillId."
    }
    if ($sliceSkillIds.ContainsKey($skillId)) {
      Add-Issue $issues "Duplicate Council Skill id in slice: $skillId."
    }
    else {
      $sliceSkillIds[$skillId] = $skill
    }
    # MINTED id discipline: skill ids must be unique across ALL slices.
    if ($siblingSkillIds.ContainsKey($skillId)) {
      Add-Issue $issues "$subject collides with a Council Skill id from a sibling slice: $skillId."
    }
  }
  $skillById[$skillId] = $skill

  if ($authorityClasses -notcontains [string]$skill.com_authority_class) {
    Add-Issue $issues "$subject com_authority_class is not in manifest com_authorityclass vocabulary, found: $($skill.com_authority_class)."
  }
  if ($recordStatuses -notcontains [string]$skill.com_status) {
    Add-Issue $issues "$subject com_status is not in manifest com_recordstatus vocabulary, found: $($skill.com_status)."
  }
  else {
    $statusKey = [string]$skill.com_status
    if (-not $skillsByStatus.ContainsKey($statusKey)) { $skillsByStatus[$statusKey] = 0 }
    $skillsByStatus[$statusKey] += 1
  }
  if ($skill.evidenceStatus -ne "mock_manual_not_tenant_verified") {
    Add-Issue $issues "$subject must be marked mock_manual_not_tenant_verified evidence, found: $($skill.evidenceStatus)."
  }
  # Local-contract-evidence markers (evidenceStatus / provenanceSourceRecord /
  # provenanceNote) are NOT com_councilskill manifest columns; they are the
  # slice-level local-contract-evidence annotation pattern the gold-standard
  # sibling slice (source-drift-supersession) establishes via evidenceStatus on
  # its records. They are mandatory here and NOT skippable: every skill must
  # declare provenanceSourceRecord, which is either null with a non-empty
  # provenanceNote, or a resolvable sibling Source Record (REFERENCED id).
  if (@($skill.PSObject.Properties.Name) -notcontains "provenanceSourceRecord") {
    Add-Issue $issues "$subject must declare provenanceSourceRecord (null with a provenanceNote, or a resolvable sibling Source Record)."
  }
  else {
    $provenanceRef = [string]$skill.provenanceSourceRecord
    if ($null -eq $skill.provenanceSourceRecord -or [string]::IsNullOrWhiteSpace($provenanceRef)) {
      if (-not (Test-HasNonEmptyField -Record $skill -Field "provenanceNote")) {
        Add-Issue $issues "$subject provenanceSourceRecord is null so it must carry a non-empty provenanceNote explaining the absence of a single source record."
      }
    }
    else {
      if ($knownPriorSourceIds -notcontains $provenanceRef) {
        Add-Issue $issues "$subject provenanceSourceRecord must reference a known Source Record from a sibling slice, found: $provenanceRef."
      }
    }
  }
  if (-not (Test-HasNonEmptyField -Record $skill -Field "provenanceNote")) {
    Add-Issue $issues "$subject must carry a non-empty provenanceNote (provenance evidence link rationale)."
  }
  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($skill.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 5.1 skills are local contract evidence only."
    }
  }
}

# Coverage derived, not counted: exactly one active, one deprecated, one suspended status must be present.
foreach ($requiredStatus in @("active", "deprecated", "suspended")) {
  $count = if ($skillsByStatus.ContainsKey($requiredStatus)) { $skillsByStatus[$requiredStatus] } else { 0 }
  if ($count -ne 1) {
    Add-Issue $issues "Skill registry run must include exactly one skill with com_status=$requiredStatus, found $count."
  }
}

# Recommendation scenarios: outcomes DERIVED from the skill record's status and authority class.
$recommendationScenarios = @($run.recommendationScenarios | Where-Object { $null -ne $_ })
if ($recommendationScenarios.Count -lt 2) {
  Add-Issue $issues "Skill registry run must include at least two recommendation scenarios (one flag, one prevent), found $($recommendationScenarios.Count)."
}
$sliceScenarioIds = @{}
$scenarioById = @{}
foreach ($scenario in $recommendationScenarios) {
  $scenarioId = [string]$scenario.scenarioId
  $subject = "Recommendation scenario $scenarioId"
  if ([string]::IsNullOrWhiteSpace($scenarioId)) {
    Add-Issue $issues "Recommendation scenario must declare a scenarioId."
  }
  else {
    if ($scenarioId -notmatch "^REC-LOCAL-") {
      Add-Issue $issues "$subject must use fresh REC-LOCAL-* identity, found: $scenarioId."
    }
    if ($sliceScenarioIds.ContainsKey($scenarioId)) {
      Add-Issue $issues "Duplicate recommendation scenario id in slice: $scenarioId."
    }
    else {
      $sliceScenarioIds[$scenarioId] = $scenario
    }
    if ($siblingScenarioIds.ContainsKey($scenarioId)) {
      Add-Issue $issues "$subject collides with a scenario id from a sibling slice: $scenarioId."
    }
  }
  $scenarioById[$scenarioId] = $scenario

  if (-not (Test-HasNonEmptyField -Record $scenario -Field "recommendedSkill")) {
    Add-Issue $issues "$subject must name a recommendedSkill."
  }
  else {
    $recommendedSkillId = [string]$scenario.recommendedSkill
    if (-not $sliceSkillIds.ContainsKey($recommendedSkillId)) {
      Add-Issue $issues "$subject recommendedSkill must reference a Council Skill that exists in this slice, found: $recommendedSkillId."
    }
    else {
      $recommendedSkill = $sliceSkillIds[$recommendedSkillId]
      $skillStatus = [string]$recommendedSkill.com_status
      $skillAuthority = [string]$recommendedSkill.com_authority_class
      # DERIVED outcome: compute the expected outcome from the skill record's
      # status (status governs use), not from any self-asserted boolean.
      # deprecated -> flagged, suspended -> prevented, active -> allowed.
      $derivedOutcome = switch ($skillStatus) {
        "deprecated" { "flagged" }
        "suspended" { "prevented" }
        "active" { "allowed" }
        default { "unknown" }
      }
      $outcomeMatches = $false
      if (-not (Test-HasNonEmptyField -Record $scenario -Field "expectedOutcome")) {
        Add-Issue $issues "$subject must declare an expectedOutcome."
      }
      elseif ([string]$scenario.expectedOutcome -ne $derivedOutcome) {
        Add-Issue $issues "$subject expectedOutcome must be derived from the recommended skill's com_status ($skillStatus => $derivedOutcome), found: $($scenario.expectedOutcome). The outcome must not be a self-asserted boolean."
      }
      else {
        $outcomeMatches = $true
      }
      $decisionPolicyProof.skillUseIsGovernedByRecordStatus = $decisionPolicyProof.skillUseIsGovernedByRecordStatus -and $outcomeMatches
      # STRUCTURAL authority-class consistency (not prose-only): the outcome's
      # restrictiveness must be at least the authority class's gating stance.
      # manual_only and ask_before_use both require a human gate, so an outcome
      # of "allowed" (auto-permit) would contradict them; only approved_automatic
      # may be auto-allowed. flagged/prevented are always at least as restrictive
      # as any authority class demands, so they are consistent with any class.
      $authorityConsistent = $true
      if ($derivedOutcome -eq "allowed" -and $skillAuthority -ne "approved_automatic") {
        Add-Issue $issues "$subject expectedOutcome 'allowed' is inconsistent with com_authority_class $skillAuthority, which requires a human gate; only approved_automatic may be auto-allowed."
        $authorityConsistent = $false
      }
      if (-not (Test-HasNonEmptyField -Record $scenario -Field "outcomeRationale")) {
        Add-Issue $issues "$subject must carry a non-empty outcomeRationale."
      }
      else {
        # The outcome rationale must reference the skill's status AND authority
        # class (supplementary textual evidence to the structural rule above).
        $rationaleText = [string]$scenario.outcomeRationale
        if ($skillStatus -eq "deprecated" -and $rationaleText -notmatch "deprecated") {
          Add-Issue $issues "$subject outcomeRationale must reference the deprecated status of $recommendedSkillId."
        }
        if ($skillStatus -eq "suspended" -and $rationaleText -notmatch "suspended") {
          Add-Issue $issues "$subject outcomeRationale must reference the suspended status of $recommendedSkillId."
        }
        if ($rationaleText -notmatch [regex]::Escape($skillAuthority)) {
          Add-Issue $issues "$subject outcomeRationale must reference the skill's authority class ($skillAuthority), found rationale omitting it."
        }
      }
      $decisionPolicyProof.outcomesDerivedFromSkillRecordStatusAndAuthorityClass = $decisionPolicyProof.outcomesDerivedFromSkillRecordStatusAndAuthorityClass -and $outcomeMatches -and $authorityConsistent
    }
  }
  if ($actorTypes -notcontains [string]$scenario.recommendingActorType) {
    Add-Issue $issues "$subject recommendingActorType must use manifest com_actortype vocabulary, found: $($scenario.recommendingActorType)."
  }
  if (-not (Test-HasNonEmptyField -Record $scenario -Field "recommendingActorId")) {
    Add-Issue $issues "$subject must carry a non-empty recommendingActorId."
  }
  if (-not (Test-HasNonEmptyField -Record $scenario -Field "recommendationRationale")) {
    Add-Issue $issues "$subject must carry a non-empty recommendationRationale."
  }
}

# Coverage derived: exactly one flag scenario (deprecated) and one prevent scenario (suspended).
$flagScenarios = @($recommendationScenarios | Where-Object {
  $s = [string]$_.recommendedSkill
  $sliceSkillIds.ContainsKey($s) -and [string]$sliceSkillIds[$s].com_status -eq "deprecated"
})
$preventScenarios = @($recommendationScenarios | Where-Object {
  $s = [string]$_.recommendedSkill
  $sliceSkillIds.ContainsKey($s) -and [string]$sliceSkillIds[$s].com_status -eq "suspended"
})
if ($flagScenarios.Count -ne 1) {
  Add-Issue $issues "Skill registry run must include exactly one recommendation scenario for the deprecated skill (FLAG), found $($flagScenarios.Count)."
  $decisionPolicyProof.deprecatedSkillRecommendedIsFlaggedForHumanReview = $false
}
else {
  $flagScenarioOk = ([string]$flagScenarios[0].expectedOutcome -eq "flagged")
  $decisionPolicyProof.deprecatedSkillRecommendedIsFlaggedForHumanReview = $decisionPolicyProof.deprecatedSkillRecommendedIsFlaggedForHumanReview -and $flagScenarioOk
}
if ($preventScenarios.Count -ne 1) {
  Add-Issue $issues "Skill registry run must include exactly one recommendation scenario for the suspended skill (PREVENT), found $($preventScenarios.Count)."
  $decisionPolicyProof.suspendedSkillRecommendedIsPrevented = $false
}
else {
  $preventScenarioOk = ([string]$preventScenarios[0].expectedOutcome -eq "prevented")
  $decisionPolicyProof.suspendedSkillRecommendedIsPrevented = $decisionPolicyProof.suspendedSkillRecommendedIsPrevented -and $preventScenarioOk
}
# activeSkillMayBeRecommended: an active skill is present and the status
# derivation maps active -> allowed (recommendable, not flagged/prevented).
$activeSkillCount = if ($skillsByStatus.ContainsKey("active")) { $skillsByStatus["active"] } else { 0 }
$decisionPolicyProof.activeSkillMayBeRecommended = $decisionPolicyProof.activeSkillMayBeRecommended -and ($activeSkillCount -eq 1)

# Receipts.
$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
# Manifest-required columns, plus the Council receipt contract fields this story additionally pins.
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique

$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 2) {
  Add-Issue $issues "Skill registry run must include at least two outcome receipts (one flag, one prevent), found $($receipts.Count)."
}
$sliceReceiptIds = @{}
$receiptById = @{}
$seenIdempotencyKeys = @{}
$appendOnlyProof = $true
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
    if ($receiptId -notmatch "^CR-LOCAL-SKILL-") {
      Add-Issue $issues "$subject must use Council-level CR-LOCAL-SKILL-* identity."
    }
    if ($sliceReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "Duplicate receipt ID in slice: $receiptId."
    }
    else {
      $sliceReceiptIds[$receiptId] = $receipt
    }
    # MINTED id discipline: receipt ids must be unique across ALL slices. The
    # sibling harvest above already walks every co-located *.json (including the
    # state-transition-demo evidence file), so demo receipt ids are covered by
    # $siblingReceiptIds; no separate hard dependency on a non-story artifact.
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
      $appendOnlyProof = $false
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
    $appendOnlyProof = $false
  }
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 5.1 receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 5.1 receipts are local contract evidence only."
      }
    }
  }

  # Evidence refs must resolve: every CSK-LOCAL-* and REC-LOCAL-* cited in com_evidence_refs
  # must reference a real slice skill or scenario (REFERENCED id discipline).
  if (Test-HasNonEmptyField -Record $receipt -Field "com_evidence_refs") {
    $refs = [string]$receipt.com_evidence_refs
    foreach ($refToken in @($refs -split ";" | ForEach-Object { [string]$_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
      if ($refToken -match "^CSK-LOCAL-") {
        if (-not $sliceSkillIds.ContainsKey($refToken)) {
          Add-Issue $issues "$subject com_evidence_refs cites an unknown Council Skill: $refToken."
        }
      }
      elseif ($refToken -match "^REC-LOCAL-") {
        if (-not $sliceScenarioIds.ContainsKey($refToken)) {
          Add-Issue $issues "$subject com_evidence_refs cites an unknown recommendation scenario: $refToken."
        }
      }
    }
  }
}

# Outcome receipts are DISCOVERED BY SHAPE, never bound by hardcoded id (Story
# 5.1 hardening bar: general rules over collections). A flag receipt is any
# receipt with verb held / result accepted / before recommended / after
# flagged_for_review; a prevent receipt is verb policy_denied / result rejected
# / before recommended / after prevented. Exactly one of each must exist
# (coverage derived, not named).
$flagReceipts = @($receipts | Where-Object {
  [string]$_.com_verb -eq "held" -and [string]$_.com_result -eq "accepted" -and
  [string]$_.com_before_state -eq "recommended" -and [string]$_.com_after_state -eq "flagged_for_review"
})
$preventReceipts = @($receipts | Where-Object {
  [string]$_.com_verb -eq "policy_denied" -and [string]$_.com_result -eq "rejected" -and
  [string]$_.com_before_state -eq "recommended" -and [string]$_.com_after_state -eq "prevented"
})
if ($flagReceipts.Count -ne 1) {
  Add-Issue $issues "Slice must include exactly one FLAG receipt by shape (verb held, result accepted, before recommended, after flagged_for_review), found $($flagReceipts.Count)."
}
else {
  $flagReceipt = $flagReceipts[0]
  $subject = "Receipt $([string]$flagReceipt.com_receipt_id) (flag)"
  if ([string]$flagReceipt.com_policy_flags -notmatch "deprecated_skill_flagged") {
    Add-Issue $issues "$subject com_policy_flags must declare deprecated_skill_flagged."
  }
}
if ($preventReceipts.Count -ne 1) {
  Add-Issue $issues "Slice must include exactly one PREVENT receipt by shape (verb policy_denied, result rejected, before recommended, after prevented), found $($preventReceipts.Count)."
}
else {
  $preventReceipt = $preventReceipts[0]
  $subject = "Receipt $([string]$preventReceipt.com_receipt_id) (prevent)"
  if ([string]$preventReceipt.com_policy_flags -notmatch "suspended_skill_prevented") {
    Add-Issue $issues "$subject com_policy_flags must declare suspended_skill_prevented."
  }
}

# Bind each scenario's outcomeReceipt to a real slice receipt whose shape matches the scenario.
$receiptBackingProof = $true
foreach ($scenario in $recommendationScenarios) {
  $scenarioId = [string]$scenario.scenarioId
  $subject = "Recommendation scenario $scenarioId"
  if (Test-HasNonEmptyField -Record $scenario -Field "outcomeReceipt") {
    $outcomeReceiptId = [string]$scenario.outcomeReceipt
    if (-not $sliceReceiptIds.ContainsKey($outcomeReceiptId)) {
      Add-Issue $issues "$subject outcomeReceipt must reference a receipt that exists in this slice, found: $outcomeReceiptId."
      $receiptBackingProof = $false
    }
    else {
      $bound = $sliceReceiptIds[$outcomeReceiptId]
      $expectedOutcome = [string]$scenario.expectedOutcome
      $shapeOk = $true
      if ($expectedOutcome -eq "flagged") {
        if ([string]$bound.com_verb -ne "held" -or [string]$bound.com_result -ne "accepted" -or [string]$bound.com_before_state -ne "recommended" -or [string]$bound.com_after_state -ne "flagged_for_review") {
          Add-Issue $issues "$subject outcomeReceipt ($outcomeReceiptId) must be a flag receipt by shape (verb held, result accepted, before recommended, after flagged_for_review), found verb $($bound.com_verb) result $($bound.com_result) after $($bound.com_after_state)."
          $shapeOk = $false
        }
      }
      elseif ($expectedOutcome -eq "prevented") {
        if ([string]$bound.com_verb -ne "policy_denied" -or [string]$bound.com_result -ne "rejected" -or [string]$bound.com_before_state -ne "recommended" -or [string]$bound.com_after_state -ne "prevented") {
          Add-Issue $issues "$subject outcomeReceipt ($outcomeReceiptId) must be a prevent receipt by shape (verb policy_denied, result rejected, before recommended, after prevented), found verb $($bound.com_verb) result $($bound.com_result) after $($bound.com_after_state)."
          $shapeOk = $false
        }
      }
      # The receipt's com_evidence_refs must cite this scenario's recommended skill.
      $recommendedSkillId = [string]$scenario.recommendedSkill
      if ((Test-HasNonEmptyField -Record $bound -Field "com_evidence_refs") -and -not [string]::IsNullOrWhiteSpace($recommendedSkillId)) {
        if ([string]$bound.com_evidence_refs -notmatch [regex]::Escape($recommendedSkillId)) {
          Add-Issue $issues "$subject outcomeReceipt ($outcomeReceiptId) com_evidence_refs must cite the recommended skill $recommendedSkillId."
          $shapeOk = $false
        }
      }
      $receiptBackingProof = $receiptBackingProof -and $shapeOk
    }
  }
  else {
    Add-Issue $issues "$subject must declare an outcomeReceipt."
    $receiptBackingProof = $false
  }
}
$decisionPolicyProof.recommendationOutcomesAreReceiptBacked = $decisionPolicyProof.recommendationOutcomesAreReceiptBacked -and $receiptBackingProof
$decisionPolicyProof.receiptsAreAppendOnlyCorrectionsAreNewReceipts = $decisionPolicyProof.receiptsAreAppendOnlyCorrectionsAreNewReceipts -and $appendOnlyProof

# Receipt source links: provenance evidence binding for outcome receipts.
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
  elseif ($link.com_evidence_role -ne "supporting") {
    Add-Issue $issues "$linkSubject must use the supporting role for skill provenance evidence, found: $($link.com_evidence_role)."
  }
}
foreach ($receiptId in @($sliceReceiptIds.Keys)) {
  if (@($links | Where-Object { $_.com_receipt -eq $receiptId }).Count -lt 1) {
    Add-Issue $issues "Receipt $receiptId must be bound to its provenance evidence by at least one receipt source link."
  }
}

# Deferred skill updates: every skill's live mutation must be a deferred entry naming a receipt gate.
$deferredUpdates = @($run.skillUpdatesDeferred | Where-Object { $null -ne $_ })
$deferredProof = $true
foreach ($deferred in $deferredUpdates) {
  $deferredOk = $true
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "skill")) {
    Add-Issue $issues "Deferred skill update must name its skill."
    $deferredOk = $false
  }
  elseif (-not $sliceSkillIds.ContainsKey([string]$deferred.skill)) {
    Add-Issue $issues "Deferred skill update references an unknown Council Skill: $($deferred.skill)."
    $deferredOk = $false
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred skill update must carry a non-empty deferredUpdate."
    $deferredOk = $false
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt" -or [string]$deferred.deferredUpdate -notmatch "gated|deferred|epic 2|epic2") {
    Add-Issue $issues "Deferred skill update for $($deferred.skill) must state that the live mutation is receipt-gated (mention 'receipt' and a gate/defer/epic-2 term), found: $($deferred.deferredUpdate)."
    $deferredOk = $false
  }
  $deferredProof = $deferredProof -and $deferredOk
}
foreach ($skillId in @($sliceSkillIds.Keys)) {
  $deferred = $deferredUpdates | Where-Object { [string]$_.skill -eq $skillId } | Select-Object -First 1
  if (-not $deferred) {
    Add-Issue $issues "Missing deferred skill update entry for $skillId; live skill mutation must be receipt-gated."
    $deferredProof = $false
  }
}
$decisionPolicyProof.liveSkillMutationReceiptGatedToEpic2 = $decisionPolicyProof.liveSkillMutationReceiptGatedToEpic2 -and $deferredProof

# Acceptance mapping for AC 1, 2. localEvidence must not be self-asserting prose:
# every CSK-LOCAL-*, CR-LOCAL-SKILL-*, REC-LOCAL-*, and CSR-* id it cites must
# resolve to a real slice entity or known sibling Source Record, and each AC
# must cite at least one real slice id.
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
  $citedIds = [regex]::Matches($joinedEvidence, "(?:CR-LOCAL-SKILL-[A-Z0-9-]+|CSK-LOCAL-[A-Z0-9-]+|REC-LOCAL-[A-Z0-9-]+|CSR-[A-Z0-9-]+)") | ForEach-Object { [string]$_.Value } | Sort-Object -Unique
  $citedAny = $false
  foreach ($citedId in $citedIds) {
    $resolved = $false
    if ($citedId -like "CR-LOCAL-SKILL-*") {
      if ($sliceReceiptIds.ContainsKey($citedId)) { $resolved = $true }
    }
    elseif ($citedId -like "CSK-LOCAL-*") {
      if ($sliceSkillIds.ContainsKey($citedId)) { $resolved = $true }
    }
    elseif ($citedId -like "REC-LOCAL-*") {
      if ($sliceScenarioIds.ContainsKey($citedId)) { $resolved = $true }
    }
    elseif ($citedId -like "CSR-*") {
      if ($knownPriorSourceIds -contains $citedId) { $resolved = $true }
    }
    if (-not $resolved) {
      Add-Issue $issues "Acceptance mapping for AC $criterion cites id '$citedId' which does not resolve to any skill, receipt, scenario, or known Source Record in this slice."
    }
    else {
      $citedAny = $true
    }
  }
  if (-not $citedAny) {
    Add-Issue $issues "Acceptance mapping for AC $criterion must cite at least one real slice id (CR-LOCAL-SKILL-*/CSK-LOCAL-*/REC-LOCAL-*) in localEvidence; self-asserting prose is not proof."
  }
}

# decisionPolicy backing: each declared policy must be a strict-true intent
# label AND supported by the structural evidence accumulated above. The boolean
# alone is never proof (a true boolean without backing fails); a false boolean
# is a contradictory intent and also fails. This closes the "self-asserted
# boolean standing in for proof" gap: the slice only passes when the asserted
# intent matches the derived evidence.
if ($null -ne $decisionPolicy) {
  foreach ($policyName in @("skillUseIsGovernedByRecordStatus", "deprecatedSkillRecommendedIsFlaggedForHumanReview", "suspendedSkillRecommendedIsPrevented", "activeSkillMayBeRecommended", "outcomesDerivedFromSkillRecordStatusAndAuthorityClass", "recommendationOutcomesAreReceiptBacked", "liveSkillMutationReceiptGatedToEpic2", "receiptsAreAppendOnlyCorrectionsAreNewReceipts")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -contains $policyName) {
      $entry = $decisionPolicy.$policyName
      if ($entry -isnot [bool] -or -not $entry) {
        Add-Issue $issues "decisionPolicy $policyName must be declared as boolean true (intent); found: $entry. A false boolean contradicts the policy the slice is meant to prove."
      }
      if (-not $decisionPolicyProof[$policyName]) {
        Add-Issue $issues "decisionPolicy $policyName is asserted but not backed by structural evidence in this slice; a self-asserted boolean is not proof."
      }
    }
  }
}

if ($issues.Count -gt 0) {
  Write-Host "Skill registry slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Skill registry slice validation succeeded."
Write-Host "Skills: $($skills.Count)"
Write-Host "Recommendation scenarios: $($recommendationScenarios.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "SKILL_REGISTRY_SLICE_VALIDATE_OK"
