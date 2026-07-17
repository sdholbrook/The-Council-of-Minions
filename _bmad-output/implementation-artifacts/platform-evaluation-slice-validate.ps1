param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$PlatformSlicePath = "$PSScriptRoot\platform-evaluation-slice.json",
  [string]$TenantDecisionPacketPath = "$PSScriptRoot\tenant-decision-packet.json",
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

  if ($null -eq $Record) { return $false }
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

function Read-JsonInput {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  try {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  }
  catch {
    Write-Host "Platform evaluation slice validation failed:"
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
  if ($null -eq $Node) { return @($ids) }
  $json = ConvertTo-Json $Node -Depth 20 -Compress
  foreach ($m in [regex]::Matches($json, $Pattern)) {
    $ids.Add($m.Value) | Out-Null
  }
  @($ids)
}

# Walk the parsed object graph and collect every property name, so implementation-marker
# detection runs over real keys (not a raw-text substring scan that would misfire on the
# sanctioned implementationArtifactsReferenced field).
function Collect-PropertyNames {
  param(
    [Parameter(Mandatory = $true)]$Node,
    [AllowEmptyCollection()][System.Collections.Generic.List[string]]$Accumulator
  )

  if ($null -eq $Node) { return }
  if ($Node -is [System.Management.Automation.PSCustomObject]) {
    foreach ($prop in @($Node.PSObject.Properties)) {
      $Accumulator.Add($prop.Name) | Out-Null
      Collect-PropertyNames -Node $prop.Value -Accumulator $Accumulator
    }
  }
  elseif ($Node -is [System.Array] -or $Node -is [System.Collections.IList]) {
    foreach ($item in @($Node)) {
      Collect-PropertyNames -Node $item -Accumulator $Accumulator
    }
  }
}

foreach ($path in @($ManifestPath, $PlatformSlicePath, $TenantDecisionPacketPath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required platform evaluation validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$platform = Read-JsonInput -Path $PlatformSlicePath
$tenantPacket = Read-JsonInput -Path $TenantDecisionPacketPath
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath
$rawSliceText = Get-Content -LiteralPath $PlatformSlicePath -Raw
$issues = [System.Collections.Generic.List[string]]::new()

$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$platformDecisions = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_platformdecision"

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_platformdecision"; Values = $platformDecisions }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

$peTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilplatformevaluation" } | Select-Object -First 1
if ($null -eq $peTable) {
  Add-Issue $issues "Manifest must define the com_councilplatformevaluation table."
}
$manifestRequiredPeFields = @()
if ($null -ne $peTable) {
  $manifestRequiredPeFields = @(@($peTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
if ($manifestRequiredPeFields.Count -eq 0) {
  Add-Issue $issues "No required columns could be derived from manifest com_councilplatformevaluation; row completeness checks would silently no-op."
}

# The story enumerates the row capture set as tenant gates, permission/DLP impact,
# licensing/cost, ALM path, contract gaps, decision, and review reference. Six of
# these (com_tenant_gate, com_permission_dlp_impact, com_licensing_cost_gate,
# com_lifecycle_alm_path, com_contract_gaps, com_review_reference) are
# manifest-optional, so a manifest-required-only completeness check silently drops
# them. Row completeness is therefore asserted over the UNION of the manifest-
# required PE columns and this story-mandated capture set, never over the
# manifest-required subset alone. com_decision already sits in the manifest-required
# set, so the union reproduces all seven story-mandated row fields.
$storyMandatedRowFields = @(
  "com_tenant_gate",
  "com_permission_dlp_impact",
  "com_licensing_cost_gate",
  "com_lifecycle_alm_path",
  "com_contract_gaps",
  "com_review_reference"
)
$rowCompletenessFields = @($manifestRequiredPeFields + $storyMandatedRowFields) | Sort-Object -Unique
if ($rowCompletenessFields.Count -eq 0) {
  Add-Issue $issues "Row completeness field set is empty; row completeness checks would silently no-op."
}

$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @()
if ($null -ne $receiptTable) {
  $manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique

# The named candidate universe is fixed by the story spec; the slice must reproduce it exactly so no
# candidate outside the enumerated set is admitted and coverage is derived against a closed vocabulary.
$specCandidateUniverse = @(
  "Work IQ",
  "Dataverse intelligence/MCP",
  "Power Apps MCP agent feed",
  "Copilot Studio",
  "Power Automate",
  "Fabric IQ/Graph",
  "Fabric data agents"
)

# Slice header.
if ($platform.storyKey -ne "5-3-record-microsoft-platform-evaluation-evidence") {
  Add-Issue $issues "Platform evaluation slice storyKey must be 5-3-record-microsoft-platform-evaluation-evidence."
}
if ([string]$platform.status -notmatch "^local-contract") {
  Add-Issue $issues "Platform evaluation slice status must declare local contract evidence, found: $($platform.status)."
}

# Guards.
$requiredGuards = @(
  "noTenantWrites",
  "noOutboundAction",
  "noApprovalExecution",
  "requiresExplicitHumanApprovalForExecution",
  "microsoftNativeEvaluatedBeforeCustomSubstrate",
  "customServicesMustCiteMicrosoftGap",
  "decisionsRecordedBeforeImplementation",
  "receiptsAreLocalContractEvidenceOnly",
  "noImplementationArtifactsReferenced"
)
foreach ($guard in $requiredGuards) {
  if (-not ($platform.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Platform evaluation slice must declare guard: $guard."
  }
}
if ($null -ne $platform.guards) {
  foreach ($guardProperty in @($platform.guards.PSObject.Properties)) {
    if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
      Add-Issue $issues "Platform evaluation guard must be boolean true: $($guardProperty.Name)."
    }
  }
}

$run = $platform.platformEvaluationRun
if ($null -eq $run) {
  Add-Issue $issues "Platform evaluation slice must carry a platformEvaluationRun block."
  Write-Host "Platform evaluation slice validation failed:"
  foreach ($issue in $issues) { Write-Host "- $issue" }
  exit 1
}

# Run header.
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Platform evaluation run must declare a runId."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Platform evaluation run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Platform evaluation run must carry a non-empty ${field}."
  }
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Platform evaluation run semanticContractVersion must be 2026-07-07."
}
if (@($run.inputDecisionsFrom) -notcontains "tenant-decision-packet.json") {
  Add-Issue $issues "Platform evaluation run must reference tenant-decision-packet.json as an input decision source."
}

# decisionPolicy.
$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Platform evaluation run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("microsoftNativePlanesEvaluatedBeforeCustomSubstrate", "customServiceMustCiteSpecificMicrosoftGapOrTenantConstraint", "decisionsRecordedAsReceiptsBeforeAnyImplementation", "receiptsAreLocalContractEvidenceOnly", "noLiveDataverseMutationInThisSlice", "evaluationRowsMapToManifestComCouncilplatformevaluation")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Platform evaluation run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Platform evaluation run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# candidateUniverse must reproduce the spec set exactly.
$sliceUniverse = @($run.candidateUniverse | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($sliceUniverse.Count -eq 0) {
  Add-Issue $issues "Platform evaluation run must declare a candidateUniverse; coverage checks would silently no-op."
}
else {
  $missingFromSlice = @($specCandidateUniverse | Where-Object { $sliceUniverse -notcontains $_ })
  foreach ($missing in $missingFromSlice) {
    Add-Issue $issues "Platform evaluation run candidateUniverse is missing the spec-required candidate: $missing."
  }
  $extraInSlice = @($sliceUniverse | Where-Object { $specCandidateUniverse -notcontains $_ })
  foreach ($extra in $extraInSlice) {
    Add-Issue $issues "Platform evaluation run candidateUniverse admits a candidate outside the spec set: $extra."
  }
}

# Evaluations: coverage derived (not counted), row completeness, valid decisions.
$evaluations = @($run.evaluations | Where-Object { $null -ne $_ })
if ($evaluations.Count -lt 2) {
  Add-Issue $issues "Platform evaluation slice must include at least two capability evaluations, found $($evaluations.Count)."
}

$allRowIds = [System.Collections.Generic.List[string]]::new()
$allRowIdToDecision = @{}
$allRowIdToGaps = @{}
$allRowIdToCapability = @{}
$seenEvaluationIds = @{}
foreach ($evaluation in $evaluations) {
  $evalId = [string]$evaluation.capabilityEvaluationId
  $subject = "Evaluation $evalId"
  if ([string]::IsNullOrWhiteSpace($evalId)) {
    Add-Issue $issues "Evaluation must declare a capabilityEvaluationId."
  }
  elseif ($seenEvaluationIds.ContainsKey($evalId)) {
    Add-Issue $issues "Duplicate evaluation capabilityEvaluationId: $evalId."
  }
  else {
    $seenEvaluationIds[$evalId] = $true
  }
  if (-not (Test-HasNonEmptyField -Record $evaluation -Field "com_council_capability")) {
    Add-Issue $issues "$subject must carry a non-empty com_council_capability."
  }
  if (-not (Test-HasNonEmptyField -Record $evaluation -Field "capabilityQuestion")) {
    Add-Issue $issues "$subject must carry a non-empty capabilityQuestion."
  }

  $rows = @($evaluation.candidateRows | Where-Object { $null -ne $_ })
  if ($rows.Count -lt 4) {
    Add-Issue $issues "$subject must consider at least four Microsoft candidates, found $($rows.Count)."
  }

  $seenCandidatesInEval = @{}
  $seenRowIdsInEval = @{}
  foreach ($row in $rows) {
    $rowId = [string]$row.rowId
    $rowSubject = "$subject row $rowId"
    if ([string]::IsNullOrWhiteSpace($rowId)) {
      Add-Issue $issues "$subject candidate row must declare a rowId."
    }
    else {
      if ($seenRowIdsInEval.ContainsKey($rowId)) {
        Add-Issue $issues "$subject duplicate rowId: $rowId."
      }
      else { $seenRowIdsInEval[$rowId] = $true }
      if ($allRowIds -contains $rowId) {
        Add-Issue $issues "Evaluation row rowId must be unique across all evaluations: $rowId."
      }
      else { $allRowIds.Add($rowId) | Out-Null }
    }

    foreach ($field in $rowCompletenessFields) {
      if (-not (Test-HasNonEmptyField -Record $row -Field $field)) {
        Add-Issue $issues "$rowSubject missing row completeness field (manifest-required or story-mandated capture set): $field."
      }
    }

    $candidate = [string]$row.com_microsoft_candidate
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      Add-Issue $issues "$rowSubject must declare a com_microsoft_candidate."
    }
    else {
      if ($specCandidateUniverse -notcontains $candidate) {
        Add-Issue $issues "$rowSubject com_microsoft_candidate must come from the named candidate universe, found: $candidate."
      }
      if ($seenCandidatesInEval.ContainsKey($candidate)) {
        Add-Issue $issues "$subject must not evaluate the same candidate twice: $candidate."
      }
      else { $seenCandidatesInEval[$candidate] = $true }
    }

    if ($platformDecisions -notcontains [string]$row.com_decision) {
      Add-Issue $issues "$rowSubject com_decision must use manifest com_platformdecision vocabulary, found: $($row.com_decision)."
    }
    if (-not [string]::IsNullOrWhiteSpace($rowId)) {
      $allRowIdToDecision[$rowId] = [string]$row.com_decision
      $allRowIdToGaps[$rowId] = [string]$row.com_contract_gaps
      $allRowIdToCapability[$rowId] = [string]$evaluation.com_council_capability
    }
  }
}

# Custom-service proposals: gap citation resolves to a recorded gap; decision receipt precedes implementation.
$proposals = @($run.customServiceProposals | Where-Object { $null -ne $_ })
if ($proposals.Count -lt 1) {
  Add-Issue $issues "Platform evaluation slice must include at least one custom-service proposal."
}

$seenProposalIds = @{}
foreach ($proposal in $proposals) {
  $proposalId = [string]$proposal.proposalId
  $pSubject = "Custom proposal $proposalId"
  if ([string]::IsNullOrWhiteSpace($proposalId)) {
    Add-Issue $issues "Custom-service proposal must declare a proposalId."
  }
  elseif ($seenProposalIds.ContainsKey($proposalId)) {
    Add-Issue $issues "Duplicate custom-service proposal proposalId: $proposalId."
  }
  else { $seenProposalIds[$proposalId] = $true }

  if (-not (Test-HasNonEmptyField -Record $proposal -Field "com_name")) {
    Add-Issue $issues "$pSubject must carry a non-empty com_name."
  }
  if (-not (Test-HasNonEmptyField -Record $proposal -Field "com_council_capability")) {
    Add-Issue $issues "$pSubject must carry a non-empty com_council_capability."
  }

  $gapRowId = [string]$proposal.addressesGapInRow
  if ([string]::IsNullOrWhiteSpace($gapRowId)) {
    Add-Issue $issues "$pSubject must declare addressesGapInRow pointing to an evaluation candidate row."
  }
  elseif ($allRowIds -notcontains $gapRowId) {
    Add-Issue $issues "$pSubject addressesGapInRow must reference a real evaluation candidate row minted in this slice, found: $gapRowId."
  }
  else {
    $gapDecision = [string]$allRowIdToDecision[$gapRowId]
    if ($gapDecision -ne "custom_gap_build") {
      Add-Issue $issues "$pSubject addressesGapInRow must point to a row whose com_decision records a gap (custom_gap_build); row $gapRowId decision is '$gapDecision'."
    }
    $gapText = [string]$allRowIdToGaps[$gapRowId]
    if (-not (Test-HasNonEmptyField -Record $proposal -Field "gapCitation")) {
      Add-Issue $issues "$pSubject must carry a non-empty gapCitation."
    }
    else {
      # The citation must reference the RECORDED gap. General rule, no slice-specific
      # vocabulary: (1) it must cite the row by id; (2) the cited row must actually
      # record non-empty com_contract_gaps text (a "recorded gap" is not just a row
      # id + decision label); (3) it must substantively overlap that recorded gap text
      # via a verbatim contiguous run of word-tokens drawn from the cited row's own
      # com_contract_gaps. Counting isolated shared terms is insufficient — two
      # unrelated rows can share "contract" and "semantics" as isolated tokens while
      # the citation describes a different row's gap, so a count is not proof. Both
      # texts are normalized identically (lowercased, non [a-z0-9_/-] runs collapsed
      # to spaces) so the tie is content-driven and survives punctuation or casing
      # reflows; the cited row's gap text supplies the phrases, never this slice's
      # own vocabulary.
      $citation = [string]$proposal.gapCitation
      if ($citation -notmatch [regex]::Escape($gapRowId)) {
        Add-Issue $issues "$pSubject gapCitation must cite the recorded gap row by id ($gapRowId)."
      }
      if ([string]::IsNullOrWhiteSpace($gapText)) {
        Add-Issue $issues "$pSubject addressesGapInRow $gapRowId, but that row records no com_contract_gaps text; the custom proposal must cite a recorded gap, not just a row id and decision label."
      }
      else {
        # Derive a structural tie between the citation and the cited row's recorded
        # gap text: a verbatim contiguous run of word-tokens drawn from that row's own
        # com_contract_gaps must appear in the citation. A contiguous run (not a count
        # of isolated terms) is required because isolated generic vocabulary recurs
        # across many rows and would let a citation describing a different row's gap
        # pass. Both strings are normalized identically so the comparison is purely
        # content-driven.
        $normCitation = [string]((([string]$citation).ToLower() -replace '[^a-z0-9_/-]+', ' ') -replace '\s+', ' ')
        $citationTokens = @($normCitation.Trim() -split ' ' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $normGap = [string]((([string]$gapText).ToLower() -replace '[^a-z0-9_/-]+', ' ') -replace '\s+', ' ')
        $gapTokens = @($normGap.Trim() -split ' ' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        # Token-boundary-aware containment: the delimiter never appears inside a
        # normalized token (tokens are [a-z0-9_/-] only), so a delimited phrase can
        # only match whole tokens, never a prefix of one (e.g. "semantic" must not
        # match inside "semantics"). That is what makes the tie a true phrase match
        # rather than a bare substring scan.
        $phraseDelim = '|'
        $citationBlob = $phraseDelim + ($citationTokens -join $phraseDelim) + $phraseDelim
        $phraseHit = $false
        $requiredRunLength = 3
        $lastStart = $gapTokens.Count - $requiredRunLength
        for ($i = 0; $i -le $lastStart; $i++) {
          $phrase = $phraseDelim + ($gapTokens[$i..($i + $requiredRunLength - 1)] -join $phraseDelim) + $phraseDelim
          if ($citationBlob.IndexOf($phrase, [System.StringComparison]::Ordinal) -ge 0) {
            $phraseHit = $true
            break
          }
        }
        if (-not $phraseHit) {
          Add-Issue $issues "$pSubject gapCitation must substantively reference the recorded gap text in row $gapRowId (a verbatim contiguous run of at least $requiredRunLength word-tokens drawn from that row's com_contract_gaps); isolated shared vocabulary is not sufficient."
        }
      }
    }
  }

  if (-not (Test-HasNonEmptyField -Record $proposal -Field "tenantConstraintCited")) {
    Add-Issue $issues "$pSubject must carry a non-empty tenantConstraintCited."
  }
  if (-not (Test-HasNonEmptyField -Record $proposal -Field "proposalRationale")) {
    Add-Issue $issues "$pSubject must carry a non-empty proposalRationale."
  }

  # Implementation artifacts: the slice must not reference any; the sanctioned list must be empty.
  $implRefs = @($proposal.implementationArtifactsReferenced | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($implRefs.Count -gt 0) {
    Add-Issue $issues "$pSubject must not reference implementation artifacts; found: $($implRefs -join ', ')."
  }

  $decisionReceiptId = [string]$proposal.decisionReceipt
  if ([string]::IsNullOrWhiteSpace($decisionReceiptId)) {
    Add-Issue $issues "$pSubject must declare a decisionReceipt recording the decision before implementation."
  }
}

# Receipts: completeness, vocabulary, append-only, no live-write markers, cross-slice uniqueness.
$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -lt 1) {
  Add-Issue $issues "Platform evaluation slice must include at least one decision receipt."
}
$sliceReceiptIds = @{}
$seenIdempotencyKeys = @{}
$receiptTimestamps = @{}
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
    }
    else { $sliceReceiptIds[$receiptId] = $true }
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
  $occurredTs = Test-IsoTimestamp -Issues $issues -Record $receipt -Field "com_occurred_at" -Subject $subject
  if ($null -ne $occurredTs -and -not [string]::IsNullOrWhiteSpace($receiptId)) {
    $receiptTimestamps[$receiptId] = $occurredTs
  }

  $idempotencyKey = [string]$receipt.com_idempotency_key
  if (-not [string]::IsNullOrWhiteSpace($idempotencyKey)) {
    if ($seenIdempotencyKeys.ContainsKey($idempotencyKey)) {
      Add-Issue $issues "$subject reuses an idempotency key already used in this slice: $idempotencyKey."
    }
    else { $seenIdempotencyKeys[$idempotencyKey] = $true }
  }

  if ($receipt.com_append_only_locked -isnot [bool] -or -not $receipt.com_append_only_locked) {
    Add-Issue $issues "$subject com_append_only_locked must be strict boolean true."
  }
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject

  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; platform evaluation receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; platform evaluation receipts are local contract evidence only."
      }
    }
  }
}

# Each custom proposal's decisionReceipt must resolve to a receipt minted in this slice.
foreach ($proposal in $proposals) {
  $pSubject = "Custom proposal $($proposal.proposalId)"
  $decisionReceiptId = [string]$proposal.decisionReceipt
  if (-not [string]::IsNullOrWhiteSpace($decisionReceiptId) -and -not $sliceReceiptIds.ContainsKey($decisionReceiptId)) {
    Add-Issue $issues "$pSubject decisionReceipt must resolve to a receipt minted in this slice, found: $decisionReceiptId."
  }
}

# Microsoft-native evaluated before custom substrate (story goal FR26-28): a self-asserted
# guard is not proof. Derive, from receipts alone, which receipts are evaluation-review
# receipts (their com_evidence_refs references a minted capabilityEvaluationId) and assert
# that every custom-substrate proposal decision receipt was recorded at or after EVERY
# evaluation-review receipt. With no evaluation-review receipts the check would silently
# no-op, so a proposal-bearing slice must produce at least one evaluation-review receipt.
$proposalDecisionReceiptIds = @{}
foreach ($proposal in $proposals) {
  $dr = [string]$proposal.decisionReceipt
  if (-not [string]::IsNullOrWhiteSpace($dr)) { $proposalDecisionReceiptIds[$dr] = $true }
}
$evalReviewTimestamps = [System.Collections.Generic.List[datetimeoffset]]::new()
foreach ($receipt in $receipts) {
  $receiptId = [string]$receipt.com_receipt_id
  # A custom-substrate proposal decision receipt is the "custom substrate" event itself,
  # not a Microsoft-native evaluation review, even though it may cite an evaluation row
  # in its evidence_refs. Exclude it so the eval-review set is not poisoned by the very
  # receipt the ordering rule compares against.
  if ($proposalDecisionReceiptIds.ContainsKey($receiptId)) { continue }
  $evrefs = [string]$receipt.com_evidence_refs
  if ([string]::IsNullOrWhiteSpace($evrefs)) { continue }
  $matchesEval = $false
  foreach ($evaluation in $evaluations) {
    $eid = [string]$evaluation.capabilityEvaluationId
    if (-not [string]::IsNullOrWhiteSpace($eid) -and $evrefs -match [regex]::Escape($eid)) {
      $matchesEval = $true
      break
    }
  }
  if ($matchesEval -and $receiptTimestamps.ContainsKey($receiptId)) {
    $evalReviewTimestamps.Add($receiptTimestamps[$receiptId]) | Out-Null
  }
}
if ($proposals.Count -gt 0) {
  if ($evalReviewTimestamps.Count -eq 0) {
    Add-Issue $issues "Microsoft-native evaluated before custom substrate is unproven: no evaluation-review receipt (a receipt whose com_evidence_refs references a minted capabilityEvaluationId) was recorded before the custom proposal decision."
  }
  foreach ($proposal in $proposals) {
    $proposalKey = [string]$proposal.proposalId
    $dr = [string]$proposal.decisionReceipt
    if (-not $receiptTimestamps.ContainsKey($dr)) { continue }
    $proposalTs = $receiptTimestamps[$dr]
    foreach ($evalTs in $evalReviewTimestamps) {
      if ($proposalTs -lt $evalTs) {
        Add-Issue $issues "Custom proposal $proposalKey decision receipt $dr was recorded at $($proposalTs.ToString('o')) before Microsoft-native evaluation review receipt at $($evalTs.ToString('o')); Microsoft-native planes must be evaluated before custom substrate."
      }
    }
  }
}

# Decisions recorded before any implementation: no implementation-marker fields may appear anywhere in the slice.
$allPropertyNames = [System.Collections.Generic.List[string]]::new()
Collect-PropertyNames -Node $platform -Accumulator $allPropertyNames
$forbiddenImplementationMarkers = @(
  "implementationArtifact",
  "builtComponent",
  "deployedService",
  "implementationStartedAt",
  "codeCommitted",
  "prMerged",
  "buildUrl",
  "releaseName",
  "deployedAt"
)
foreach ($marker in $forbiddenImplementationMarkers) {
  if ($allPropertyNames -contains $marker) {
    Add-Issue $issues "Slice must not contain an implementation-marker field '$marker'; decisions must be recorded before implementation and no implementation artifacts are referenced."
  }
}

# Deferred writes: every would-be live write appears only as a receipt-gated deferred entry.
$deferredWrites = @($run.deferredWrites | Where-Object { $null -ne $_ })
if ($deferredWrites.Count -eq 0) {
  Add-Issue $issues "Platform evaluation slice must declare at least one deferred write entry; live mutations must stay receipt-gated."
}
foreach ($deferred in $deferredWrites) {
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "record")) {
    Add-Issue $issues "Deferred write entry must name its record."
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred write entry must carry a non-empty deferredUpdate."
  }
  elseif ([string]$deferred.deferredUpdate -notmatch "receipt") {
    Add-Issue $issues "Deferred write entry for $($deferred.record) must state that the live mutation is receipt-gated."
  }
}

# Cross-slice ID harvest: LIVE scan of every *-slice.json in $PSScriptRoot (excluding this slice)
# plus the demo-evidence inventory. MINTED ids (minted in this slice) must be unique across ALL slices;
# REFERENCED ids (any CWI/CR/CSR id appearing in this slice that is not minted here) must resolve to a sibling.
$sliceFileName = Split-Path -Leaf $PlatformSlicePath
$allSiblingSlicePaths = @(
  Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*-slice.json" -File |
    Where-Object { $_.Name -ne $sliceFileName } |
    ForEach-Object { $_.FullName }
)
if ($allSiblingSlicePaths.Count -eq 0) {
  Add-Issue $issues "No sibling slice files (*-slice.json) found in $PSScriptRoot; cross-slice collision checks would silently no-op."
}
$siblingSlices = @()
foreach ($siblingPath in $allSiblingSlicePaths) {
  $siblingSlices += Read-JsonInput -Path $siblingPath
}
$priorCwiIds = [System.Collections.Generic.HashSet[string]]::new()
$priorCrIds = [System.Collections.Generic.HashSet[string]]::new()
$priorCsrIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($slice in $siblingSlices) {
  foreach ($id in (Collect-Ids -Node $slice -Pattern "CWI-[A-Za-z0-9-]+")) { [void]$priorCwiIds.Add($id) }
  foreach ($id in (Collect-Ids -Node $slice -Pattern "CR-[A-Za-z0-9-]+")) { [void]$priorCrIds.Add($id) }
  foreach ($id in (Collect-Ids -Node $slice -Pattern "CSR-[A-Za-z0-9-]+")) { [void]$priorCsrIds.Add($id) }
}
foreach ($id in @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) { [void]$priorCrIds.Add([string]$id) }
foreach ($id in @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) { [void]$priorCwiIds.Add([string]$id) }

# Minted ids in this slice (CR receipts minted here).
$mintedCrIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($receiptId in @($sliceReceiptIds.Keys)) { [void]$mintedCrIds.Add($receiptId) }

# All CWI/CR/CSR ids appearing anywhere in this slice's text (minted + referenced).
$sliceTextCwi = Collect-Ids -Node $platform -Pattern "CWI-[A-Za-z0-9-]+"
$sliceTextCr = Collect-Ids -Node $platform -Pattern "CR-[A-Za-z0-9-]+"
$sliceTextCsr = Collect-Ids -Node $platform -Pattern "CSR-[A-Za-z0-9-]+"

# MINTED CR ids must be unique across ALL slices (no collision with sibling/demo ids).
foreach ($mintedCr in $mintedCrIds) {
  if ($priorCrIds -contains $mintedCr) {
    Add-Issue $issues "Minted receipt id $mintedCr collides with an id already present in a sibling slice or demo evidence; new CR-LOCAL-* ids must be unique across ALL slices."
  }
}

# REFERENCED ids: any CWI/CR/CSR id in this slice that is NOT minted here must resolve to a sibling slice.
foreach ($cr in @($sliceTextCr | Sort-Object -Unique)) {
  if (-not $mintedCrIds.Contains($cr)) {
    if ($priorCrIds -notcontains $cr) {
      Add-Issue $issues "Referenced receipt id $cr does not resolve to any sibling slice or demo evidence; referenced ids must resolve."
    }
  }
}
foreach ($cwi in @($sliceTextCwi | Sort-Object -Unique)) {
  if ($priorCwiIds -notcontains $cwi) {
    Add-Issue $issues "Referenced work item id $cwi does not resolve to any sibling slice or demo evidence; referenced ids must resolve."
  }
}
foreach ($csr in @($sliceTextCsr | Sort-Object -Unique)) {
  if ($priorCsrIds -notcontains $csr) {
    Add-Issue $issues "Referenced source record id $csr does not resolve to any sibling slice or demo evidence; referenced ids must resolve."
  }
}

# Within-slice uniqueness for the PE-LOCAL-* / CSP-LOCAL-* namespaces minted by this story.
# Minting locations are structural (capabilityEvaluationId, candidateRows.rowId, proposalId); textual
# occurrences elsewhere (addressesGapInRow, decisionReceipt, com_evidence_refs) are references, not mints,
# so uniqueness is enforced only over the minting fields.
$mintedPeIds = [System.Collections.Generic.List[string]]::new()
foreach ($evaluation in $evaluations) {
  if (Test-HasNonEmptyField -Record $evaluation -Field "capabilityEvaluationId") {
    $mintedPeIds.Add([string]$evaluation.capabilityEvaluationId) | Out-Null
  }
  foreach ($row in @($evaluation.candidateRows | Where-Object { $null -ne $_ })) {
    if (Test-HasNonEmptyField -Record $row -Field "rowId") {
      $mintedPeIds.Add([string]$row.rowId) | Out-Null
    }
  }
}
$seenPe = @{}
foreach ($pe in $mintedPeIds) {
  if ($seenPe.ContainsKey($pe)) { Add-Issue $issues "Duplicate minted PE-LOCAL-* id in slice: $pe." }
  else { $seenPe[$pe] = $true }
}
$mintedCspIds = [System.Collections.Generic.List[string]]::new()
foreach ($proposal in $proposals) {
  if (Test-HasNonEmptyField -Record $proposal -Field "proposalId") {
    $mintedCspIds.Add([string]$proposal.proposalId) | Out-Null
  }
}
$seenCsp = @{}
foreach ($csp in $mintedCspIds) {
  if ($seenCsp.ContainsKey($csp)) { Add-Issue $issues "Duplicate minted CSP-LOCAL-* id in slice: $csp." }
  else { $seenCsp[$csp] = $true }
}

# acceptanceMapping: every story AC mapped to non-empty local evidence + tenantEvidenceRequired.
foreach ($criterion in @(1, 2)) {
  $mapping = @($platform.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
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
  Write-Host "Platform evaluation slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Platform evaluation slice validation succeeded."
Write-Host "Evaluations: $($evaluations.Count)"
Write-Host "Candidate rows: $($allRowIds.Count)"
Write-Host "Custom proposals: $($proposals.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "PLATFORM_EVALUATION_SLICE_VALIDATE_OK"
