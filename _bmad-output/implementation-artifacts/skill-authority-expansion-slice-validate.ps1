param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$SkillSlicePath = "$PSScriptRoot\skill-authority-expansion-slice.json",
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

  if ($null -eq $Record) { return $false }
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

function Get-NormalizedStringSet {
  # Normalize an array (or scalar) of strings into a sorted, de-duplicated, lower-cased
  # string list so authority-set members can be compared order-insensitively. Empty/whitespace
  # members are dropped. Returns a NEW array (never $null) so callers can always iterate.
  param($Values)

  $list = [System.Collections.Generic.List[string]]::new()
  if ($null -ne $Values) {
    foreach ($v in @($Values)) {
      $s = [string]$v
      if (-not [string]::IsNullOrWhiteSpace($s)) {
        $list.Add($s.Trim().ToLowerInvariant()) | Out-Null
      }
    }
  }
  @($list | Sort-Object -Unique)
}

function Compare-StringSet {
  # Set-equality on two normalized string sets. Returns $true iff they contain the same members.
  param($SetA, $SetB)

  $a = Get-NormalizedStringSet -Values $SetA
  $b = Get-NormalizedStringSet -Values $SetB
  if ($a.Count -ne $b.Count) { return $false }
  for ($i = 0; $i -lt $a.Count; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
  return $true
}

function Get-SetDifference {
  # Members in SetA that are not in SetB (normalized).
  param($SetA, $SetB)

  $a = Get-NormalizedStringSet -Values $SetA
  $b = Get-NormalizedStringSet -Values $SetB
  @($a | Where-Object { $b -notcontains $_ })
}

function Compare-AuthoritySet {
  # Deep equality of two authority-set objects (authorityClass + dataScopes/tools/externalActions),
  # order-insensitive on the array members.
  param($SetA, $SetB)

  if ($null -eq $SetA -and $null -eq $SetB) { return $true }
  if ($null -eq $SetA -or $null -eq $SetB) { return $false }
  if ([string]$SetA.authorityClass -ne [string]$SetB.authorityClass) { return $false }
  if (-not (Compare-StringSet -SetA $SetA.dataScopes -SetB $SetB.dataScopes)) { return $false }
  if (-not (Compare-StringSet -SetA $SetA.tools -SetB $SetB.tools)) { return $false }
  if (-not (Compare-StringSet -SetA $SetA.externalActions -SetB $SetB.externalActions)) { return $false }
  return $true
}

function Test-AuthoritySetShape {
  # Asserts an authority-set object is well-formed: authorityClass present and in vocab,
  # and dataScopes/tools/externalActions are arrays of non-empty, unique strings.
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)][AllowNull()]$Set,
    [Parameter(Mandatory = $true)][string]$Subject,
    [Parameter(Mandatory = $true)]$AuthorityClassVocab
  )

  if ($null -eq $Set) {
    Add-Issue $Issues "$Subject authority set is missing."
    return
  }
  if (-not (Test-HasNonEmptyField -Record $Set -Field "authorityClass")) {
    Add-Issue $Issues "$Subject authority set must carry a non-empty authorityClass."
  }
  elseif ($AuthorityClassVocab -notcontains [string]$Set.authorityClass) {
    Add-Issue $Issues "$Subject authority set authorityClass is not in manifest com_authorityclass vocabulary, found: $($Set.authorityClass)."
  }
  foreach ($memberField in @("dataScopes", "tools", "externalActions")) {
    if ($Set.PSObject.Properties.Name -notcontains $memberField) {
      Add-Issue $Issues "$Subject authority set must declare $memberField (array; empty allowed)."
      continue
    }
    $members = @($Set.$memberField | Where-Object { $null -ne $_ })
    $normalized = Get-NormalizedStringSet -Values $members
    # Each member must be a non-empty, whitespace-free identifier (no spaces inside).
    foreach ($m in $members) {
      $s = [string]$m
      if ([string]::IsNullOrWhiteSpace($s)) {
        Add-Issue $Issues "$Subject authority set $memberField has an empty/whitespace member."
      }
      elseif ($s -match "\s") {
        Add-Issue $Issues "$Subject authority set $memberField member must not contain whitespace, found: $s."
      }
    }
    # Uniqueness (order-insensitive): normalized count must equal raw count.
    if ($normalized.Count -ne $members.Count) {
      Add-Issue $Issues "$Subject authority set $memberField must have unique members (case-insensitive); duplicates found."
    }
  }
}

function Test-DeltaExact {
  # Asserts before/after authority sets differ EXACTLY by declaredDelta: after is the union of
  # before and the declared additions (no extras, no removals), and the authority class change
  # matches the declared from/to. Returns nothing; appends issues.
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)][AllowNull()]$Before,
    [Parameter(Mandatory = $true)][AllowNull()]$After,
    [Parameter(Mandatory = $true)][AllowNull()]$Delta,
    [Parameter(Mandatory = $true)][string]$Subject
  )

  if ($null -eq $Before -or $null -eq $After -or $null -eq $Delta) {
    Add-Issue $Issues "$Subject before/after/declaredDelta authority sets must all be present."
    return
  }
  # Authority class: from == before.authorityClass, to == after.authorityClass, and a real change.
  if ([string]$Delta.authorityClassChangedFrom -ne [string]$Before.authorityClass) {
    Add-Issue $Issues "$Subject declaredDelta.authorityClassChangedFrom must equal beforeAuthoritySet.authorityClass ($($Before.authorityClass)), found: $($Delta.authorityClassChangedFrom)."
  }
  if ([string]$Delta.authorityClassChangedTo -ne [string]$After.authorityClass) {
    Add-Issue $Issues "$Subject declaredDelta.authorityClassChangedTo must equal proposedAfterAuthoritySet.authorityClass ($($After.authorityClass)), found: $($Delta.authorityClassChangedTo)."
  }
  if ([string]$Delta.authorityClassChangedFrom -eq [string]$Delta.authorityClassChangedTo) {
    Add-Issue $Issues "$Subject declaredDelta must record a real authority class change; from and to are identical ($($Delta.authorityClassChangedFrom))."
  }
  foreach ($memberField in @("dataScopes", "tools", "externalActions")) {
    $addedField = switch ($memberField) { "dataScopes" { "addedDataScopes" } "tools" { "addedTools" } "externalActions" { "addedExternalActions" } }
    $beforeMembers = Get-NormalizedStringSet -Values $Before.$memberField
    $afterMembers = Get-NormalizedStringSet -Values $After.$memberField
    $addedMembers = Get-NormalizedStringSet -Values $Delta.$addedField

    # 1. Declared additions must actually be additions (not already in before).
    $alreadyPresent = @($addedMembers | Where-Object { $beforeMembers -contains $_ })
    if ($alreadyPresent.Count -gt 0) {
      Add-Issue $Issues "$Subject declaredDelta.${addedField} must not list members already in beforeAuthoritySet.${memberField}: $($alreadyPresent -join ', ')."
    }
    # 2. Declared additions must be a subset of after (no declared addition that didn't land).
    $declaredNotInAfter = @($addedMembers | Where-Object { $afterMembers -notcontains $_ })
    if ($declaredNotInAfter.Count -gt 0) {
      Add-Issue $Issues "$Subject declaredDelta.${addedField} members must all appear in proposedAfterAuthoritySet.${memberField}: missing $($declaredNotInAfter -join ', ')."
    }
    # 3. Removed members (before minus after) must be empty: an expansion only adds.
    $removed = Get-SetDifference -SetA $beforeMembers -SetB $afterMembers
    if ($removed.Count -gt 0) {
      Add-Issue $Issues "$Subject proposedAfterAuthoritySet.$memberField must not remove any beforeAuthoritySet member (expansion only adds); removed: $($removed -join ', ')."
    }
    # 4. Extra members (after minus before minus declared additions) must be empty: no undeclared additions.
    $expectedAfter = Get-NormalizedStringSet -Values (@($beforeMembers + $addedMembers))
    $extras = Get-SetDifference -SetA $afterMembers -SetB $expectedAfter
    if ($extras.Count -gt 0) {
      Add-Issue $Issues "$Subject proposedAfterAuthoritySet.$memberField must not add members beyond beforeAuthoritySet + declaredDelta.$addedField; undeclared additions: $($extras -join ', ')."
    }
  }
  # 5. The delta must be non-empty (at least one added scope/tool/action OR an authority class change).
  $deltaEmpty = $true
  foreach ($addedField in @("addedDataScopes", "addedTools", "addedExternalActions")) {
    if ((Get-NormalizedStringSet -Values $Delta.$addedField).Count -gt 0) { $deltaEmpty = $false }
  }
  if ([string]$Delta.authorityClassChangedFrom -ne [string]$Delta.authorityClassChangedTo) { $deltaEmpty = $false }
  if ($deltaEmpty) {
    Add-Issue $Issues "$Subject declaredDelta must be non-empty; an authority expansion must add at least one data scope, tool, external action, or broaden the authority class."
  }
}

function Invoke-CollectSiblingIds {
  # Recursively walk a parsed sibling slice JSON and harvest every canonical
  # Council id / idempotency key by property name, plus the demo-evidence
  # workItemIds/receiptIds arrays. This is the single source of truth for
  # cross-slice collision checks so they cover ALL co-located slices, not just
  # the named siblings (Story 5.2 hard rule: ids unique across ALL slices).
  param(
    [Parameter(Mandatory = $false)][AllowNull()]$Node,
    [Parameter(Mandatory = $true)][hashtable]$WorkItems,
    [Parameter(Mandatory = $true)][hashtable]$Receipts,
    [Parameter(Mandatory = $true)][hashtable]$Keys,
    [Parameter(Mandatory = $true)][hashtable]$SourceRecords,
    [Parameter(Mandatory = $true)][hashtable]$Instructions,
    [Parameter(Mandatory = $true)][hashtable]$MemoryCandidates,
    [Parameter(Mandatory = $true)][hashtable]$Skills
  )

  if ($null -eq $Node) { return }
  if ($Node -is [System.Collections.IList]) {
    foreach ($item in $Node) {
      Invoke-CollectSiblingIds -Node $item -WorkItems $WorkItems -Receipts $Receipts -Keys $Keys -SourceRecords $SourceRecords -Instructions $Instructions -MemoryCandidates $MemoryCandidates -Skills $Skills
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
        "com_council_skill_id" {
          $id = [string]$prop.Value
          if (-not [string]::IsNullOrWhiteSpace($id)) { $Skills[$id] = $true }
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
          Invoke-CollectSiblingIds -Node $prop.Value -WorkItems $WorkItems -Receipts $Receipts -Keys $Keys -SourceRecords $SourceRecords -Instructions $Instructions -MemoryCandidates $MemoryCandidates -Skills $Skills
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
    Write-Host "Skill authority expansion slice validation failed:"
    Write-Host "- Input file is not valid JSON: $Path"
    exit 1
  }
}

foreach ($path in @($ManifestPath, $SkillSlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required skill authority expansion validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$slice = Read-JsonInput -Path $SkillSlicePath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath
$rawSliceText = Get-Content -LiteralPath $SkillSlicePath -Raw
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

foreach ($requiredVerb in @("approved", "policy_denied")) {
  if ($receiptVerbs -notcontains $requiredVerb) {
    Add-Issue $issues "Manifest com_receiptverb is missing a verb required by Story 5.2: $requiredVerb."
  }
}
foreach ($requiredResult in @("accepted", "rejected")) {
  if ($receiptResults -notcontains $requiredResult) {
    Add-Issue $issues "Manifest com_receiptresult is missing a result required by Story 5.2: $requiredResult."
  }
}
foreach ($requiredActor in @("human")) {
  if ($actorTypes -notcontains $requiredActor) {
    Add-Issue $issues "Manifest com_actortype is missing an actor type required by Story 5.2: $requiredActor."
  }
}
foreach ($requiredStatus in @("candidate", "active")) {
  if ($recordStatuses -notcontains $requiredStatus) {
    Add-Issue $issues "Manifest com_recordstatus is missing a status required by Story 5.2: $requiredStatus."
  }
}
foreach ($requiredClass in @("manual_only", "ask_before_use", "approved_automatic")) {
  if ($authorityClasses -notcontains $requiredClass) {
    Add-Issue $issues "Manifest com_authorityclass is missing a value required by Story 5.2: $requiredClass."
  }
}
foreach ($requiredRole in @("approval", "failure_evidence")) {
  if ($evidenceRoles -notcontains $requiredRole) {
    Add-Issue $issues "Manifest com_councilreceiptsource.com_evidence_role is missing a role required by Story 5.2: $requiredRole."
  }
}

if ($slice.storyKey -ne "5-2-approve-skill-authority-expansion") {
  Add-Issue $issues "Slice storyKey must be 5-2-approve-skill-authority-expansion."
}
if ([string]$slice.status -notmatch "^local-contract") {
  Add-Issue $issues "Slice status must declare local contract evidence, found: $($slice.status)."
}

foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "requiresExplicitHumanApprovalForExecution", "sourceRecordsRemainSeparate", "meaningGraphDoesNotOwnWorkflowState", "dataverseRowsNotUsedAsCouncilIdentity", "receiptsAreLocalContractEvidenceOnly", "receiptsAreAppendOnlyCorrectionsAreNewReceipts", "authorityExpansionRequiresExplicitApprovalReceipt", "activationStrictlyFollowsApprovalReceipt", "denialConstrainsSkillToBeforeAuthority", "denialRationaleRemainsVisibleForFutureReview", "noWorkItemStateChangeInThisSlice")) {
  if (-not ($slice.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($slice.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Slice guard must be boolean true: $($guardProperty.Name)."
  }
}

# Local extension vocabularies (authority set + failure code) must be declared with a basis.
$authorityVocab = $slice.authoritySetVocabulary
if ($null -eq $authorityVocab) {
  Add-Issue $issues "Slice must declare an authoritySetVocabulary block (Story 5.2 local extension)."
}
else {
  if (-not (Test-HasNonEmptyField -Record $authorityVocab -Field "basis")) {
    Add-Issue $issues "authoritySetVocabulary must carry a non-empty basis."
  }
  $expansionTriggers = @($authorityVocab.expansionTriggersApproval | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($expansionTriggers.Count -eq 0) {
    Add-Issue $issues "authoritySetVocabulary.expansionTriggersApproval must list at least one trigger kind."
  }
}

$failureVocab = $slice.failureCodeVocabulary
$declaredFailureCodes = @{}
if ($null -eq $failureVocab) {
  Add-Issue $issues "Slice must declare a failureCodeVocabulary block (Story 5.2 local extension)."
}
else {
  if (-not (Test-HasNonEmptyField -Record $failureVocab -Field "basis")) {
    Add-Issue $issues "failureCodeVocabulary must carry a non-empty basis."
  }
  $codes = @($failureVocab.codes | Where-Object { $null -ne $_ })
  if ($codes.Count -eq 0) {
    Add-Issue $issues "failureCodeVocabulary must declare at least one code."
  }
  foreach ($code in $codes) {
    $codeName = [string]$code.code
    if ([string]::IsNullOrWhiteSpace($codeName)) {
      Add-Issue $issues "failureCodeVocabulary code must declare a non-empty code name."
      continue
    }
    $declaredFailureCodes[$codeName] = $code
    if ([string]$code.kind -ne "policy_denial") {
      Add-Issue $issues "failureCodeVocabulary code $codeName kind must be policy_denial for Story 5.2, found: $($code.kind)."
    }
    if ($code.retryAllowed -isnot [bool]) {
      Add-Issue $issues "failureCodeVocabulary code $codeName retryAllowed must be a strict boolean."
    }
    if ($code.humanReviewRequired -isnot [bool]) {
      Add-Issue $issues "failureCodeVocabulary code $codeName humanReviewRequired must be a strict boolean."
    }
    if (-not (Test-HasNonEmptyField -Record $code -Field "definition")) {
      Add-Issue $issues "failureCodeVocabulary code $codeName must carry a non-empty definition."
    }
  }
}

# Cross-slice prior source IDs (for com_source_record / sourceRecord resolution).
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

$story13Items = @($story13Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })
$story14Items = @($story14Extraction.extractionRun.proposedWorkItems | Where-Object { $null -ne $_ })

foreach ($sliceLoad in @(
    @{ Name = "manual-source-record-slice sampleRecords"; Count = $manualSources.Count },
    @{ Name = "outlook-source-reference-slice sampleRecords"; Count = $outlookSources.Count },
    @{ Name = "proposed-work-item-extraction-slice proposedWorkItems"; Count = $story13Items.Count },
    @{ Name = "zero-multi-item-extraction-slice proposedWorkItems"; Count = $story14Items.Count }
  )) {
  if ($sliceLoad.Count -eq 0) {
    Add-Issue $issues "No records loaded from $($sliceLoad.Name); its cross-slice checks would silently no-op."
  }
}

# Generic cross-slice id harvest: walk EVERY sibling slice JSON in this folder so
# collision checks cover ALL co-located slices (Story 5.2 hard rule: ids unique
# across ALL slices). Hashtables make membership tests O(1) and immune to
# duplicate-fold bugs. The slice's own file is excluded so its ids are checked
# only for intra-slice uniqueness below, not false-flagged as collisions.
$siblingWorkItemIds = @{}
$siblingReceiptIds = @{}
$siblingIdempotencyKeys = @{}
$siblingSourceRecordIds = @{}
$siblingInstructionIds = @{}
$siblingMemoryCandidateIds = @{}
$siblingSkillIds = @{}
$siblingSliceFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.json" |
  Where-Object { $_.Name -ne "dataverse-mvp-schema-manifest.json" -and $_.Name -ne "skill-authority-expansion-slice.json" } |
  ForEach-Object { $_.FullName })
if ($siblingSliceFiles.Count -eq 0) {
  Add-Issue $issues "No sibling slice JSON files found in $PSScriptRoot; cross-slice id-collision checks would silently no-op."
}
foreach ($siblingFile in $siblingSliceFiles) {
  $siblingJson = Read-JsonInput -Path $siblingFile
  Invoke-CollectSiblingIds -Node $siblingJson -WorkItems $siblingWorkItemIds -Receipts $siblingReceiptIds -Keys $siblingIdempotencyKeys -SourceRecords $siblingSourceRecordIds -Instructions $siblingInstructionIds -MemoryCandidates $siblingMemoryCandidateIds -Skills $siblingSkillIds
}

# Fold sibling source-record ids into the prior-source set used for resolution.
foreach ($sid in @($siblingSourceRecordIds.Keys)) {
  if ($knownPriorSourceIds -notcontains $sid) { $knownPriorSourceIds += $sid }
}

$demoReceiptIds = @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$demoWorkItemIds = @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

if ($knownPriorSourceIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be harvested from sibling slices; sourceRecord resolution checks would silently no-op."
}
if ($siblingReceiptIds.Count -eq 0) {
  Add-Issue $issues "No Receipt IDs could be harvested from sibling slices; receipt collision checks would silently no-op."
}
if ($siblingIdempotencyKeys.Count -eq 0) {
  Add-Issue $issues "No idempotency keys could be harvested from sibling slices; key collision checks would silently no-op."
}

$run = $slice.expansionRun
if ($null -eq $run) {
  Add-Issue $issues "Slice must carry an expansionRun block."
  Write-Host "Skill authority expansion slice validation failed:"
  foreach ($issue in $issues) { Write-Host "- $issue" }
  exit 1
}
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Expansion run must declare a runId."
}
elseif (@([string]$story13Extraction.extractionRun.runId, [string]$story14Extraction.extractionRun.runId) -contains [string]$run.runId) {
  Add-Issue $issues "Expansion run must use a new local runId, not a sibling slice runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Expansion run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Expansion run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Expansion run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json")) {
  if (@($run.inputSlicesFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Expansion run must reference $inputSlice as an input."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Expansion run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("authorityExpansionRequiresExplicitHumanApprovalReceipt", "activationStrictlyFollowsAnApprovalReceiptNotAFlag", "denialConstrainsTheSkillToItsBeforeAuthoritySet", "denialRationaleRemainsVisibleForFutureReview", "beforeAndAfterAuthoritySetsDifferExactlyByTheDeclaredDelta", "liveSkillMutationReceiptGatedToEpic2", "receiptsAreAppendOnlyCorrectionsAreNewReceipts")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Expansion run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Expansion run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# Skills
$skillTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilskill" } | Select-Object -First 1
$skillRequiredFields = @(@($skillTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($skillRequiredFields.Count -eq 0) {
  Add-Issue $issues "No required Skill columns could be derived from manifest com_councilskill; skill required-field checks would silently no-op."
}

$skills = @($run.skills | Where-Object { $null -ne $_ })
if ($skills.Count -ne 2) {
  Add-Issue $issues "Expansion run must include exactly two skills (one approved, one denied), found $($skills.Count)."
}

$approvedSkills = @($skills | Where-Object { [string]$_.decision -eq "approved" })
$deniedSkills = @($skills | Where-Object { [string]$_.decision -eq "denied" })
if ($approvedSkills.Count -ne 1) {
  Add-Issue $issues "Expansion run must include exactly one approved skill, found $($approvedSkills.Count)."
}
if ($deniedSkills.Count -ne 1) {
  Add-Issue $issues "Expansion run must include exactly one denied skill, found $($deniedSkills.Count)."
}

$sliceSkillIds = @{}
$sliceSkillById = @{}
foreach ($skill in $skills) {
  $skillRecord = $skill.skillRecord
  $skillId = [string]$skillRecord.com_council_skill_id
  $subject = "Skill $skillId"

  if ($null -eq $skillRecord) {
    Add-Issue $issues "Skill entry must embed a skillRecord."
    continue
  }
  foreach ($field in $skillRequiredFields) {
    if (-not (Test-HasNonEmptyField -Record $skillRecord -Field $field)) {
      Add-Issue $issues "$subject skillRecord missing required manifest skill field: $field."
    }
  }
  if ([string]::IsNullOrWhiteSpace($skillId)) {
    Add-Issue $issues "Skill skillRecord must declare com_council_skill_id."
  }
  else {
    if ($skillId -notmatch "^CSK-LOCAL-") {
      Add-Issue $issues "$subject must use fresh CSK-LOCAL-* identity, found: $skillId."
    }
    if ($sliceSkillIds.ContainsKey($skillId)) {
      Add-Issue $issues "Duplicate skill id in slice: $skillId."
    }
    else {
      $sliceSkillIds[$skillId] = $skill
    }
    if ($siblingSkillIds.ContainsKey($skillId)) {
      Add-Issue $issues "$subject collides with a skill id from a sibling slice: $skillId."
    }
  }
  $sliceSkillById[$skillId] = $skill

  if ($skill.evidenceStatus -ne "mock_manual_not_tenant_verified") {
    Add-Issue $issues "$subject must be marked mock_manual_not_tenant_verified evidence, found: $($skill.evidenceStatus)."
  }
  if ($authorityClasses -notcontains [string]$skillRecord.com_authority_class) {
    Add-Issue $issues "$subject skillRecord com_authority_class is not in manifest com_authorityclass vocabulary, found: $($skillRecord.com_authority_class)."
  }
  if ($recordStatuses -notcontains [string]$skillRecord.com_status) {
    Add-Issue $issues "$subject skillRecord com_status is not in manifest com_recordstatus vocabulary, found: $($skillRecord.com_status)."
  }
  # The embedded skill record shows the BEFORE state (no live write in this slice); so its
  # authority class must be the before authority class and its status must be non-active
  # until activation is gated to an approval receipt.
  $expansion = $skill.proposedExpansion
  if ($null -eq $expansion) {
    Add-Issue $issues "$subject must declare a proposedExpansion block."
  }
  else {
    $before = $expansion.beforeAuthoritySet
    $after = $expansion.proposedAfterAuthoritySet
    $delta = $expansion.declaredDelta
    Test-AuthoritySetShape -Issues $issues -Set $before -Subject "$subject beforeAuthoritySet" -AuthorityClassVocab $authorityClasses
    Test-AuthoritySetShape -Issues $issues -Set $after -Subject "$subject proposedAfterAuthoritySet" -AuthorityClassVocab $authorityClasses
    Test-DeltaExact -Issues $issues -Before $before -After $after -Delta $delta -Subject $subject
    # The embedded skill record's authority class must equal the before authority class.
    if ($null -ne $before -and [string]$skillRecord.com_authority_class -ne [string]$before.authorityClass) {
      Add-Issue $issues "$subject skillRecord com_authority_class ($($skillRecord.com_authority_class)) must equal beforeAuthoritySet.authorityClass ($($before.authorityClass)); the embedded record shows the pre-expansion state."
    }
    if (-not (Test-HasNonEmptyField -Record $expansion -Field "approvalRequiredReason")) {
      Add-Issue $issues "$subject proposedExpansion must carry a non-empty approvalRequiredReason."
    }
    elseif ([string]$expansion.approvalRequiredReason -notmatch "FR25") {
      Add-Issue $issues "$subject proposedExpansion.approvalRequiredReason must cite FR25 (authority expansion requires approval)."
    }
    if ([string]$skill.expansionKind -ne "installation") {
      Add-Issue $issues "$subject expansionKind must be installation for this slice (new skill installs), found: $($skill.expansionKind)."
    }
  }

  # Source record ref must resolve to a known prior Source Record (REFERENCED id).
  if (Test-HasNonEmptyField -Record $skill -Field "sourceRecord") {
    $sourceRef = [string]$skill.sourceRecord
    if ($knownPriorSourceIds -notcontains $sourceRef) {
      Add-Issue $issues "$subject sourceRecord must reference a known Source Record from a sibling slice, found: $sourceRef."
    }
  }
  else {
    Add-Issue $issues "$subject must reference a source record (sourceRecord)."
  }

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($skillRecord.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 5.2 skills are local contract evidence only."
    }
    if ($skill.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 5.2 skills are local contract evidence only."
    }
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
if ($receipts.Count -ne 2) {
  Add-Issue $issues "Expansion run must include exactly two receipts (one approval, one denial), found $($receipts.Count)."
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
    if ($receiptId -notmatch "^CR-LOCAL-SKILL-") {
      Add-Issue $issues "$subject must use Council-level CR-LOCAL-SKILL-* identity."
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
    if ($demoReceiptIds -contains $receiptId) {
      Add-Issue $issues "$subject collides with a reserved state-transition-demo receipt ID."
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
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 5.2 receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 5.2 receipts are local contract evidence only."
      }
    }
  }
}

# Approval receipt: verb=approved, actor=human, actor_id=Doug, result=accepted, before/after authority sets present.
$approvalReceipts = @($receipts | Where-Object { [string]$_.com_verb -eq "approved" })
if ($approvalReceipts.Count -ne 1) {
  Add-Issue $issues "Slice must include exactly one approval receipt (verb approved), found $($approvalReceipts.Count)."
}
foreach ($approval in $approvalReceipts) {
  $approvalId = [string]$approval.com_receipt_id
  $subject = "Receipt $approvalId"
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
  Test-AuthoritySetShape -Issues $issues -Set $approval.beforeAuthoritySet -Subject "$subject beforeAuthoritySet" -AuthorityClassVocab $authorityClasses
  Test-AuthoritySetShape -Issues $issues -Set $approval.afterAuthoritySet -Subject "$subject afterAuthoritySet" -AuthorityClassVocab $authorityClasses
  # The approval receipt's before/after authority sets must match the approved skill's proposedExpansion.
  if ($approvedSkills.Count -eq 1) {
    $approvedSkill = $approvedSkills[0]
    $ap = $approvedSkill.proposedExpansion
    if ($null -ne $ap) {
      if (-not (Compare-AuthoritySet -SetA $approval.beforeAuthoritySet -SetB $ap.beforeAuthoritySet)) {
        Add-Issue $issues "$subject beforeAuthoritySet must match the approved skill's proposedExpansion.beforeAuthoritySet."
      }
      if (-not (Compare-AuthoritySet -SetA $approval.afterAuthoritySet -SetB $ap.proposedAfterAuthoritySet)) {
        Add-Issue $issues "$subject afterAuthoritySet must match the approved skill's proposedExpansion.proposedAfterAuthoritySet."
      }
    }
  }
}

# Denial receipt: verb=policy_denied, result=rejected, failure code declared, before + proposedAfter authority sets present, denial rationale.
$denialReceipts = @($receipts | Where-Object { [string]$_.com_verb -eq "policy_denied" })
if ($denialReceipts.Count -ne 1) {
  Add-Issue $issues "Slice must include exactly one policy_denied receipt (verb policy_denied), found $($denialReceipts.Count)."
}
foreach ($denial in $denialReceipts) {
  $denialId = [string]$denial.com_receipt_id
  $subject = "Receipt $denialId"
  if ([string]$denial.com_actor_type -ne "human") {
    Add-Issue $issues "$subject actor type must be human for a skill authority denial receipt, found: $($denial.com_actor_type)."
  }
  if ([string]$denial.com_result -ne "rejected") {
    Add-Issue $issues "$subject result must be rejected for a policy_denied receipt, found: $($denial.com_result)."
  }
  if (Test-HasNonEmptyField -Record $denial -Field "com_failure_code") {
    $failureCode = [string]$denial.com_failure_code
    if (-not $declaredFailureCodes.ContainsKey($failureCode)) {
      Add-Issue $issues "$subject com_failure_code must be declared in failureCodeVocabulary, found: $failureCode."
    }
  }
  else {
    Add-Issue $issues "$subject must carry a non-empty com_failure_code declared in failureCodeVocabulary."
  }
  if (-not (Test-HasNonEmptyField -Record $denial -Field "denialRationale")) {
    Add-Issue $issues "$subject must carry a non-empty denialRationale visible for future review."
  }
  Test-AuthoritySetShape -Issues $issues -Set $denial.beforeAuthoritySet -Subject "$subject beforeAuthoritySet" -AuthorityClassVocab $authorityClasses
  Test-AuthoritySetShape -Issues $issues -Set $denial.proposedAfterAuthoritySet -Subject "$subject proposedAfterAuthoritySet" -AuthorityClassVocab $authorityClasses
  # The denial receipt's before/proposedAfter authority sets must match the denied skill's proposedExpansion.
  if ($deniedSkills.Count -eq 1) {
    $deniedSkill = $deniedSkills[0]
    $dp = $deniedSkill.proposedExpansion
    if ($null -ne $dp) {
      if (-not (Compare-AuthoritySet -SetA $denial.beforeAuthoritySet -SetB $dp.beforeAuthoritySet)) {
        Add-Issue $issues "$subject beforeAuthoritySet must match the denied skill's proposedExpansion.beforeAuthoritySet."
      }
      if (-not (Compare-AuthoritySet -SetA $denial.proposedAfterAuthoritySet -SetB $dp.proposedAfterAuthoritySet)) {
        Add-Issue $issues "$subject proposedAfterAuthoritySet must match the denied skill's proposedExpansion.proposedAfterAuthoritySet."
      }
    }
  }
  # The denial receipt's com_after_state must NOT record the expanded authority (the expansion was denied).
  if (Test-HasNonEmptyField -Record $denial -Field "com_after_state") {
    $afterState = [string]$denial.com_after_state
    if ($afterState -match "approved_automatic" -or ($afterState -match "write" -and $afterState -match "fabric")) {
      Add-Issue $issues "$subject com_after_state must record the constrained (denied) state, not the denied expansion authority; found: $afterState."
    }
  }
}

# Per-skill decision binding + activation/denial checks (general rules over the collection).
foreach ($skill in $skills) {
  $skillRecord = $skill.skillRecord
  $skillId = [string]$skillRecord.com_council_skill_id
  $subject = "Skill $skillId"
  $decision = [string]$skill.decision
  $decisionReceiptId = [string]$skill.decisionReceipt
  $boundReceipt = $null
  if ([string]::IsNullOrWhiteSpace($decisionReceiptId) -or -not $sliceReceiptIds.ContainsKey($decisionReceiptId)) {
    Add-Issue $issues "$subject decisionReceipt must reference a receipt that exists in this slice, found: $decisionReceiptId."
  }
  else {
    $boundReceipt = $sliceReceiptIds[$decisionReceiptId]
  }

  if ($decision -eq "approved") {
    if ($null -ne $boundReceipt) {
      if ([string]$boundReceipt.com_verb -ne "approved") {
        Add-Issue $issues "$subject decisionReceipt must reference an approval receipt (verb approved), found verb: $($boundReceipt.com_verb)."
      }
      if ([string]$boundReceipt.com_result -ne "accepted") {
        Add-Issue $issues "$subject decisionReceipt must reference a receipt with result accepted, found: $($boundReceipt.com_result)."
      }
      if ([string]$boundReceipt.com_actor_type -ne "human") {
        Add-Issue $issues "$subject decisionReceipt must reference a human-actor receipt, found actor type: $($boundReceipt.com_actor_type)."
      }
    }
    # Activation strictly follows an approval receipt: temporal + receipt-chain, NOT a self-asserted flag.
    $activation = $skill.activation
    if ($null -eq $activation) {
      Add-Issue $issues "$subject (approved) must declare an activation block gated to the approval receipt."
    }
    else {
      $gateId = [string]$activation.gateReceipt
      if ([string]::IsNullOrWhiteSpace($gateId) -or -not $sliceReceiptIds.ContainsKey($gateId)) {
        Add-Issue $issues "$subject activation.gateReceipt must reference a receipt that exists in this slice, found: $gateId."
      }
      elseif ($gateId -ne $decisionReceiptId) {
        Add-Issue $issues "$subject activation.gateReceipt ($gateId) must equal the skill's decisionReceipt ($decisionReceiptId); activation is gated to the approval receipt that decided this expansion."
      }
      else {
        $gateReceipt = $sliceReceiptIds[$gateId]
        if ([string]$gateReceipt.com_verb -ne "approved" -or [string]$gateReceipt.com_result -ne "accepted") {
          Add-Issue $issues "$subject activation.gateReceipt must be an approved/accepted receipt, found verb $($gateReceipt.com_verb) result $($gateReceipt.com_result)."
        }
        # Temporal check: activation.effectiveAt must be on or after the gate receipt's com_occurred_at.
        $effectiveAt = Test-IsoTimestamp -Issues $issues -Record $activation -Field "effectiveAt" -Subject "$subject activation"
        $gateAt = $null
        if ($null -ne $gateReceipt) { $gateAt = Get-ComparableInstant $gateReceipt.com_occurred_at }
        if ($null -ne $effectiveAt -and $null -ne $gateAt -and $effectiveAt -lt $gateAt) {
          Add-Issue $issues "$subject activation.effectiveAt ($($activation.effectiveAt)) must be on or after the approval receipt com_occurred_at ($($gateReceipt.com_occurred_at)); activation strictly follows approval (temporal check, not a flag)."
        }
      }
      # Activated authority set must equal the proposed after authority set.
      if ($null -ne $skill.proposedExpansion) {
        if (-not (Compare-AuthoritySet -SetA $activation.activatedAuthoritySet -SetB $skill.proposedExpansion.proposedAfterAuthoritySet)) {
          Add-Issue $issues "$subject activation.activatedAuthoritySet must equal proposedExpansion.proposedAfterAuthoritySet."
        }
      }
      if ($skill.PSObject.Properties.Name -contains "denial") {
        Add-Issue $issues "$subject (approved) must not carry a denial block."
      }
      # The gateReceipt must not be a self-asserted boolean; the activation must not carry a bare boolean flag
      # claiming approval (e.g. an "approved": true field). Only the receipt-chain + temporal checks count.
      foreach ($forbiddenFlag in @("approved", "isApproved", "activationApproved")) {
        if ($activation.PSObject.Properties.Name -contains $forbiddenFlag -and $activation.$forbiddenFlag -is [bool]) {
          Add-Issue $issues "$subject activation must not carry a self-asserted boolean '$forbiddenFlag'; activation follows the approval receipt chain + temporal check, not a flag."
        }
      }
    }
  }
  elseif ($decision -eq "denied") {
    if ($null -ne $boundReceipt) {
      if ([string]$boundReceipt.com_verb -ne "policy_denied") {
        Add-Issue $issues "$subject decisionReceipt must reference a policy_denied receipt (verb policy_denied), found verb: $($boundReceipt.com_verb)."
      }
      if ([string]$boundReceipt.com_result -ne "rejected") {
        Add-Issue $issues "$subject decisionReceipt must reference a receipt with result rejected, found: $($boundReceipt.com_result)."
      }
    }
    # Denied skill must have NO activation block (denied expansions do not activate).
    if ($skill.PSObject.Properties.Name -contains "activation") {
      Add-Issue $issues "$subject (denied) must not carry an activation block; denied expansions do not activate."
    }
    # Denied skill status must remain non-active.
    if ([string]$skillRecord.com_status -eq "active") {
      Add-Issue $issues "$subject (denied) skillRecord com_status must remain non-active (inactive or constrained), found: active."
    }
    $denial = $skill.denial
    if ($null -eq $denial) {
      Add-Issue $issues "$subject (denied) must declare a denial block with rationale visible for future review."
    }
    else {
      if (-not (Test-HasNonEmptyField -Record $denial -Field "denialRationale")) {
        Add-Issue $issues "$subject denial.denialRationale must be non-empty so the rationale stays visible for future review."
      }
      # Effective authority set must equal the before authority set (constrained to before; no expansion applied).
      if ($null -ne $skill.proposedExpansion) {
        if (-not (Compare-AuthoritySet -SetA $denial.effectiveAuthoritySet -SetB $skill.proposedExpansion.beforeAuthoritySet)) {
          Add-Issue $issues "$subject denial.effectiveAuthoritySet must equal proposedExpansion.beforeAuthoritySet; a denied expansion constrains the skill to its before authority."
        }
      }
      if ([string]$denial.denialReceipt -ne $decisionReceiptId) {
        Add-Issue $issues "$subject denial.denialReceipt ($($denial.denialReceipt)) must equal the skill's decisionReceipt ($decisionReceiptId)."
      }
      $policyFlags = @($denial.policyFlagsTraced | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
      if ($policyFlags.Count -lt 2) {
        Add-Issue $issues "$subject denial.policyFlagsTraced must list at least two policy flags driving the denial."
      }
      # Traced evidence refs must resolve within the slice (CSK) or cross-slice (CSR).
      $evidenceRefs = @($denial.evidenceRefsTraced | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
      if ($evidenceRefs.Count -lt 1) {
        Add-Issue $issues "$subject denial.evidenceRefsTraced must list at least one evidence ref."
      }
      foreach ($ref in $evidenceRefs) {
        $refStr = [string]$ref
        if ($refStr -like "CSK-LOCAL-*") {
          if (-not $sliceSkillIds.ContainsKey($refStr)) {
            Add-Issue $issues "$subject denial.evidenceRefsTraced CSK ref must resolve to a slice skill, found: $refStr."
          }
        }
        elseif ($refStr -like "CSR-*") {
          if ($knownPriorSourceIds -notcontains $refStr) {
            Add-Issue $issues "$subject denial.evidenceRefsTraced CSR ref must resolve to a known Source Record, found: $refStr."
          }
        }
        else {
          Add-Issue $issues "$subject denial.evidenceRefsTraced ref must be a CSK-LOCAL-* or CSR-* id, found: $refStr."
        }
      }
    }
  }
  else {
    Add-Issue $issues "$subject decision must be 'approved' or 'denied', found: $decision."
  }
}

# Receipt source links: each decision receipt must be bound to its source by a link with the right role.
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
# Approval receipt -> at least one link with role approval.
foreach ($approval in $approvalReceipts) {
  $approvalId = [string]$approval.com_receipt_id
  $approvalLinks = @($links | Where-Object { [string]$_.com_receipt -eq $approvalId })
  if ($approvalLinks.Count -lt 1) {
    Add-Issue $issues "Receipt $approvalId must be bound to its source evidence by at least one receipt source link."
  }
  elseif (@($approvalLinks | Where-Object { [string]$_.com_evidence_role -eq "approval" }).Count -lt 1) {
    Add-Issue $issues "Receipt $approvalId must have at least one receipt source link with com_evidence_role approval."
  }
}
# Denial receipt -> at least one link with role failure_evidence.
foreach ($denial in $denialReceipts) {
  $denialId = [string]$denial.com_receipt_id
  $denialLinks = @($links | Where-Object { [string]$_.com_receipt -eq $denialId })
  if ($denialLinks.Count -lt 1) {
    Add-Issue $issues "Receipt $denialId must be bound to its source evidence by at least one receipt source link."
  }
  elseif (@($denialLinks | Where-Object { [string]$_.com_evidence_role -eq "failure_evidence" }).Count -lt 1) {
    Add-Issue $issues "Receipt $denialId must have at least one receipt source link with com_evidence_role failure_evidence."
  }
}

# Deferred skill updates: every skill's live mutation must be a deferred entry naming a receipt gate.
$deferredUpdates = @($run.skillUpdatesDeferred | Where-Object { $null -ne $_ })
if ($deferredUpdates.Count -lt $skills.Count) {
  Add-Issue $issues "Every skill must have a deferred update entry; found $($deferredUpdates.Count) deferred entries for $($skills.Count) skills."
}
$deferredBySkill = @{}
foreach ($deferred in $deferredUpdates) {
  $deferredSkill = [string]$deferred.skill
  $subject = "Deferred skill update $deferredSkill"
  if ([string]::IsNullOrWhiteSpace($deferredSkill) -or -not $sliceSkillIds.ContainsKey($deferredSkill)) {
    Add-Issue $issues "$subject references an unknown skill: $deferredSkill."
    continue
  }
  $deferredBySkill[$deferredSkill] = $deferred
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "$subject must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "$subject deferredUpdate must state that the live mutation is receipt-gated."
  }
  # gateReceipt on the deferred entry must resolve to a slice receipt.
  if (Test-HasNonEmptyField -Record $deferred -Field "gateReceipt") {
    $gateRef = [string]$deferred.gateReceipt
    if (-not $sliceReceiptIds.ContainsKey($gateRef)) {
      Add-Issue $issues "$subject gateReceipt must reference a receipt that exists in this slice, found: $gateRef."
    }
    elseif ($gateRef -ne [string]$sliceSkillIds[$deferredSkill].decisionReceipt) {
      Add-Issue $issues "$subject gateReceipt ($gateRef) must equal the skill's decisionReceipt ($([string]$sliceSkillIds[$deferredSkill].decisionReceipt))."
    }
  }
}
foreach ($skillId in @($sliceSkillIds.Keys)) {
  if (-not $deferredBySkill.ContainsKey($skillId)) {
    Add-Issue $issues "Missing deferred skill update entry for $skillId; live skill mutation must be receipt-gated."
  }
}

# Acceptance mapping for AC 1, 2. localEvidence must not be self-asserting prose:
# every CR-LOCAL-SKILL-*, CSK-LOCAL-*, and CSR-* id it cites must resolve to a real
# slice entity (receipt/skill) or a known cross-slice Source Record, and each AC
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
  $citedIds = [regex]::Matches($joinedEvidence, "(?:CR-LOCAL-SKILL-[A-Z0-9-]+|CSK-LOCAL-[A-Z0-9-]+|CSR-[A-Z0-9-]+)") | ForEach-Object { [string]$_.Value } | Sort-Object -Unique
  $citedAny = $false
  foreach ($citedId in $citedIds) {
    $resolved = $false
    if ($citedId -like "CR-LOCAL-SKILL-*") {
      if ($sliceReceiptIds.ContainsKey($citedId)) { $resolved = $true }
    }
    elseif ($citedId -like "CSK-LOCAL-*") {
      if ($sliceSkillIds.ContainsKey($citedId)) { $resolved = $true }
    }
    elseif ($citedId -like "CSR-*") {
      if ($knownPriorSourceIds -contains $citedId) { $resolved = $true }
    }
    if (-not $resolved) {
      Add-Issue $issues "Acceptance mapping for AC $criterion cites id '$citedId' which does not resolve to any receipt, skill, or known Source Record in this slice."
    }
    else {
      $citedAny = $true
    }
  }
  if (-not $citedAny) {
    Add-Issue $issues "Acceptance mapping for AC $criterion must cite at least one real slice id (CR-LOCAL-SKILL-*/CSK-LOCAL-*/CSR-*) in localEvidence; self-asserting prose is not proof."
  }
}

if ($issues.Count -gt 0) {
  Write-Host "Skill authority expansion slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Skill authority expansion slice validation succeeded."
Write-Host "Skills: $($skills.Count)"
Write-Host "Approved skills: $($approvedSkills.Count)"
Write-Host "Denied skills: $($deniedSkills.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "Deferred skill updates: $($deferredUpdates.Count)"
Write-Host "SKILL_AUTHORITY_EXPANSION_SLICE_VALIDATE_OK"
