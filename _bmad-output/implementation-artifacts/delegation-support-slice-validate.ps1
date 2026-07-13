param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$DelegationSlicePath = "$PSScriptRoot\delegation-support-slice.json",
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
    Write-Host "Delegation support slice validation failed:"
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

foreach ($path in @($ManifestPath, $DelegationSlicePath, $ManualSlicePath, $OutlookSlicePath, $Story13ExtractionPath, $Story14ExtractionPath, $DriftSlicePath, $DemoEvidencePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required delegation support validation input not found: $path"
  }
}

$manifest = Read-JsonInput -Path $ManifestPath
$delegation = Read-JsonInput -Path $DelegationSlicePath
$manualSlice = Read-JsonInput -Path $ManualSlicePath
$outlookSlice = Read-JsonInput -Path $OutlookSlicePath
$story13Extraction = Read-JsonInput -Path $Story13ExtractionPath
$story14Extraction = Read-JsonInput -Path $Story14ExtractionPath
$driftSlice = Read-JsonInput -Path $DriftSlicePath
$demoEvidence = Read-JsonInput -Path $DemoEvidencePath
$issues = [System.Collections.Generic.List[string]]::new()

$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$workItemTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemtype"
$workItemStateGroups = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemstategroup"
$riskClasses = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_riskclass"
$evidenceRoles = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilreceiptsource" -ColumnName "com_evidence_role"
$workItemUrgency = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_councilworkitem" -ColumnName "com_urgency"
$validStances = @("delegate", "hold", "handle")

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_workitemtype"; Values = $workItemTypes },
    @{ Name = "com_workitemstategroup"; Values = $workItemStateGroups },
    @{ Name = "com_riskclass"; Values = $riskClasses },
    @{ Name = "com_councilreceiptsource.com_evidence_role"; Values = $evidenceRoles },
    @{ Name = "com_councilworkitem.com_urgency"; Values = $workItemUrgency }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

foreach ($verb in @("approved", "held")) {
  if ($receiptVerbs -notcontains $verb) {
    Add-Issue $issues "Manifest com_receiptverb is missing the delegation-decision verb: $verb."
  }
}
foreach ($result in @("accepted", "rejected")) {
  if ($receiptResults -notcontains $result) {
    Add-Issue $issues "Manifest com_receiptresult is missing the delegation-decision result: $result."
  }
}
if ($evidenceRoles -notcontains "approval") {
  Add-Issue $issues "Manifest com_councilreceiptsource.com_evidence_role is missing: approval."
}

# Cross-slice ID collection: the story hard rule requires new CWI-LOCAL-* / CR-LOCAL-* / CSR-* ids to be
# unique across ALL slices (not just 1-1..1-5). Harvest CWI/CR/CSR ids from every *-slice.json in this
# directory (excluding the slice under validation) plus the structured demo-evidence inventory. The
# named sibling slices below are also parsed structurally for runId / source-record binding checks.
$delegationSliceFileName = Split-Path -Leaf $DelegationSlicePath
$allSiblingSlicePaths = @(
  Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*-slice.json" -File |
    Where-Object { $_.Name -ne $delegationSliceFileName } |
    ForEach-Object { $_.FullName }
)
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
foreach ($id in @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
  [void]$priorCrIds.Add([string]$id)
}
foreach ($id in @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
  [void]$priorCwiIds.Add([string]$id)
}
$priorRunIds = @(
  [string]$story13Extraction.extractionRun.runId,
  [string]$story14Extraction.extractionRun.runId,
  [string]$driftSlice.driftRun.runId
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

if ($allSiblingSlicePaths.Count -eq 0) {
  Add-Issue $issues "No sibling slice files (*-slice.json) found in $PSScriptRoot; cross-slice collision checks would silently no-op."
}
if ($priorCsrIds.Count -eq 0) {
  Add-Issue $issues "No Source Record IDs could be harvested from sibling slices; cross-slice source-reference checks would silently no-op."
}
if ($priorCwiIds.Count -eq 0) {
  Add-Issue $issues "No Work Item IDs could be harvested from sibling slices; cross-slice collision and source-reference checks would silently no-op."
}
if ($priorCrIds.Count -eq 0) {
  Add-Issue $issues "No Receipt IDs could be harvested from sibling slices; cross-slice collision checks would silently no-op."
}

# Slice header.
if ($delegation.storyKey -ne "3-2-build-delegation-decision-support-packages") {
  Add-Issue $issues "Delegation slice storyKey must be 3-2-build-delegation-decision-support-packages."
}
if ([string]$delegation.status -notmatch "^local-contract") {
  Add-Issue $issues "Delegation slice status must declare local contract evidence, found: $($delegation.status)."
}

# Guards.
$requiredGuards = @(
  "noTenantWrites",
  "noOutboundAction",
  "noApprovalExecution",
  "requiresExplicitHumanApprovalForExecution",
  "delegationDecisionsAreReceiptBacked",
  "nonDelegableExceptionsPreserveExceptionReason",
  "sourceReferencesResolveToSiblingSlices",
  "receiptsAreLocalContractEvidenceOnly",
  "receiptsAreAppendOnly",
  "noStateChangeExecutionInThisSlice"
)
foreach ($guard in $requiredGuards) {
  if (-not ($delegation.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Delegation slice must declare guard: $guard."
  }
}
foreach ($guardProperty in @($delegation.guards.PSObject.Properties)) {
  if ($guardProperty.Value -isnot [bool] -or -not $guardProperty.Value) {
    Add-Issue $issues "Delegation guard must be boolean true: $($guardProperty.Name)."
  }
}

$run = $delegation.delegationSupportRun
if ($null -eq $run) {
  Add-Issue $issues "Delegation slice must carry a delegationSupportRun block."
  Write-Host "Delegation support slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

# Run header.
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Delegation run must declare a runId."
}
elseif ($priorRunIds -contains [string]$run.runId) {
  Add-Issue $issues "Delegation run must use a new local runId, not a sibling slice runId: $($run.runId)."
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Delegation run semanticContractVersion must be 2026-07-07."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Delegation run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Delegation run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "proposed-work-item-extraction-slice.json", "zero-multi-item-extraction-slice.json")) {
  if (@($run.inputSourceRecordsFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Delegation run must reference $inputSlice as an input."
  }
}

# Decision policy.
$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Delegation run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("delegationCandidatesArePackagedWithStanceAndRationale", "nonDelegableExceptionsPreserveExceptionReason", "delegateHoldHandleDecisionsAreReceiptBacked", "decisionAuthorityBasisIsHumanDoug", "beforeAfterStatesFormManifestValidTransitions", "receiptsAreLocalContractEvidenceOnly", "liveWorkItemMutationReceiptGatedToEpic2")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Delegation run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if ($policyProperty.Value -isnot [bool] -or -not $policyProperty.Value) {
      Add-Issue $issues "Delegation run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# Delegation support packages.
$packageRequiredFields = @(
  "packageId",
  "delegable",
  "candidateWorkItem",
  "suggestedOwner",
  "rationale",
  "confidence",
  "recommendedStance",
  "urgency",
  "sourceReferences",
  "risks"
)

$packages = @($run.delegationPackages | Where-Object { $null -ne $_ })
if ($packages.Count -ne 2) {
  Add-Issue $issues "Delegation slice must include exactly two delegation support packages (one delegable, one non-delegable), found $($packages.Count)."
}

$seenPackageIds = @{}
$seenCandidateIds = @{}
$delegableCount = 0
$nonDelegableCount = 0
foreach ($package in $packages) {
  $packageId = [string]$package.packageId
  $subject = "Delegation package $packageId"

  foreach ($field in $packageRequiredFields) {
    if (-not (Test-HasNonEmptyField -Record $package -Field $field)) {
      Add-Issue $issues "$subject missing required field: $field."
    }
  }

  if ([string]::IsNullOrWhiteSpace($packageId)) {
    Add-Issue $issues "Delegation package must declare a packageId."
  }
  else {
    if ($packageId -notmatch "^DSP-LOCAL-") {
      Add-Issue $issues "$subject packageId must use a story-local DSP-LOCAL-* identity, found: $packageId."
    }
    if ($seenPackageIds.ContainsKey($packageId)) {
      Add-Issue $issues "Duplicate packageId in slice: $packageId."
    }
    else {
      $seenPackageIds[$packageId] = $true
    }
  }

  # delegable / nonDelegable must be strict, consistent booleans.
  if ($package.delegable -isnot [bool]) {
    Add-Issue $issues "$subject delegable must be a strict boolean, found: $($package.delegable)."
  }
  elseif ($package.delegable) {
    $delegableCount++
  }
  if ($package.PSObject.Properties.Name -contains "nonDelegable") {
    if ($package.nonDelegable -isnot [bool]) {
      Add-Issue $issues "$subject nonDelegable must be a strict boolean, found: $($package.nonDelegable)."
    }
    elseif ($package.nonDelegable -eq $package.delegable) {
      Add-Issue $issues "$subject nonDelegable must be the boolean inverse of delegable; found delegable=$($package.delegable), nonDelegable=$($package.nonDelegable)."
    }
  }

  # confidence TryParse in [0,1].
  Test-ConfidenceInRange -Issues $issues -Record $package -Field "confidence" -Subject $subject | Out-Null

  # stance vocabulary.
  $stance = [string]$package.recommendedStance
  if ($validStances -notcontains $stance) {
    Add-Issue $issues "$subject recommendedStance must be one of (delegate|hold|handle), found: $stance."
  }

  # Stance polarity: a non-delegable package must NOT recommend 'delegate' (contradiction: you cannot
  # delegate a candidate packaged as non-delegable). A delegable package may recommend any stance.
  $isNonDelegable = ($package.PSObject.Properties.Name -contains "nonDelegable" -and $package.nonDelegable -is [bool] -and $package.nonDelegable)
  if ($isNonDelegable -and $stance -eq "delegate") {
    Add-Issue $issues "$subject is non-delegable and must NOT recommend stance 'delegate'; use hold or handle."
  }

  # urgency vocabulary.
  if ($workItemUrgency -notcontains [string]$package.urgency) {
    Add-Issue $issues "$subject urgency must be in manifest com_urgency vocabulary, found: $($package.urgency)."
  }

  # candidateWorkItem must resolve to a sibling-slice CWI id.
  $candidateId = [string]$package.candidateWorkItem
  if ([string]::IsNullOrWhiteSpace($candidateId)) {
    Add-Issue $issues "$subject must name a non-empty candidateWorkItem."
  }
  else {
    if (-not $priorCwiIds.Contains($candidateId)) {
      Add-Issue $issues "$subject candidateWorkItem must resolve to an existing CWI id from a sibling slice, found: $candidateId."
    }
    if ($seenCandidateIds.ContainsKey($candidateId)) {
      Add-Issue $issues "$subject candidateWorkItem duplicates another package's candidate ($candidateId); the two packages must target distinct delegation candidates."
    }
    else {
      $seenCandidateIds[$candidateId] = $true
    }
  }

  # sourceReferences resolve to sibling-slice CSR/CWI ids and must include the candidate + its backing CSR.
  $refs = @()
  if ($null -ne $package.sourceReferences) {
    $refs = @($package.sourceReferences | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
  }
  if ($refs.Count -lt 1) {
    Add-Issue $issues "$subject sourceReferences must list at least one CSR/CWI id resolving to a sibling slice."
  }
  $seenRefInPackage = @{}
  foreach ($ref in $refs) {
    if ($seenRefInPackage.ContainsKey($ref)) {
      Add-Issue $issues "$subject sourceReferences must not repeat the same id: $ref."
    }
    else {
      $seenRefInPackage[$ref] = $true
    }
    if ($priorCsrIds.Contains($ref)) { continue }
    if ($priorCwiIds.Contains($ref)) { continue }
    Add-Issue $issues "$subject sourceReferences entry '$ref' must resolve to an existing CSR or CWI id from a sibling slice."
  }
  if (-not [string]::IsNullOrWhiteSpace($candidateId) -and ($refs -notcontains $candidateId)) {
    Add-Issue $issues "$subject sourceReferences must include the candidate Work Item id $candidateId."
  }

  # Non-delegable package must preserve an exception reason; delegable package must NOT carry one.
  if ($package.PSObject.Properties.Name -contains "nonDelegable" -and $package.nonDelegable -is [bool] -and $package.nonDelegable) {
    $nonDelegableCount++
    if (-not (Test-HasNonEmptyField -Record $package -Field "exceptionReason")) {
      Add-Issue $issues "$subject is non-delegable and must preserve a non-empty exceptionReason."
    }
    else {
      $reason = [string]$package.exceptionReason
      # Content gate: the reason must declare non-delegability AND name the governance judgment it
      # protects (Council judgment gate / human judgment / Doug / bypass). A bare "non-delegable"
      # token with no governance binding is not evidence.
      if ($reason -notmatch "non-delegable|non_delegable") {
        Add-Issue $issues "$subject exceptionReason must explicitly state non-delegability (non-delegable / non_delegable), found: $reason."
      }
      if ($reason -notmatch "Council judgment gate|human judgment|Doug|bypass") {
        Add-Issue $issues "$subject exceptionReason must name the governance judgment it protects (Council judgment gate / human judgment / Doug / bypass), found: $reason."
      }
    }
  }
  elseif ($package.PSObject.Properties.Name -contains "delegable" -and $package.delegable -is [bool] -and $package.delegable) {
    if ($package.PSObject.Properties.Name -contains "exceptionReason" -and -not [string]::IsNullOrWhiteSpace([string]$package.exceptionReason)) {
      Add-Issue $issues "$subject is delegable and must NOT carry a nonDelegable exceptionReason; the exception belongs only to the non-delegable package."
    }
  }
}

if ($delegableCount -ne 1) {
  Add-Issue $issues "Delegation slice must include exactly one delegable package (delegable=true), found $delegableCount."
}
if ($nonDelegableCount -ne 1) {
  Add-Issue $issues "Delegation slice must include exactly one non-delegable package (nonDelegable=true with a preserved exceptionReason), found $nonDelegableCount."
}

# Decisions (one approval, one rejection).
$decisions = @($run.decisions | Where-Object { $null -ne $_ })
if ($decisions.Count -ne 2) {
  Add-Issue $issues "Delegation slice must include exactly two decisions (one approve, one reject), found $($decisions.Count)."
}

$decisionRequiredFields = @(
  "decisionId",
  "decisionType",
  "package",
  "workItem",
  "decisionReceipt",
  "decisionRationale",
  "authorityBasis",
  "actorType",
  "actorId",
  "beforeState",
  "afterState",
  "result"
)

$seenDecisionIds = @{}
$seenDecisionTypes = @{}
$seenDecisionWorkItems = @{}
$decisionByReceipt = @{}
foreach ($decision in $decisions) {
  $decisionId = [string]$decision.decisionId
  $subject = "Decision $decisionId"

  foreach ($field in $decisionRequiredFields) {
    if (-not (Test-HasNonEmptyField -Record $decision -Field $field)) {
      Add-Issue $issues "$subject missing required field: $field."
    }
  }

  if ([string]::IsNullOrWhiteSpace($decisionId)) {
    Add-Issue $issues "Decision must declare a decisionId."
  }
  else {
    if ($seenDecisionIds.ContainsKey($decisionId)) {
      Add-Issue $issues "Duplicate decisionId in slice: $decisionId."
    }
    else {
      $seenDecisionIds[$decisionId] = $true
    }
  }

  $decisionType = [string]$decision.decisionType
  if (@("approve", "reject") -notcontains $decisionType) {
    Add-Issue $issues "$subject decisionType must be approve or reject, found: $decisionType."
  }
  else {
    if ($seenDecisionTypes.ContainsKey($decisionType)) {
      Add-Issue $issues "$subject duplicates decisionType $decisionType; the slice must include one approve and one reject."
    }
    else {
      $seenDecisionTypes[$decisionType] = $true
    }
  }

  # decision.package must be a real package in this slice; resolve it once for polarity + exception binding.
  $decisionPackageId = [string]$decision.package
  $targetPackage = $null
  if ([string]::IsNullOrWhiteSpace($decisionPackageId) -or -not $seenPackageIds.ContainsKey($decisionPackageId)) {
    Add-Issue $issues "$subject package must reference a delegation package in this slice, found: $decisionPackageId."
  }
  else {
    $targetPackage = @($packages | Where-Object { [string]$_.packageId -eq $decisionPackageId }) | Select-Object -First 1
  }

  # decision.workItem must be the package's candidateWorkItem.
  $decisionWorkItem = [string]$decision.workItem
  if ($null -ne $targetPackage) {
    $targetCandidate = [string]$targetPackage.candidateWorkItem
    if ($decisionWorkItem -ne $targetCandidate) {
      Add-Issue $issues "$subject workItem ($decisionWorkItem) must equal its package's candidateWorkItem ($targetCandidate)."
    }
    elseif (-not $priorCwiIds.Contains($decisionWorkItem)) {
      Add-Issue $issues "$subject workItem must resolve to an existing CWI id from a sibling slice, found: $decisionWorkItem."
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($decisionWorkItem)) {
    if ($seenDecisionWorkItems.ContainsKey($decisionWorkItem)) {
      Add-Issue $issues "$subject workItem duplicates another decision's workItem ($decisionWorkItem); the two decisions must target distinct candidates."
    }
    else {
      $seenDecisionWorkItems[$decisionWorkItem] = $true
    }
  }

  # Authority basis must be human/Doug.
  if ([string]$decision.actorType -ne "human") {
    Add-Issue $issues "$subject actorType must be human for a delegation decision, found: $($decision.actorType)."
  }
  if ([string]$decision.actorId -ne "Doug") {
    Add-Issue $issues "$subject actorId must be Doug for a delegation decision, found: $($decision.actorId)."
  }
  if (-not (Test-HasNonEmptyField -Record $decision -Field "authorityBasis")) {
    Add-Issue $issues "$subject must carry a non-empty authorityBasis naming the human/Doug authority."
  }
  elseif ([string]$decision.authorityBasis -notmatch "Doug") {
    Add-Issue $issues "$subject authorityBasis must name Doug as the human authority, found: $($decision.authorityBasis)."
  }

  # before/after states must be manifest state-group values and form a valid transition (before != after).
  $beforeState = [string]$decision.beforeState
  $afterState = [string]$decision.afterState
  foreach ($stateField in @("beforeState", "afterState")) {
    if (-not (Test-HasNonEmptyField -Record $decision -Field $stateField)) {
      Add-Issue $issues "$subject must carry a non-empty ${stateField}."
    }
    elseif ($workItemStateGroups -notcontains [string]$decision.$stateField) {
      Add-Issue $issues "$subject ${stateField} '$([string]$decision.$stateField)' is not in manifest com_workitemstategroup vocabulary."
    }
  }
  if ($workItemStateGroups -contains $beforeState -and $workItemStateGroups -contains $afterState) {
    if ($beforeState -eq $afterState) {
      Add-Issue $issues "$subject beforeState and afterState must differ to form a transition, found $beforeState -> $afterState."
    }
  }

  # Decision polarity must bind to package polarity (HIGH): an approve must target the delegable
  # package; a reject must target the non-delegable package. This closes the hole where a mutated
  # slice could approve the non-delegable package and reject the delegable one while still passing
  # the typed transition contract.
  if ($null -ne $targetPackage) {
    $pkgDelegable = ($targetPackage.delegable -is [bool] -and $targetPackage.delegable)
    $pkgNonDelegable = ($targetPackage.PSObject.Properties.Name -contains "nonDelegable" -and $targetPackage.nonDelegable -is [bool] -and $targetPackage.nonDelegable)
    if ($decisionType -eq "approve" -and -not $pkgDelegable) {
      Add-Issue $issues "$subject (approve) must target the delegable package (delegable=true), found package $decisionPackageId with delegable=$($targetPackage.delegable)."
    }
    if ($decisionType -eq "approve" -and $pkgNonDelegable) {
      Add-Issue $issues "$subject (approve) must NOT target a non-delegable package, found package $decisionPackageId with nonDelegable=$($targetPackage.nonDelegable)."
    }
    if ($decisionType -eq "reject" -and -not $pkgNonDelegable) {
      Add-Issue $issues "$subject (reject) must target the non-delegable package (nonDelegable=true), found package $decisionPackageId with nonDelegable=$($targetPackage.nonDelegable)."
    }
    if ($decisionType -eq "reject" -and $pkgDelegable) {
      Add-Issue $issues "$subject (reject) must NOT target a delegable package, found package $decisionPackageId with delegable=$($targetPackage.delegable)."
    }
  }

  # decisionType-specific transition contract: approve => proposed->approved; reject => proposed->held.
  if ($decisionType -eq "approve") {
    if ($beforeState -ne "proposed") {
      Add-Issue $issues "$subject (approve) beforeState must be proposed, found: $beforeState."
    }
    if ($afterState -ne "approved") {
      Add-Issue $issues "$subject (approve) afterState must be approved, found: $afterState."
    }
    if ([string]$decision.result -ne "accepted") {
      Add-Issue $issues "$subject (approve) result must be accepted, found: $($decision.result)."
    }
  }
  elseif ($decisionType -eq "reject") {
    if ($beforeState -ne "proposed") {
      Add-Issue $issues "$subject (reject) beforeState must be proposed, found: $beforeState."
    }
    if ($afterState -ne "held") {
      Add-Issue $issues "$subject (reject) afterState must be held (held for human handling; non-delegable), found: $afterState."
    }
    if ([string]$decision.result -ne "rejected") {
      Add-Issue $issues "$subject (reject) result must be rejected, found: $($decision.result)."
    }
    # The rejection decision must preserve the non-delegable exception reason verbatim from its
    # package — UNCONDITIONALLY (HIGH). The reject target is bound above to a non-delegable package,
    # which the package loop already proved carries a non-empty exceptionReason. Do not gate this
    # check on the package already having a reason; that made the whole block skippable.
    if ($null -ne $targetPackage) {
      if (-not (Test-HasNonEmptyField -Record $targetPackage -Field "exceptionReason")) {
        Add-Issue $issues "$subject (reject) target package $decisionPackageId must carry a non-empty exceptionReason for the rejection to preserve."
      }
      else {
        $packageReason = [string]$targetPackage.exceptionReason
        if (-not (Test-HasNonEmptyField -Record $decision -Field "nonDelegableExceptionReason")) {
          Add-Issue $issues "$subject (reject) must preserve the non-delegable exceptionReason from package $decisionPackageId (missing nonDelegableExceptionReason)."
        }
        elseif ([string]$decision.nonDelegableExceptionReason -ne $packageReason) {
          Add-Issue $issues "$subject (reject) nonDelegableExceptionReason must be preserved verbatim from package $decisionPackageId; it differs from the package's exceptionReason."
        }
      }
    }
  }

  # Record the receipt binding for cross-check.
  $decisionReceiptId = [string]$decision.decisionReceipt
  if (-not [string]::IsNullOrWhiteSpace($decisionReceiptId)) {
    $decisionByReceipt[$decisionReceiptId] = $decision
  }
}

if (-not $seenDecisionTypes.ContainsKey("approve")) {
  Add-Issue $issues "Delegation slice must include one approval decision (decisionType approve)."
}
if (-not $seenDecisionTypes.ContainsKey("reject")) {
  Add-Issue $issues "Delegation slice must include one rejection decision (decisionType reject)."
}

# Receipts.
$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique

$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -ne 2) {
  Add-Issue $issues "Delegation slice must include exactly two decision receipts (one approval, one rejection), found $($receipts.Count)."
}

$sliceReceiptIds = @{}
$sliceReceiptsById = @{}
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
    if ($receiptId -notmatch "^CR-LOCAL-") {
      Add-Issue $issues "$subject must use a story-local CR-LOCAL-* identity (hard rule: new CR ids are CR-LOCAL-*), found: $receiptId."
    }
    if ($sliceReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "Duplicate receipt ID in slice: $receiptId."
    }
    else {
      $sliceReceiptIds[$receiptId] = $true
      $sliceReceiptsById[$receiptId] = $receipt
    }
    if ($priorCrIds.Contains($receiptId)) {
      Add-Issue $issues "$subject collides with an existing CR id from a sibling slice or demo evidence."
    }
  }

  if ($receiptVerbs -notcontains [string]$receipt.com_verb) {
    Add-Issue $issues "$subject verb is not in manifest com_receiptverb vocabulary: $($receipt.com_verb)."
  }
  if ($actorTypes -notcontains [string]$receipt.com_actor_type) {
    Add-Issue $issues "$subject actor type is not in manifest com_actortype vocabulary: $($receipt.com_actor_type)."
  }
  # F1: decision receipts (this story's deliverable) must be human/Doug-actor pinned; the
  # delegation decision authority basis is human/Doug by FR13.
  if ([string]$receipt.com_actor_type -ne "human") {
    Add-Issue $issues "$subject actor type must be human for a delegation decision receipt, found: $($receipt.com_actor_type)."
  }
  if ([string]$receipt.com_actor_id -ne "Doug") {
    Add-Issue $issues "$subject actor id must be Doug for a delegation decision receipt, found: $($receipt.com_actor_id)."
  }
  if ($receiptResults -notcontains [string]$receipt.com_result) {
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
  }

  if ($receipt.com_append_only_locked -isnot [bool] -or -not $receipt.com_append_only_locked) {
    Add-Issue $issues "$subject com_append_only_locked must be strict boolean true (append-only)."
  }
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject | Out-Null

  # before/after states must be manifest state-group values (text-typed column; free text outside vocab is not evidence).
  foreach ($stateField in @("com_before_state", "com_after_state")) {
    if (Test-HasNonEmptyField -Record $receipt -Field $stateField) {
      $stateVal = [string]$receipt.$stateField
      if ($workItemStateGroups -notcontains $stateVal) {
        Add-Issue $issues "$subject $stateField '$stateVal' is not in manifest com_workitemstategroup vocabulary."
      }
    }
  }

  # No live-write marker fields anywhere on a receipt.
  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; delegation decision receipts are local contract evidence only."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write", "no_outbound_action")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; delegation decision receipts are local contract evidence only."
      }
    }
  }
}

# Bind decisions to receipts: every decision.decisionReceipt must exist and match the decision's transition contract.
foreach ($decision in $decisions) {
  $decisionId = [string]$decision.decisionId
  $decisionReceiptId = [string]$decision.decisionReceipt
  $subject = "Decision $decisionId"
  if ([string]::IsNullOrWhiteSpace($decisionReceiptId) -or -not $sliceReceiptIds.ContainsKey($decisionReceiptId)) {
    Add-Issue $issues "$subject references an unknown decision receipt: $decisionReceiptId."
    continue
  }
  $receipt = $sliceReceiptsById[$decisionReceiptId]
  # Verb/result must match the decision contract.
  $decisionType = [string]$decision.decisionType
  if ($decisionType -eq "approve") {
    if ([string]$receipt.com_verb -ne "approved") {
      Add-Issue $issues "$subject backing receipt $decisionReceiptId must use verb approved, found: $($receipt.com_verb)."
    }
    if ([string]$receipt.com_result -ne "accepted") {
      Add-Issue $issues "$subject backing receipt $decisionReceiptId must have result accepted, found: $($receipt.com_result)."
    }
  }
  elseif ($decisionType -eq "reject") {
    if ([string]$receipt.com_verb -ne "held") {
      Add-Issue $issues "$subject backing receipt $decisionReceiptId must use verb held (hold for human handling), found: $($receipt.com_verb)."
    }
    if ([string]$receipt.com_result -ne "rejected") {
      Add-Issue $issues "$subject backing receipt $decisionReceiptId must have result rejected, found: $($receipt.com_result)."
    }
  }
  # before/after states on the receipt must equal the decision's declared transition (proven scope == declared scope).
  if ([string]$receipt.com_before_state -ne [string]$decision.beforeState) {
    Add-Issue $issues "$subject backing receipt $decisionReceiptId com_before_state ($($receipt.com_before_state)) must equal the decision beforeState ($($decision.beforeState))."
  }
  if ([string]$receipt.com_after_state -ne [string]$decision.afterState) {
    Add-Issue $issues "$subject backing receipt $decisionReceiptId com_after_state ($($receipt.com_after_state)) must equal the decision afterState ($($decision.afterState))."
  }
  # The receipt must bind to the same Work Item the decision targets.
  $decisionWorkItem = [string]$decision.workItem
  if (-not [string]::IsNullOrWhiteSpace($decisionWorkItem)) {
    if ([string]::IsNullOrWhiteSpace([string]$receipt.com_work_item)) {
      Add-Issue $issues "$subject backing receipt $decisionReceiptId must carry com_work_item binding it to the decision's work item ($decisionWorkItem)."
    }
    elseif ([string]$receipt.com_work_item -ne $decisionWorkItem) {
      Add-Issue $issues "$subject backing receipt $decisionReceiptId com_work_item ($($receipt.com_work_item)) must equal the decision's workItem ($decisionWorkItem)."
    }
  }
  # The receipt decision_rationale must reference the decision (binding free text to this decision, not generic).
  if (Test-HasNonEmptyField -Record $receipt -Field "com_decision_rationale") {
    if ([string]$receipt.com_decision_rationale -notmatch [regex]::Escape($decisionWorkItem)) {
      Add-Issue $issues "$subject backing receipt $decisionReceiptId com_decision_rationale must name the decision's work item $decisionWorkItem so it is bound to this decision, not generic text."
    }
  }
}

# Receipt coverage is proven semantically above (one approve + one reject decision, each bound to a
# distinct receipt with matching verb/result/before/after/workItem). Hardcoded receipt-id literals
# would be a slice-game anti-pattern (epic-2 called this out); the decision↔receipt binding is the proof.

# Receipt source links.
$links = @($run.receiptSourceLinks | Where-Object { $null -ne $_ })
foreach ($link in $links) {
  $linkSubject = "Receipt source link $($link.com_name)"
  if (-not (Test-HasNonEmptyField -Record $link -Field "com_name")) {
    Add-Issue $issues "Receipt source link must carry a non-empty com_name."
  }
  $linkReceiptId = [string]$link.com_receipt
  if ([string]::IsNullOrWhiteSpace($linkReceiptId) -or -not $sliceReceiptIds.ContainsKey($linkReceiptId)) {
    Add-Issue $issues "$linkSubject references an unknown receipt: $linkReceiptId."
  }
  $linkSourceId = [string]$link.com_source_record
  if ([string]::IsNullOrWhiteSpace($linkSourceId) -or -not $priorCsrIds.Contains($linkSourceId)) {
    Add-Issue $issues "$linkSubject must bind an existing Source Record id from a sibling slice, found: $linkSourceId."
  }
  if ($evidenceRoles -notcontains [string]$link.com_evidence_role) {
    Add-Issue $issues "$linkSubject evidence role is not in manifest vocabulary: $($link.com_evidence_role)."
  }
  elseif ($sliceReceiptIds.ContainsKey($linkReceiptId)) {
    # F2: the approval evidence role is reserved for the approved-verb receipt; a
    # non-approved receipt (e.g. held) must NOT carry role approval. This mirrors the
    # hardened approval-boundaries contract so the role cannot silently drift.
    $linkReceiptVerb = [string]$sliceReceiptsById[$linkReceiptId].com_verb
    if ($linkReceiptVerb -eq "approved") {
      if ([string]$link.com_evidence_role -ne "approval") {
        Add-Issue $issues "$linkSubject is bound to an approved-verb receipt and must use the approval evidence role, found: $($link.com_evidence_role)."
      }
    }
    else {
      if ([string]$link.com_evidence_role -eq "approval") {
        Add-Issue $issues "$linkSubject is bound to a non-approved receipt (verb $linkReceiptVerb) and must NOT use the approval evidence role; use supporting instead."
      }
    }
  }
}
foreach ($receiptId in @($sliceReceiptIds.Keys)) {
  if (@($links | Where-Object { [string]$_.com_receipt -eq $receiptId }).Count -lt 1) {
    Add-Issue $issues "Receipt $receiptId must be bound to its source evidence by at least one receipt source link."
  }
}

# Deferred work item state changes — MANDATORY (HIGH). Story hard rule: every would-be live write
# appears as a deferred entry naming its receipt gate. Dropping the array or leaving it empty must
# fail. Mirror the epic-2 receipt-backed-state-changes pattern: at least one deferred entry per
# decided Work Item plus one ledger entry, each naming its receipt gate.
$workItemStateChangesDeferred = @($run.workItemStateChangesDeferred | Where-Object { $null -ne $_ })
if ($workItemStateChangesDeferred.Count -eq 0) {
  Add-Issue $issues "Delegation run must declare workItemStateChangesDeferred; every would-be live Work Item state change must appear as a deferred entry naming its receipt gate (cannot be dropped)."
}

$deferredWorkItemEntries = @{}
$deferredLedgerEntryCount = 0
foreach ($deferred in $workItemStateChangesDeferred) {
  $isWorkItemEntry = (Test-HasNonEmptyField -Record $deferred -Field "workItem")
  $isLedgerEntry = ((Test-HasNonEmptyField -Record $deferred -Field "target") -and (Test-HasNonEmptyField -Record $deferred -Field "targetKind"))

  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "Deferred live-write entry must carry a non-empty deferredUpdate."
  }
  else {
    if ([string]$deferred.deferredUpdate -notmatch "receipt") {
      Add-Issue $issues "Deferred live-write entry must state that any state move is receipt-gated, found: $($deferred.deferredUpdate)."
    }
  }

  if ($isWorkItemEntry) {
    $deferredWorkItem = [string]$deferred.workItem
    if (-not $priorCwiIds.Contains($deferredWorkItem)) {
      Add-Issue $issues "Deferred Work Item state change references an unknown Work Item (not in sibling slices): $deferredWorkItem."
    }
    # No live-write marker fields on a deferred entry.
    foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt")) {
      if ($deferred.PSObject.Properties.Name -contains $liveWriteField) {
        Add-Issue $issues "Deferred Work Item state change for $deferredWorkItem must not carry live-write marker field '$liveWriteField'."
      }
    }
    # receiptGate must name a real receipt id minted in THIS slice and must be the decision receipt
    # bound to this Work Item's decision. This proves the deferred ledger actually tracks the
    # binding receipt rather than free-text aspirational claims.
    $deferredGate = [string]$deferred.receiptGate
    if ([string]::IsNullOrWhiteSpace($deferredGate)) {
      Add-Issue $issues "Deferred Work Item state change for $deferredWorkItem must name its binding receiptGate (a CR-LOCAL-* id minted in this slice)."
    }
    elseif (-not $sliceReceiptIds.ContainsKey($deferredGate)) {
      Add-Issue $issues "Deferred Work Item state change for $deferredWorkItem receiptGate '$deferredGate' must be a receipt id minted in this slice."
    }
    else {
      # Cross-bind: the deferred entry's receiptGate must be the decision receipt for a decision
      # targeting this Work Item (the gate is the receipt that would authorize the deferred write).
      $matchingDecision = $null
      foreach ($d in $decisions) {
        if ([string]$d.workItem -eq $deferredWorkItem) { $matchingDecision = $d; break }
      }
      if ($null -eq $matchingDecision) {
        Add-Issue $issues "Deferred Work Item state change for $deferredWorkItem must correspond to a decision targeting that Work Item; no such decision found."
      }
      elseif ([string]$matchingDecision.decisionReceipt -ne $deferredGate) {
        Add-Issue $issues "Deferred Work Item state change for $deferredWorkItem receiptGate '$deferredGate' must equal the decision receipt '$([string]$matchingDecision.decisionReceipt)' bound to $deferredWorkItem."
      }
    }
    if ($deferredWorkItemEntries.ContainsKey($deferredWorkItem)) {
      Add-Issue $issues "Deferred Work Item state change for $deferredWorkItem appears more than once; one deferred entry per Work Item."
    }
    else {
      $deferredWorkItemEntries[$deferredWorkItem] = $true
    }
  }
  elseif ($isLedgerEntry) {
    $deferredLedgerEntryCount++
    if ([string]$deferred.targetKind -ne "receipt_ledger") {
      Add-Issue $issues "Deferred ledger entry targetKind '$($deferred.targetKind)' must be 'receipt_ledger' for the com_councilreceipt ledger persistence gate."
    }
  }
  else {
    Add-Issue $issues "Deferred live-write entry must name either a 'workItem' (work-item state move) or a 'target'+'targetKind' (ledger persistence gate)."
  }
}

# Every decided Work Item must have a deferred entry proving its would-be live write is gated.
foreach ($decision in $decisions) {
  $decisionWorkItem = [string]$decision.workItem
  if (-not [string]::IsNullOrWhiteSpace($decisionWorkItem) -and -not $deferredWorkItemEntries.ContainsKey($decisionWorkItem)) {
    Add-Issue $issues "Decided Work Item $decisionWorkItem (decision $([string]$decision.decisionId)) has no workItemStateChangesDeferred entry; its would-be live state change is not receipt-gated by the ledger."
  }
}

# The receipt ledger itself must have a deferred persistence entry (receipts are local contract
# evidence only; persisting them to the live com_councilreceipt ledger is Epic 2 gated work).
if ($deferredLedgerEntryCount -lt 1) {
  Add-Issue $issues "Delegation run must include a workItemStateChangesDeferred entry targeting the com_councilreceipt ledger (targetKind receipt_ledger); persisting the local receipts to the live ledger is deferred Epic 2 work."
}

# No live-write marker fields anywhere in the run block.
$forbiddenTopLevelFields = @("dataverseRowId", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt", "solutionPublishAt")
foreach ($forbiddenField in $forbiddenTopLevelFields) {
  if ($run.PSObject.Properties.Name -contains $forbiddenField) {
    Add-Issue $issues "Delegation run must not carry live-write marker field '$forbiddenField'; this slice is local contract evidence only."
  }
}

# Acceptance mapping — bind evidence claims to real slice ids (LOW2). localEvidence prose must cite
# ids that actually exist in the run, so the map cannot drift into aspirational free text while the
# real proof lives elsewhere in the slice.
foreach ($criterion in @(1, 2)) {
  $mapping = @($delegation.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
  if (-not $mapping) {
    Add-Issue $issues "Missing acceptance mapping for AC $criterion."
    continue
  }
  $evidenceEntries = @($mapping.localEvidence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($evidenceEntries.Count -lt 1) {
    Add-Issue $issues "Acceptance mapping for AC $criterion must list non-empty localEvidence."
  }
  if (-not (Test-HasNonEmptyField -Record $mapping -Field "tenantEvidenceRequired")) {
    Add-Issue $issues "Acceptance mapping for AC $criterion must state tenantEvidenceRequired."
  }

  # Collapse localEvidence into one searchable text blob; every id cited must resolve to a real id
  # minted or referenced in this slice (package / decision / receipt / work item).
  $evidenceText = ($evidenceEntries | ForEach-Object { [string]$_ }) -join " "
  $citedPackageIds = [regex]::Matches($evidenceText, "DSP-LOCAL-[A-Za-z0-9-]+") | ForEach-Object { $_.Value }
  $citedDecisionIds = [regex]::Matches($evidenceText, "DEC-LOCAL-[A-Za-z0-9-]+") | ForEach-Object { $_.Value }
  $citedReceiptIds = [regex]::Matches($evidenceText, "CR-LOCAL-[A-Za-z0-9-]+") | ForEach-Object { $_.Value }

  if ($criterion -eq 1) {
    # AC1 = two packages; the map must cite at least one real package id from this slice.
    $boundPackage = $false
    foreach ($pkgId in $citedPackageIds) {
      if ($seenPackageIds.ContainsKey($pkgId)) { $boundPackage = $true; break }
    }
    if (-not $boundPackage) {
      Add-Issue $issues "Acceptance mapping for AC 1 must cite at least one real packageId (DSP-LOCAL-*) minted in this slice; found only: $($citedPackageIds -join ', ')."
    }
  }
  elseif ($criterion -eq 2) {
    # AC2 = one approval + one rejection receipt-backed; the map must cite at least one real decision id
    # and at least one real receipt id from this slice.
    $boundDecision = $false
    foreach ($did in $citedDecisionIds) {
      if ($seenDecisionIds.ContainsKey($did)) { $boundDecision = $true; break }
    }
    if (-not $boundDecision) {
      Add-Issue $issues "Acceptance mapping for AC 2 must cite at least one real decisionId (DEC-LOCAL-*) minted in this slice; found only: $($citedDecisionIds -join ', ')."
    }
    $boundReceipt = $false
    foreach ($rid in $citedReceiptIds) {
      if ($sliceReceiptIds.ContainsKey($rid)) { $boundReceipt = $true; break }
    }
    if (-not $boundReceipt) {
      Add-Issue $issues "Acceptance mapping for AC 2 must cite at least one real receiptId (CR-LOCAL-*) minted in this slice; found only: $($citedReceiptIds -join ', ')."
    }
  }
}

if ($issues.Count -gt 0) {
  Write-Host "Delegation support slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Delegation support slice validation succeeded."
Write-Host "Delegation packages: $($packages.Count)"
Write-Host "Decisions: $($decisions.Count)"
Write-Host "Receipts: $($receipts.Count)"
Write-Host "Receipt source links: $($links.Count)"
Write-Host "Deferred live-write entries: $($workItemStateChangesDeferred.Count)"
Write-Host "DELEGATION_SUPPORT_SLICE_VALIDATE_OK"
