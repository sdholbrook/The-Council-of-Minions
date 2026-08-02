param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$TenantSlicePath = "$PSScriptRoot\tenant-readiness-gates-slice.json",
  [string]$ApprovalBoundariesSlicePath = "$PSScriptRoot\approval-boundaries-slice.json",
  [string]$FailurePolicyDenialSlicePath = "$PSScriptRoot\failure-policy-denial-slice.json",
  [string]$TenantDecisionPacketPath = "$PSScriptRoot\tenant-decision-packet.json",
  [string]$DemoEvidencePath = "$PSScriptRoot\state-transition-demo-evidence.json",
  [string]$FixturesDirPath = "$PSScriptRoot\tenant-readiness-probe-fixtures",
  [switch]$ShowFixtureIssues
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
  if ($null -eq $table) { return @() }
  $column = @($table.columns) | Where-Object { $_.name -eq $ColumnName } | Select-Object -First 1
  if ($null -eq $column) { return @() }
  @($column.values | Where-Object { $null -ne $_ })
}

function Test-HasNonEmptyField {
  param(
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$Field
  )

  if ($null -eq $Record) { return $false }
  if (-not ($Record -is [psobject])) { return $false }
  if (@($Record.PSObject.Properties.Name) -notcontains $Field) {
    return $false
  }
  if ($null -eq $Record.$Field -or [string]::IsNullOrWhiteSpace([string]$Record.$Field)) {
    return $false
  }
  return $true
}

function Test-StrictBooleanTrue {
  param($Value)

  ($Value -is [bool]) -and $Value
}

function Test-StrictBoolean {
  param($Value)

  $Value -is [bool]
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
    # Throw (never exit): the proven-to-fail battery runs the check set repeatedly in-process,
    # and a fixture that fails to parse must count as a produced failure, not kill the process.
    throw "Input file is not valid JSON: $Path"
  }
}

function Split-EvidenceRefs {
  param([Parameter(Mandatory = $true)][string]$Raw)

  @(([string]$Raw) -split "[;\r\n]" | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

# Recursive scanner: harvest every receipt id, capability id, work item id, source record id, and
# run id declared anywhere in a slice JSON, without depending on each sibling's run-block name.
# The collector is a hashtable (reference type) passed in by the caller so recursion does not
# depend on PowerShell's dynamic-scope variable visibility.
function Invoke-ScanSliceIdentifiers {
  param($Node, $Collector)

  if ($null -eq $Node) { return }
  if ($Node -is [string]) { return }
  if ($Node -is [System.ValueType]) { return }
  if (-not ($Node -is [System.Collections.IDictionary]) -and
      -not ($Node -is [Array] -or $Node -is [System.Collections.IList]) -and
      -not ($Node -is [psobject])) { return }

  if ($Node -is [System.Collections.IDictionary]) {
    foreach ($key in @($Node.Keys)) {
      $value = $Node[$key]
      switch -CaseSensitive ($key) {
        "com_receipt_id" {
          $s = [string]$value
          if (-not [string]::IsNullOrWhiteSpace($s) -and $s -match "^CR-") { $Collector.ReceiptIds.Add($s) | Out-Null }
        }
        "com_council_work_item_id" {
          $s = [string]$value
          if (-not [string]::IsNullOrWhiteSpace($s) -and $s -match "^CWI-") { $Collector.WorkItemIds.Add($s) | Out-Null }
        }
        "com_council_source_record_id" {
          $s = [string]$value
          if (-not [string]::IsNullOrWhiteSpace($s) -and $s -match "^CSR-") { $Collector.SourceRecordIds.Add($s) | Out-Null }
        }
        "capabilityId" {
          $s = [string]$value
          if (-not [string]::IsNullOrWhiteSpace($s) -and $s -match "^CAP-") { $Collector.CapabilityIds.Add($s) | Out-Null }
        }
        "runId" {
          $s = [string]$value
          if (-not [string]::IsNullOrWhiteSpace($s)) { $Collector.RunIds.Add($s) | Out-Null }
        }
        "receiptIds" {
          foreach ($entry in @($value)) {
            $s = [string]$entry
            if (-not [string]::IsNullOrWhiteSpace($s) -and $s -match "^CR-") { $Collector.ReceiptIds.Add($s) | Out-Null }
          }
        }
        default { Invoke-ScanSliceIdentifiers -Node $value -Collector $Collector }
      }
    }
    return
  }

  if ($Node -is [Array] -or ($Node -is [System.Collections.IList])) {
    foreach ($element in $Node) { Invoke-ScanSliceIdentifiers -Node $element -Collector $Collector }
    return
  }

  foreach ($prop in @($Node.PSObject.Properties)) {
    switch -CaseSensitive ($prop.Name) {
      "com_receipt_id" {
        $s = [string]$prop.Value
        if (-not [string]::IsNullOrWhiteSpace($s) -and $s -match "^CR-") { $Collector.ReceiptIds.Add($s) | Out-Null }
      }
      "com_council_work_item_id" {
        $s = [string]$prop.Value
        if (-not [string]::IsNullOrWhiteSpace($s) -and $s -match "^CWI-") { $Collector.WorkItemIds.Add($s) | Out-Null }
      }
      "com_council_source_record_id" {
        $s = [string]$prop.Value
        if (-not [string]::IsNullOrWhiteSpace($s) -and $s -match "^CSR-") { $Collector.SourceRecordIds.Add($s) | Out-Null }
      }
      "capabilityId" {
        $s = [string]$prop.Value
        if (-not [string]::IsNullOrWhiteSpace($s) -and $s -match "^CAP-") { $Collector.CapabilityIds.Add($s) | Out-Null }
      }
      "runId" {
        $s = [string]$prop.Value
        if (-not [string]::IsNullOrWhiteSpace($s)) { $Collector.RunIds.Add($s) | Out-Null }
      }
      "receiptIds" {
        foreach ($entry in @($prop.Value)) {
          $s = [string]$entry
          if (-not [string]::IsNullOrWhiteSpace($s) -and $s -match "^CR-") { $Collector.ReceiptIds.Add($s) | Out-Null }
        }
      }
      default { Invoke-ScanSliceIdentifiers -Node $prop.Value -Collector $Collector }
    }
  }
}

function Get-SliceIdentifiers {
  param([Parameter(Mandatory = $true)]$Node)

  $ids = @{
    ReceiptIds       = [System.Collections.Generic.List[string]]::new()
    WorkItemIds       = [System.Collections.Generic.List[string]]::new()
    SourceRecordIds   = [System.Collections.Generic.List[string]]::new()
    CapabilityIds     = [System.Collections.Generic.List[string]]::new()
    RunIds            = [System.Collections.Generic.List[string]]::new()
  }
  Invoke-ScanSliceIdentifiers -Node $Node -Collector $ids
  , $ids
}

# =================================================================================================
# The FULL check set, wrapped so the proven-to-fail battery can run it repeatedly in-process:
# once per committed mutation fixture (tenant-slice path substituted, everything else identical),
# then once for the real slice. It returns the issues list; it never exits, and never prints the
# final report or the OK token.
# =================================================================================================
function Invoke-TenantReadinessCheckSet {
  param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$TenantSlicePath,
    [Parameter(Mandatory = $true)][string]$ApprovalBoundariesSlicePath,
    [Parameter(Mandatory = $true)][string]$FailurePolicyDenialSlicePath,
    [Parameter(Mandatory = $true)][string]$TenantDecisionPacketPath,
    [Parameter(Mandatory = $true)][string]$DemoEvidencePath,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$SiblingSliceFiles,
    [hashtable]$SummaryCollector
  )

  $manifest = Read-JsonInput -Path $ManifestPath
  $tenant = Read-JsonInput -Path $TenantSlicePath
  $approvalBoundariesSlice = Read-JsonInput -Path $ApprovalBoundariesSlicePath
  $failurePolicyDenialSlice = Read-JsonInput -Path $FailurePolicyDenialSlicePath
  $tenantDecisionPacket = Read-JsonInput -Path $TenantDecisionPacketPath
  $demoEvidence = Read-JsonInput -Path $DemoEvidencePath
  $issues = [System.Collections.Generic.List[string]]::new()

$receiptVerbs = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptverb"
$actorTypes = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_actortype"
$receiptResults = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_receiptresult"
$workItemStateGroups = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_workitemstategroup"
$tenantEvidenceDecisions = Get-ColumnChoiceValues -Manifest $manifest -TableSchemaName "com_counciltenantevidence" -ColumnName "com_decision"
$platformDecisions = Get-ChoiceValues -Manifest $manifest -ChoiceName "com_platformdecision"

foreach ($vocabulary in @(
    @{ Name = "com_receiptverb"; Values = $receiptVerbs },
    @{ Name = "com_actortype"; Values = $actorTypes },
    @{ Name = "com_receiptresult"; Values = $receiptResults },
    @{ Name = "com_workitemstategroup"; Values = $workItemStateGroups },
    @{ Name = "com_counciltenantevidence.com_decision"; Values = $tenantEvidenceDecisions },
    @{ Name = "com_platformdecision"; Values = $platformDecisions }
  )) {
  if (@($vocabulary.Values).Count -eq 0) {
    Add-Issue $issues "Manifest vocabulary missing or empty: $($vocabulary.Name)."
  }
}

foreach ($requiredVerb in @("reviewed", "policy_denied")) {
  if ($receiptVerbs -notcontains $requiredVerb) {
    Add-Issue $issues "Manifest com_receiptverb is missing the Story 5.4 verb: $requiredVerb."
  }
}
foreach ($requiredResult in @("succeeded", "rejected")) {
  if ($receiptResults -notcontains $requiredResult) {
    Add-Issue $issues "Manifest com_receiptresult is missing the Story 5.4 result: $requiredResult."
  }
}
foreach ($requiredDecision in @("available_with_constraints")) {
  if ($tenantEvidenceDecisions -notcontains $requiredDecision) {
    Add-Issue $issues "Manifest com_counciltenantevidence.com_decision is missing the Story 5.4 decision value: $requiredDecision."
  }
}

if ($tenant.storyKey -ne "5-4-enforce-tenant-readiness-and-verify-in-tenant-gates") {
  Add-Issue $issues "Tenant readiness slice storyKey must be 5-4-enforce-tenant-readiness-and-verify-in-tenant-gates, found: $($tenant.storyKey)."
}
if ([string]$tenant.status -notmatch "^local-contract") {
  Add-Issue $issues "Tenant readiness slice status must declare local contract evidence, found: $($tenant.status)."
}

foreach ($guard in @("noTenantWrites", "noOutboundAction", "noApprovalExecution", "requiresExplicitHumanApprovalForExecution", "receiptsAreLocalContractEvidenceOnly", "receiptsAppendOnly", "noLiveWriteBeforeApprovedBoundary", "unverifiedCapabilitiesAreVerifyInTenant", "verificationFlipsAreReceiptBacked", "policyDenialsForUnverifiedCapabilityActions", "noCapabilityPublishedOrRegisteredInThisSlice")) {
  if (-not ($tenant.guards.PSObject.Properties.Name -contains $guard)) {
    Add-Issue $issues "Tenant readiness slice must declare guard: $guard."
  }
}
if ($null -ne $tenant.guards) {
  foreach ($guardProperty in @($tenant.guards.PSObject.Properties)) {
    if (-not (Test-StrictBooleanTrue $guardProperty.Value)) {
      Add-Issue $issues "Tenant readiness guard must be boolean true: $($guardProperty.Name)."
    }
  }
}

# --- Cross-slice id inventory (minted vs referenced) -----------------------------------------
# Harvest every CR-*/CWI-*/CSR-*/CAP-* id declared by every sibling *-slice.json on disk, plus
# the reserved demo receipt ids, plus the work-item ids in the approval-boundaries slice (which
# this slice references as authority). Sibling ids are the REFERENCED universe; ids minted only
# in this slice must not collide with any sibling id (Story hard rule: unique across ALL slices).
$siblingIdUniverse = @{
  ReceiptIds      = @{}
  WorkItemIds     = @{}
  SourceRecordIds = @{}
  CapabilityIds   = @{}
}
foreach ($siblingFile in $siblingSliceFiles) {
  $siblingNode = Read-JsonInput -Path $siblingFile.FullName
  $harvest = Get-SliceIdentifiers -Node $siblingNode
  foreach ($rid in $harvest.ReceiptIds) {
    if (-not $siblingIdUniverse.ReceiptIds.ContainsKey($rid)) { $siblingIdUniverse.ReceiptIds[$rid] = $siblingFile.Name }
  }
  foreach ($wid in $harvest.WorkItemIds) {
    if (-not $siblingIdUniverse.WorkItemIds.ContainsKey($wid)) { $siblingIdUniverse.WorkItemIds[$wid] = $siblingFile.Name }
  }
  foreach ($sid in $harvest.SourceRecordIds) {
    if (-not $siblingIdUniverse.SourceRecordIds.ContainsKey($sid)) { $siblingIdUniverse.SourceRecordIds[$sid] = $siblingFile.Name }
  }
  foreach ($cap in $harvest.CapabilityIds) {
    if (-not $siblingIdUniverse.CapabilityIds.ContainsKey($cap)) { $siblingIdUniverse.CapabilityIds[$cap] = $siblingFile.Name }
  }
}
# Reserved demo receipt ids (state-transition-demo-evidence.json) are not produced by a slice scan.
foreach ($rid in @($demoEvidence.receiptIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
  $siblingIdUniverse.ReceiptIds[[string]$rid] = "state-transition-demo-evidence.json"
}
foreach ($wid in @($demoEvidence.workItemIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
  $siblingIdUniverse.WorkItemIds[[string]$wid] = "state-transition-demo-evidence.json"
}

if ($siblingIdUniverse.ReceiptIds.Count -eq 0) {
  Add-Issue $issues "No sibling receipt ids could be harvested from *-slice.json files in $PSScriptRoot; minted-vs-referenced collision checks would silently no-op."
}
if ($siblingIdUniverse.WorkItemIds.Count -eq 0) {
  Add-Issue $issues "No sibling work-item ids could be harvested from *-slice.json files in $PSScriptRoot; referenced-id resolution checks would silently no-op."
}

# --- Run block ---------------------------------------------------------------------------------
$run = $tenant.tenantReadinessRun
if ($null -eq $run) {
  # No exit: return the issues accumulated so far so fixture runs can continue in-process.
  Add-Issue $issues "Tenant readiness slice must carry a tenantReadinessRun block."
  return $issues
}
if (-not (Test-HasNonEmptyField -Record $run -Field "runId")) {
  Add-Issue $issues "Tenant readiness run must declare a runId."
}
elseif ($siblingIdUniverse.ReceiptIds.Count -ge 0) {
  # runId uniqueness is checked against sibling runIds harvested below (after we scan siblings).
}
if ($run.semanticContractVersion -ne "2026-07-07") {
  Add-Issue $issues "Tenant readiness run semanticContractVersion must be 2026-07-07, found: $($run.semanticContractVersion)."
}
if ($actorTypes -notcontains $run.actorType) {
  Add-Issue $issues "Tenant readiness run actorType must use manifest com_actortype vocabulary, found: $($run.actorType)."
}
foreach ($field in @("actorId", "authorityBasis")) {
  if (-not (Test-HasNonEmptyField -Record $run -Field $field)) {
    Add-Issue $issues "Tenant readiness run must carry a non-empty ${field}."
  }
}
foreach ($inputSlice in @("manual-source-record-slice.json", "outlook-source-reference-slice.json", "proposed-work-item-extraction-slice.json", "zero-multi-item-extraction-slice.json", "approval-boundaries-slice.json", "failure-policy-denial-slice.json", "tenant-decision-packet.json")) {
  if (@($run.inputSlicesFrom) -notcontains $inputSlice) {
    Add-Issue $issues "Tenant readiness run must reference $inputSlice as an input."
  }
}

$decisionPolicy = $run.decisionPolicy
if ($null -eq $decisionPolicy) {
  Add-Issue $issues "Tenant readiness run must declare a decisionPolicy block."
}
else {
  foreach ($policyName in @("unverifiedCapabilitiesStayVerifyInTenantUntilEvidenceExists", "noLiveWriteBeforeApprovedBoundaryDocumented", "verificationFlipsRequireReceipt", "actionsOnUnverifiedCapabilitiesEmitPolicyDenialReceipt", "tenantValidationEvidenceMustCarryAllEightFields", "liveTenantWriteReceiptGatedToApprovedEpic2Boundary")) {
    if (@($decisionPolicy.PSObject.Properties.Name) -notcontains $policyName) {
      Add-Issue $issues "Tenant readiness run decisionPolicy must declare: $policyName."
    }
  }
  foreach ($policyProperty in @($decisionPolicy.PSObject.Properties)) {
    if (-not (Test-StrictBooleanTrue $policyProperty.Value)) {
      Add-Issue $issues "Tenant readiness run decisionPolicy entry must be boolean true: $($policyProperty.Name)."
    }
  }
}

# --- Capability kind vocabulary (local extension) --------------------------------------------
$kindVocab = $run.capabilityKindVocabulary
$declaredKinds = @{}
if ($null -eq $kindVocab) {
  Add-Issue $issues "Tenant readiness run must declare a capabilityKindVocabulary block."
}
else {
  if (-not (Test-HasNonEmptyField -Record $kindVocab -Field "basis")) {
    Add-Issue $issues "capabilityKindVocabulary must carry a non-empty basis explaining the local extension."
  }
  elseif (([string]$kindVocab.basis) -notmatch "extension|no enumerated|local extension") {
    Add-Issue $issues "capabilityKindVocabulary.basis must state that the kinds extend the manifest (no enumerated capability-kind choice)."
  }
  $kindEntries = @($kindVocab.kinds | Where-Object { $null -ne $_ })
  if ($kindEntries.Count -lt 5) {
    Add-Issue $issues "capabilityKindVocabulary must declare at least five kinds (connector, published_agent, app_registration, automation, model_driven_app), found $($kindEntries.Count)."
  }
  foreach ($kindEntry in $kindEntries) {
    $kindValue = [string]$kindEntry.kind
    if ([string]::IsNullOrWhiteSpace($kindValue)) {
      Add-Issue $issues "capabilityKindVocabulary entry must declare a non-empty kind."
      continue
    }
    if ($declaredKinds.ContainsKey($kindValue)) {
      Add-Issue $issues "Duplicate capability kind declared in capabilityKindVocabulary: $kindValue."
    }
    else {
      $declaredKinds[$kindValue] = $kindEntry
    }
    if (-not (Test-HasNonEmptyField -Record $kindEntry -Field "definition")) {
      Add-Issue $issues "Capability kind $kindValue must carry a non-empty definition."
    }
  }
  foreach ($requiredKind in @("connector", "published_agent", "app_registration", "automation", "model_driven_app")) {
    if (-not $declaredKinds.ContainsKey($requiredKind)) {
      Add-Issue $issues "capabilityKindVocabulary must declare kind $requiredKind."
    }
  }
}

# --- Planned (unverified) capabilities --------------------------------------------------------
$plannedCapabilities = @($run.plannedCapabilities | Where-Object { $null -ne $_ })
if ($plannedCapabilities.Count -ne 4) {
  Add-Issue $issues "Tenant readiness slice must include exactly four planned (unverified) capabilities, found $($plannedCapabilities.Count)."
}

$plannedCapabilityIds = @{}
$plannedCapabilityKinds = @{}
$seenCapabilityIds = @{}
foreach ($cap in $plannedCapabilities) {
  $capId = [string]$cap.capabilityId
  $subject = "Planned capability $capId"
  if (-not (Test-HasNonEmptyField -Record $cap -Field "capabilityId")) {
    Add-Issue $issues "Planned capability must declare a non-empty capabilityId."
    continue
  }
  if ($capId -notmatch "^CAP-LOCAL-") {
    Add-Issue $issues "$subject must use Council-level CAP-LOCAL-* identity."
  }
  if ($seenCapabilityIds.ContainsKey($capId)) {
    Add-Issue $issues "Duplicate capability id in slice: $capId."
  }
  else {
    $seenCapabilityIds[$capId] = $true
  }
  $plannedCapabilityIds[$capId] = $cap

  if (-not (Test-HasNonEmptyField -Record $cap -Field "capabilityName")) {
    Add-Issue $issues "$subject must carry a non-empty capabilityName."
  }
  $capKind = [string]$cap.kind
  if ([string]::IsNullOrWhiteSpace($capKind)) {
    Add-Issue $issues "$subject must declare a kind."
  }
  elseif ($declaredKinds.Count -gt 0 -and -not $declaredKinds.ContainsKey($capKind)) {
    Add-Issue $issues "$subject kind '$capKind' is not declared in capabilityKindVocabulary."
  }
  else {
    if ($plannedCapabilityKinds.ContainsKey($capKind)) {
      Add-Issue $issues "$subject kind '$capKind' duplicates another planned capability kind; the four planned capabilities must be of distinct kinds."
    }
    else {
      $plannedCapabilityKinds[$capKind] = $capId
    }
  }
  # An unverified capability MUST be verifyInTenant=true, verified=false, with NO evidence fields.
  if (-not (Test-StrictBooleanTrue $cap.verifyInTenant)) {
    Add-Issue $issues "$subject verifyInTenant must be strict boolean true for an unverified capability, found: $($cap.verifyInTenant)."
  }
  if (-not (Test-StrictBoolean $cap.verified) -or $cap.verified) {
    Add-Issue $issues "$subject verified must be strict boolean false for an unverified capability, found: $($cap.verified)."
  }
  if ([string]$cap.tenantEvidenceStatus -ne "none") {
    Add-Issue $issues "$subject tenantEvidenceStatus must be 'none' for an unverified capability, found: $($cap.tenantEvidenceStatus)."
  }
  if (-not (Test-StrictBoolean $cap.evidenceFieldsPresent) -or $cap.evidenceFieldsPresent) {
    Add-Issue $issues "$subject evidenceFieldsPresent must be strict boolean false for an unverified capability, found: $($cap.evidenceFieldsPresent)."
  }
  # No live-write guard: a non-empty rationale plus the negative-evidence shape — no tenant-write marker fields.
  if (-not (Test-HasNonEmptyField -Record $cap -Field "noLiveWriteGuard")) {
    Add-Issue $issues "$subject must carry a non-empty noLiveWriteGuard rationale."
  }
  if (-not (Test-HasNonEmptyField -Record $cap -Field "deferredWriteGate")) {
    Add-Issue $issues "$subject must carry a non-empty deferredWriteGate naming the receipt gate."
  }
  elseif (([string]$cap.deferredWriteGate) -notmatch "receipt") {
    Add-Issue $issues "$subject deferredWriteGate must state that the live write is receipt-gated."
  }
  # An unverified capability must not carry a tenantValidationEvidence block (no evidence fields).
  if ($cap.PSObject.Properties.Name -contains "tenantValidationEvidence") {
    Add-Issue $issues "$subject must not carry a tenantValidationEvidence block; unverified capabilities have no tenant evidence."
  }
  # No live-write marker fields anywhere on the capability.
  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt", "publishedAt", "publishReceiptId")) {
    if ($cap.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; unverified capabilities prove no live write occurred."
    }
  }
}
foreach ($requiredKind in @("connector", "published_agent", "app_registration", "automation")) {
  if (-not $plannedCapabilityKinds.ContainsKey($requiredKind)) {
    Add-Issue $issues "Tenant readiness slice must include a planned capability of kind $requiredKind."
  }
}

# --- Verified capability -----------------------------------------------------------------------
$verifiedCap = $run.verifiedCapability
if ($null -eq $verifiedCap) {
  Add-Issue $issues "Tenant readiness slice must carry a verifiedCapability block."
}
else {
  $vCapId = [string]$verifiedCap.capabilityId
  $vSubject = "Verified capability $vCapId"
  if (-not (Test-HasNonEmptyField -Record $verifiedCap -Field "capabilityId")) {
    Add-Issue $issues "Verified capability must declare a non-empty capabilityId."
  }
  elseif ($vCapId -notmatch "^CAP-LOCAL-") {
    Add-Issue $issues "$vSubject must use Council-level CAP-LOCAL-* identity."
  }
  else {
    if ($seenCapabilityIds.ContainsKey($vCapId)) {
      Add-Issue $issues "$vSubject duplicates a planned capability id; the verified capability must be distinct from the four unverified ones."
    }
    else {
      $seenCapabilityIds[$vCapId] = $true
    }
  }
  if (-not (Test-HasNonEmptyField -Record $verifiedCap -Field "capabilityName")) {
    Add-Issue $issues "$vSubject must carry a non-empty capabilityName."
  }
  $vKind = [string]$verifiedCap.kind
  if ([string]::IsNullOrWhiteSpace($vKind)) {
    Add-Issue $issues "$vSubject must declare a kind."
  }
  elseif ($declaredKinds.Count -gt 0 -and -not $declaredKinds.ContainsKey($vKind)) {
    Add-Issue $issues "$vSubject kind '$vKind' is not declared in capabilityKindVocabulary."
  }
  elseif ($vKind -ne "model_driven_app") {
    Add-Issue $issues "$vSubject kind must be model_driven_app (the verified capability this slice proves), found: $vKind."
  }
  # A verified capability MUST be verifyInTenant=false, verified=true, with complete evidence.
  if (-not (Test-StrictBoolean $verifiedCap.verifyInTenant) -or $verifiedCap.verifyInTenant) {
    Add-Issue $issues "$vSubject verifyInTenant must be strict boolean false for a verified capability, found: $($verifiedCap.verifyInTenant)."
  }
  if (-not (Test-StrictBooleanTrue $verifiedCap.verified)) {
    Add-Issue $issues "$vSubject verified must be strict boolean true for a verified capability, found: $($verifiedCap.verified)."
  }
  if ([string]$verifiedCap.tenantEvidenceStatus -ne "complete") {
    Add-Issue $issues "$vSubject tenantEvidenceStatus must be 'complete' for a verified capability, found: $($verifiedCap.tenantEvidenceStatus)."
  }
  if (-not (Test-StrictBooleanTrue $verifiedCap.evidenceFieldsPresent)) {
    Add-Issue $issues "$vSubject evidenceFieldsPresent must be strict boolean true for a verified capability, found: $($verifiedCap.evidenceFieldsPresent)."
  }
  if (-not (Test-HasNonEmptyField -Record $verifiedCap -Field "noLiveWriteGuard")) {
    Add-Issue $issues "$vSubject must carry a non-empty noLiveWriteGuard rationale (verification is local-contract evidence; the live write stays deferred)."
  }
  if (-not (Test-HasNonEmptyField -Record $verifiedCap -Field "deferredWriteGate")) {
    Add-Issue $issues "$vSubject must carry a non-empty deferredWriteGate naming the receipt gate."
  }
  elseif (([string]$verifiedCap.deferredWriteGate) -notmatch "receipt") {
    Add-Issue $issues "$vSubject deferredWriteGate must state that the live write is receipt-gated."
  }

  # Verification receipt reference must resolve to a slice receipt (checked after receipts load).
  if (-not (Test-HasNonEmptyField -Record $verifiedCap -Field "verificationReceipt")) {
    Add-Issue $issues "$vSubject must name its verificationReceipt (verification flips are receipt-backed)."
  }

  # The eight required tenant-validation evidence fields — coverage derived, not counted.
  $evidence = $verifiedCap.tenantValidationEvidence
  if ($null -eq $evidence) {
    Add-Issue $issues "$vSubject must carry a tenantValidationEvidence block with all eight required fields."
  }
  else {
    $eightRequiredFields = @(
      "tenantIdentity",
      "environment",
      "authUser",
      "licensingOrCapacityAssumptions",
      "relevantSettings",
      "restrictions",
      "decision",
      "followUpOwner"
    )
    foreach ($field in $eightRequiredFields) {
      if (-not (Test-HasNonEmptyField -Record $evidence -Field $field)) {
        Add-Issue $issues "$vSubject tenantValidationEvidence missing required field: $field (all eight fields are mandatory)."
      }
    }
    # The decision field must use the manifest com_counciltenantevidence.com_decision vocabulary.
    if (Test-HasNonEmptyField -Record $evidence -Field "decision") {
      if ($tenantEvidenceDecisions -notcontains [string]$evidence.decision) {
        Add-Issue $issues "$vSubject tenantValidationEvidence.decision must use manifest com_counciltenantevidence.com_decision vocabulary (available, unavailable, available_with_constraints, not_tested), found: $($evidence.decision)."
      }
      elseif ([string]$evidence.decision -ne "available_with_constraints") {
        Add-Issue $issues "$vSubject tenantValidationEvidence.decision must be available_with_constraints for the verified capability this slice proves (available would imply no constraints, which contradicts the documented boundary), found: $($evidence.decision)."
      }
    }
    # The evidence block must not carry live-write marker fields.
    foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "liveWriteAt", "tenantWriteAt", "publishedAt")) {
      if ($evidence.PSObject.Properties.Name -contains $liveWriteField) {
        Add-Issue $issues "$vSubject tenantValidationEvidence must not carry live-write marker field '$liveWriteField'; verification is local-contract evidence only."
      }
    }
  }
  if (Test-HasNonEmptyField -Record $verifiedCap -Field "dateVerified") {
    Test-IsoTimestamp -Issues $issues -Record $verifiedCap -Field "dateVerified" -Subject $vSubject | Out-Null
  }
}

# --- Failure code vocabulary (local extension, Story 2.6 pattern) -----------------------------
$failureCodeVocab = $run.failureCodeVocabulary
$declaredFailureCodes = @{}
if ($null -eq $failureCodeVocab) {
  Add-Issue $issues "Tenant readiness run must declare a failureCodeVocabulary block for the boundary-rule denial code."
}
else {
  if (-not (Test-HasNonEmptyField -Record $failureCodeVocab -Field "basis")) {
    Add-Issue $issues "failureCodeVocabulary must carry a non-empty basis explaining the manifest extension."
  }
  elseif (([string]$failureCodeVocab.basis) -notmatch "extension|free-text|no enumerated|local extension") {
    Add-Issue $issues "failureCodeVocabulary.basis must state that the codes extend the manifest's free-text com_failure_code column."
  }
  $codes = @($failureCodeVocab.codes | Where-Object { $null -ne $_ })
  if ($codes.Count -lt 1) {
    Add-Issue $issues "failureCodeVocabulary must declare at least one failure code (the boundary-rule denial), found $($codes.Count)."
  }
  foreach ($code in $codes) {
    $codeValue = [string]$code.code
    if ([string]::IsNullOrWhiteSpace($codeValue)) {
      Add-Issue $issues "failureCodeVocabulary entry must declare a non-empty code."
      continue
    }
    if ($declaredFailureCodes.ContainsKey($codeValue)) {
      Add-Issue $issues "Duplicate failure code declared in failureCodeVocabulary: $codeValue."
    }
    else {
      $declaredFailureCodes[$codeValue] = $code
    }
    $codeSubject = "Failure code $codeValue"
    if (-not (Test-HasNonEmptyField -Record $code -Field "definition")) {
      Add-Issue $issues "$codeSubject must carry a non-empty definition."
    }
    if ([string]$code.kind -ne "policy_denial") {
      Add-Issue $issues "$codeSubject kind must be policy_denial for the boundary-rule denial, found: $($code.kind)."
    }
    if (-not (Test-StrictBoolean $code.retryAllowed) -or $code.retryAllowed) {
      Add-Issue $issues "$codeSubject retryAllowed must be strict boolean false (a policy denial is non-retryable without a policy change), found: $($code.retryAllowed)."
    }
    if (-not (Test-StrictBoolean $code.humanReviewRequired) -or $code.humanReviewRequired) {
      Add-Issue $issues "$codeSubject humanReviewRequired must be strict boolean false, found: $($code.humanReviewRequired)."
    }
  }
}

# --- Receipts ----------------------------------------------------------------------------------
$receipts = @($run.receipts | Where-Object { $null -ne $_ })
if ($receipts.Count -ne 2) {
  Add-Issue $issues "Tenant readiness slice must include exactly two receipts (verification flip and boundary-rule denial), found $($receipts.Count)."
}

$receiptTable = @($manifest.tables) | Where-Object { $_.schemaName -eq "com_councilreceipt" } | Select-Object -First 1
$manifestRequiredReceiptFields = @(@($receiptTable.columns) | Where-Object { $_.required -eq $true } | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($manifestRequiredReceiptFields.Count -eq 0) {
  Add-Issue $issues "No required receipt columns could be derived from manifest com_councilreceipt; receipt required-field checks would silently no-op."
}
$receiptRequiredFields = @($manifestRequiredReceiptFields + @("com_before_state", "com_after_state", "com_evidence_refs", "com_decision_rationale", "com_policy_flags")) | Sort-Object -Unique

$sliceReceiptIds = @{}
$seenIdempotencyKeys = @{}
$mintedReceiptIds = @{}
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
      Add-Issue $issues "$subject must use Council-level CR-LOCAL-* identity."
    }
    if ($sliceReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "Duplicate receipt ID in slice: $receiptId."
    }
    else {
      $sliceReceiptIds[$receiptId] = $true
      $mintedReceiptIds[$receiptId] = $true
    }
    # MINTED ids must be unique across ALL slices (Story hard rule).
    if ($siblingIdUniverse.ReceiptIds.ContainsKey($receiptId)) {
      Add-Issue $issues "$subject collides with a reserved receipt ID from $($siblingIdUniverse.ReceiptIds[$receiptId]); new tenant readiness receipts must be unique across all slices."
    }
  }

  if ($receiptVerbs -notcontains $receipt.com_verb) {
    Add-Issue $issues "$subject verb is not in manifest com_receiptverb vocabulary: $($receipt.com_verb)."
  }
  elseif ($receipt.com_verb -ne "reviewed" -and $receipt.com_verb -ne "policy_denied") {
    Add-Issue $issues "$subject must use verb reviewed or policy_denied for Story 5.4, found: $($receipt.com_verb)."
  }
  if ($actorTypes -notcontains $receipt.com_actor_type) {
    Add-Issue $issues "$subject actor type is not in manifest com_actortype vocabulary: $($receipt.com_actor_type)."
  }
  if ($receiptResults -notcontains $receipt.com_result) {
    Add-Issue $issues "$subject result is not in manifest com_receiptresult vocabulary: $($receipt.com_result)."
  }
  Test-IsoTimestamp -Issues $issues -Record $receipt -Field "com_occurred_at" -Subject $subject | Out-Null

  $idempotencyKey = [string]$receipt.com_idempotency_key
  if ([string]::IsNullOrWhiteSpace($idempotencyKey)) {
    Add-Issue $issues "$subject must carry a non-empty com_idempotency_key."
  }
  elseif ($seenIdempotencyKeys.ContainsKey($idempotencyKey)) {
    Add-Issue $issues "$subject reuses an idempotency key already used in this slice: $idempotencyKey."
  }
  else {
    $seenIdempotencyKeys[$idempotencyKey] = $true
  }

  if (-not (Test-StrictBooleanTrue $receipt.com_append_only_locked)) {
    Add-Issue $issues "$subject com_append_only_locked must be strict boolean true (receipts are append-only)."
  }
  Test-ConfidenceInRange -Issues $issues -Record $receipt -Field "com_confidence" -Subject $subject

  # No live-write marker fields: this slice is local contract evidence only.
  foreach ($liveWriteField in @("dataverseRowId", "com_dataverse_row_id", "crmRecordUrl", "environmentUrl", "liveWriteAt", "tenantWriteAt", "publishedAt", "publishReceiptId")) {
    if ($receipt.PSObject.Properties.Name -contains $liveWriteField) {
      Add-Issue $issues "$subject must not carry live-write marker field '$liveWriteField'; Story 5.4 receipts are local contract evidence only."
    }
  }
  # Append-only tripwire: a receipt that claims to edit/replace a prior receipt would break append-only semantics.
  foreach ($editMarker in @("supersedesPriorReceipt", "replacesReceipt", "editedReceiptId", "correctsReceiptId")) {
    if ($receipt.PSObject.Properties.Name -contains $editMarker) {
      Add-Issue $issues "$subject must not carry edit marker '$editMarker'; corrections are new receipts, never edits."
    }
  }

  if (Test-HasNonEmptyField -Record $receipt -Field "com_policy_flags") {
    foreach ($requiredPolicyFlag in @("local_contract_evidence_only", "no_tenant_write")) {
      if ([string]$receipt.com_policy_flags -notmatch [regex]::Escape($requiredPolicyFlag)) {
        Add-Issue $issues "$subject com_policy_flags must declare $requiredPolicyFlag; Story 5.4 receipts are local contract evidence only."
      }
    }
  }

  # Evidence refs: must name at least one MINTED capability id (CAP-LOCAL-*) plus may name
  # REFERENCED cross-slice ids (CWI-*/CSR-*/CR-*) that must resolve in the sibling universe.
  $evidenceRefTokens = Split-EvidenceRefs -Raw ([string]$receipt.com_evidence_refs)
  if ($evidenceRefTokens.Count -eq 0) {
    Add-Issue $issues "$subject com_evidence_refs must name at least one resolvable evidence reference."
  }
  $referencedIds = @()
  foreach ($ref in $evidenceRefTokens) {
    # Skip non-id descriptive tokens (e.g. "tenant-decision-packet.json[...]"). Only enforce
    # resolvability for tokens that look like our id families.
    if ($ref -match "^CAP-LOCAL-") {
      if (-not $seenCapabilityIds.ContainsKey($ref)) {
        Add-Issue $issues "$subject evidence ref '$ref' does not resolve to a capability minted in this slice."
      }
    }
    elseif ($ref -match "^CWI-") {
      $referencedIds += $ref
      if (-not $siblingIdUniverse.WorkItemIds.ContainsKey($ref) -and -not $seenCapabilityIds.ContainsKey($ref)) {
        Add-Issue $issues "$subject referenced work-item id '$ref' does not resolve in any sibling *-slice.json; referenced ids must resolve."
      }
    }
    elseif ($ref -match "^CR-") {
      $referencedIds += $ref
      if (-not $siblingIdUniverse.ReceiptIds.ContainsKey($ref) -and -not $sliceReceiptIds.ContainsKey($ref)) {
        Add-Issue $issues "$subject referenced receipt id '$ref' does not resolve in any sibling *-slice.json or this slice; referenced ids must resolve."
      }
    }
    elseif ($ref -match "^CSR-") {
      $referencedIds += $ref
      if (-not $siblingIdUniverse.SourceRecordIds.ContainsKey($ref)) {
        Add-Issue $issues "$subject referenced source-record id '$ref' does not resolve in any sibling *-slice.json; referenced ids must resolve."
      }
    }
    # Non-id tokens (free-text descriptions) are allowed but carry no resolvability obligation.
  }
  $receipt.PSObject.Properties.Add([psnoteproperty]::new("__referencedIds", $referencedIds)) | Out-Null

  # Before/after state: a denial receipt must keep before==after (no state move in-slice).
  if ($receipt.com_verb -eq "policy_denied") {
    if ((Test-HasNonEmptyField -Record $receipt -Field "com_before_state") -and (Test-HasNonEmptyField -Record $receipt -Field "com_after_state")) {
      if ([string]$receipt.com_before_state -ne [string]$receipt.com_after_state) {
        Add-Issue $issues "$subject must keep com_before_state == com_after_state for a policy_denied receipt; the boundary rule moves no state in-slice, found: $($receipt.com_before_state) -> $($receipt.com_after_state)."
      }
      if ([string]$receipt.com_after_state -ne "verify_in_tenant") {
        Add-Issue $issues "$subject com_after_state must be verify_in_tenant (the capability stays unverified), found: $($receipt.com_after_state)."
      }
    }
    if (-not (Test-HasNonEmptyField -Record $receipt -Field "attemptedAction")) {
      Add-Issue $issues "$subject must carry a non-empty attemptedAction describing the blocked action."
    }
    if (-not (Test-HasNonEmptyField -Record $receipt -Field "com_failure_code")) {
      Add-Issue $issues "$subject must carry a non-empty com_failure_code."
    }
    elseif ($declaredFailureCodes.Count -gt 0 -and -not $declaredFailureCodes.ContainsKey([string]$receipt.com_failure_code)) {
      Add-Issue $issues "$subject com_failure_code '$($receipt.com_failure_code)' is not declared in failureCodeVocabulary."
    }
    elseif ($declaredFailureCodes.ContainsKey([string]$receipt.com_failure_code)) {
      $declaredCode = $declaredFailureCodes[[string]$receipt.com_failure_code]
      if ($receipt.retryAllowed -is [bool] -and $declaredCode.retryAllowed -is [bool] -and $receipt.retryAllowed -ne $declaredCode.retryAllowed) {
        Add-Issue $issues "$subject retryAllowed ($($receipt.retryAllowed)) must match the value declared for code '$($receipt.com_failure_code)' ($($declaredCode.retryAllowed))."
      }
      if ($receipt.humanReviewRequired -is [bool] -and $declaredCode.humanReviewRequired -is [bool] -and $receipt.humanReviewRequired -ne $declaredCode.humanReviewRequired) {
        Add-Issue $issues "$subject humanReviewRequired ($($receipt.humanReviewRequired)) must match the value declared for code '$($receipt.com_failure_code)' ($($declaredCode.humanReviewRequired))."
      }
    }
    if (-not (Test-StrictBoolean $receipt.retryAllowed) -or $receipt.retryAllowed) {
      Add-Issue $issues "$subject retryAllowed must be strict boolean false (a policy denial is non-retryable), found: $($receipt.retryAllowed)."
    }
    if (-not (Test-StrictBoolean $receipt.humanReviewRequired) -or $receipt.humanReviewRequired) {
      Add-Issue $issues "$subject humanReviewRequired must be strict boolean false, found: $($receipt.humanReviewRequired)."
    }
    if ($receipt.com_result -ne "rejected") {
      Add-Issue $issues "$subject must use result rejected for a policy_denied receipt (Story 2.6 vocabulary), found: $($receipt.com_result)."
    }
  }
  elseif ($receipt.com_verb -eq "reviewed") {
    # Verification flip receipt: before verify_in_tenant -> after verified, result succeeded.
    if ((Test-HasNonEmptyField -Record $receipt -Field "com_before_state") -and (Test-HasNonEmptyField -Record $receipt -Field "com_after_state")) {
      if ([string]$receipt.com_before_state -ne "verify_in_tenant") {
        Add-Issue $issues "$subject com_before_state must be verify_in_tenant (the capability was unverified before the flip), found: $($receipt.com_before_state)."
      }
      if ([string]$receipt.com_after_state -ne "verified") {
        Add-Issue $issues "$subject com_after_state must be verified (the flip moves the capability to verified), found: $($receipt.com_after_state)."
      }
    }
    if ($receipt.com_result -ne "succeeded") {
      Add-Issue $issues "$subject must use result succeeded for a verification flip receipt, found: $($receipt.com_result)."
    }
  }
}

foreach ($expectedReceiptId in @("CR-LOCAL-TENANT-VERIFY-001", "CR-LOCAL-TENANT-DENY-001")) {
  if (-not $sliceReceiptIds.ContainsKey($expectedReceiptId)) {
    Add-Issue $issues "Tenant readiness slice must include receipt $expectedReceiptId."
  }
}

$verifyReceipt = $receipts | Where-Object { $_.com_receipt_id -eq "CR-LOCAL-TENANT-VERIFY-001" } | Select-Object -First 1
$denyReceipt = $receipts | Where-Object { $_.com_receipt_id -eq "CR-LOCAL-TENANT-DENY-001" } | Select-Object -First 1
if ($null -ne $verifyReceipt -and $null -ne $verifiedCap) {
  if ([string]$verifiedCap.verificationReceipt -ne "CR-LOCAL-TENANT-VERIFY-001") {
    Add-Issue $issues "Verified capability verificationReceipt must reference CR-LOCAL-TENANT-VERIFY-001, found: $($verifiedCap.verificationReceipt)."
  }
}

# --- Derivation checks: evidence claims must bind to independently checkable facts ------------
# (a) The verificationReceipt must RESOLVE by membership in this slice's receipts collection, and
# the resolved receipt's own content must prove the flip: verb reviewed, result succeeded, and
# com_evidence_refs naming the verified capability id. A well-formed receipt id is not proof.
$resolvedVerificationReceipt = $null
if ($null -ne $verifiedCap -and (Test-HasNonEmptyField -Record $verifiedCap -Field "verificationReceipt")) {
  $verificationReceiptId = [string]$verifiedCap.verificationReceipt
  $vCapSubject = "Verified capability $([string]$verifiedCap.capabilityId)"
  $resolvedVerificationReceipt = $receipts | Where-Object { [string]$_.com_receipt_id -eq $verificationReceiptId } | Select-Object -First 1
  if ($null -eq $resolvedVerificationReceipt) {
    Add-Issue $issues "$vCapSubject verificationReceipt '$verificationReceiptId' does not resolve to any receipt in this slice's receipts collection; verification flips must be backed by a resolvable receipt."
  }
  else {
    if ([string]$resolvedVerificationReceipt.com_verb -ne "reviewed") {
      Add-Issue $issues "Resolved verification receipt $verificationReceiptId must carry verb reviewed, found: $($resolvedVerificationReceipt.com_verb)."
    }
    if ([string]$resolvedVerificationReceipt.com_result -ne "succeeded") {
      Add-Issue $issues "Resolved verification receipt $verificationReceiptId must carry result succeeded, found: $($resolvedVerificationReceipt.com_result)."
    }
    $verificationReceiptRefs = Split-EvidenceRefs -Raw ([string]$resolvedVerificationReceipt.com_evidence_refs)
    if (@($verificationReceiptRefs) -notcontains [string]$verifiedCap.capabilityId) {
      Add-Issue $issues "Resolved verification receipt $verificationReceiptId com_evidence_refs must name the verified capability id $([string]$verifiedCap.capabilityId); the receipt's own evidence must bind the flip to the capability."
    }
  }
}

# (b) Eight-field coverage is DERIVED from the tenantValidationEvidence block itself; the asserted
# evidenceFieldsPresent boolean and tenantEvidenceStatus must match the derived value
# (complete <=> all eight fields non-empty AND the verification receipt resolves). The asserted
# boolean is never trusted.
if ($null -ne $verifiedCap) {
  $vCapSubject = "Verified capability $([string]$verifiedCap.capabilityId)"
  $evidenceBlock = $verifiedCap.tenantValidationEvidence
  $derivedEightFields = @(
    "tenantIdentity",
    "environment",
    "authUser",
    "licensingOrCapacityAssumptions",
    "relevantSettings",
    "restrictions",
    "decision",
    "followUpOwner"
  )
  $derivedEvidenceFieldsPresent = ($null -ne $evidenceBlock)
  if ($derivedEvidenceFieldsPresent) {
    foreach ($field in $derivedEightFields) {
      if (-not (Test-HasNonEmptyField -Record $evidenceBlock -Field $field)) {
        $derivedEvidenceFieldsPresent = $false
      }
    }
  }
  $derivedComplete = $derivedEvidenceFieldsPresent -and ($null -ne $resolvedVerificationReceipt)
  if ((Test-StrictBoolean $verifiedCap.evidenceFieldsPresent) -and ([bool]$verifiedCap.evidenceFieldsPresent -ne $derivedEvidenceFieldsPresent)) {
    Add-Issue $issues "$vCapSubject asserted evidenceFieldsPresent=$($verifiedCap.evidenceFieldsPresent) does not match the coverage derived from the tenantValidationEvidence block itself ($derivedEvidenceFieldsPresent); coverage is derived, never trusted."
  }
  $assertedEvidenceStatus = [string]$verifiedCap.tenantEvidenceStatus
  if ($assertedEvidenceStatus -eq "complete" -and -not $derivedComplete) {
    Add-Issue $issues "$vCapSubject asserted tenantEvidenceStatus=complete but the derived status is incomplete (all eight fields non-empty: $derivedEvidenceFieldsPresent; verification receipt resolves: $($null -ne $resolvedVerificationReceipt)); status is derived, never trusted."
  }
  elseif ($assertedEvidenceStatus -ne "complete" -and $derivedComplete) {
    Add-Issue $issues "$vCapSubject asserted tenantEvidenceStatus='$assertedEvidenceStatus' but the derived status is complete (all eight fields non-empty and the verification receipt resolves); status is derived, never trusted."
  }
}

# (c) Evidence content must bind to independent facts read from already-loaded inputs (never
# literals): the manifest target block and the tenant decision packet are authorities this slice
# cannot mint, so fabricated well-formed strings are caught by content, not presence.
$manifestTarget = $manifest.target
$packetDecisions = $tenantDecisionPacket.decisions
$factEnvironmentId = [string]$manifestTarget.environmentId
$factEnvironmentUrl = [string]$manifestTarget.environmentUrl
$factOrganizationId = [string]$manifestTarget.organizationId
$factTenantDomainOrId = [string]$packetDecisions.tenantDomainOrId.value
$factHumanApprovalOwner = [string]$packetDecisions.humanApprovalOwner.value
foreach ($fact in @(
    @{ Name = "manifest target.environmentId"; Value = $factEnvironmentId },
    @{ Name = "manifest target.environmentUrl"; Value = $factEnvironmentUrl },
    @{ Name = "manifest target.organizationId"; Value = $factOrganizationId },
    @{ Name = "tenant-decision-packet decisions.tenantDomainOrId.value"; Value = $factTenantDomainOrId },
    @{ Name = "tenant-decision-packet decisions.humanApprovalOwner.value"; Value = $factHumanApprovalOwner }
  )) {
  if ([string]::IsNullOrWhiteSpace($fact.Value)) {
    Add-Issue $issues "Independent fact $($fact.Name) is missing or empty; evidence content-binding checks would silently no-op."
  }
}
if ($null -ne $verifiedCap -and $null -ne $verifiedCap.tenantValidationEvidence) {
  $vCapSubject = "Verified capability $([string]$verifiedCap.capabilityId)"
  $evidenceBlock = $verifiedCap.tenantValidationEvidence
  if (Test-HasNonEmptyField -Record $evidenceBlock -Field "environment") {
    $environmentText = [string]$evidenceBlock.environment
    if (-not [string]::IsNullOrWhiteSpace($factEnvironmentId) -and $environmentText -notmatch [regex]::Escape($factEnvironmentId)) {
      Add-Issue $issues "$vCapSubject tenantValidationEvidence.environment must contain the manifest target.environmentId ($factEnvironmentId); the evidence does not bind to the independently declared environment."
    }
    if (-not [string]::IsNullOrWhiteSpace($factEnvironmentUrl) -and $environmentText -notmatch [regex]::Escape($factEnvironmentUrl)) {
      Add-Issue $issues "$vCapSubject tenantValidationEvidence.environment must contain the manifest target.environmentUrl ($factEnvironmentUrl); the evidence does not bind to the independently declared environment."
    }
  }
  if (Test-HasNonEmptyField -Record $evidenceBlock -Field "tenantIdentity") {
    $tenantIdentityText = [string]$evidenceBlock.tenantIdentity
    if (-not [string]::IsNullOrWhiteSpace($factOrganizationId) -and $tenantIdentityText -notmatch [regex]::Escape($factOrganizationId)) {
      Add-Issue $issues "$vCapSubject tenantValidationEvidence.tenantIdentity must contain the manifest target.organizationId ($factOrganizationId); the evidence does not bind to the independently declared organization."
    }
    if (-not [string]::IsNullOrWhiteSpace($factTenantDomainOrId) -and $tenantIdentityText -notmatch [regex]::Escape($factTenantDomainOrId)) {
      Add-Issue $issues "$vCapSubject tenantValidationEvidence.tenantIdentity must contain the tenant-decision-packet decisions.tenantDomainOrId.value ($factTenantDomainOrId); the evidence does not bind to the Doug-approved tenant identity."
    }
  }
  if (Test-HasNonEmptyField -Record $evidenceBlock -Field "followUpOwner") {
    if (-not [string]::IsNullOrWhiteSpace($factHumanApprovalOwner) -and [string]$evidenceBlock.followUpOwner -ne $factHumanApprovalOwner) {
      Add-Issue $issues "$vCapSubject tenantValidationEvidence.followUpOwner must equal the tenant-decision-packet decisions.humanApprovalOwner.value ($factHumanApprovalOwner), found: $($evidenceBlock.followUpOwner)."
    }
  }
  if (Test-HasNonEmptyField -Record $evidenceBlock -Field "authUser") {
    $authUserText = [string]$evidenceBlock.authUser
    if (-not [string]::IsNullOrWhiteSpace($factHumanApprovalOwner) -and $authUserText -notmatch [regex]::Escape($factHumanApprovalOwner)) {
      Add-Issue $issues "$vCapSubject tenantValidationEvidence.authUser must contain the tenant-decision-packet decisions.humanApprovalOwner.value ($factHumanApprovalOwner); the evidence does not bind the auth user to the independently declared approval owner, found: $($evidenceBlock.authUser)."
    }
  }
}

# --- Capability bindings (receipt -> capability) ----------------------------------------------
$bindings = @($run.capabilityBindings | Where-Object { $null -ne $_ })
if ($bindings.Count -lt 2) {
  Add-Issue $issues "Tenant readiness slice must bind each receipt to its capability via capabilityBindings, found $($bindings.Count)."
}
$bindingByReceipt = @{}
foreach ($binding in $bindings) {
  $bSubject = "Capability binding $($binding.com_name)"
  if (-not (Test-HasNonEmptyField -Record $binding -Field "com_name")) {
    Add-Issue $issues "Capability binding must carry a non-empty com_name."
  }
  $bReceiptId = [string]$binding.com_receipt
  if ([string]::IsNullOrWhiteSpace($bReceiptId) -or -not $sliceReceiptIds.ContainsKey($bReceiptId)) {
    Add-Issue $issues "$bSubject references unknown receipt: $bReceiptId."
    continue
  }
  $bCapabilityId = [string]$binding.com_capability
  if ([string]::IsNullOrWhiteSpace($bCapabilityId) -or -not $seenCapabilityIds.ContainsKey($bCapabilityId)) {
    Add-Issue $issues "$bSubject references unknown capability minted in this slice: $bCapabilityId."
    continue
  }
  $bRole = [string]$binding.bindingRole
  if ($bRole -ne "verification" -and $bRole -ne "policy_denial") {
    Add-Issue $issues "$bSubject bindingRole must be verification or policy_denial, found: $bRole."
  }
  if ($bindingByReceipt.ContainsKey($bReceiptId)) {
    Add-Issue $issues "Receipt $bReceiptId is bound to more than one capability; each receipt binds exactly one capability."
  }
  else {
    $bindingByReceipt[$bReceiptId] = $binding
  }
}
foreach ($receiptId in @($sliceReceiptIds.Keys)) {
  if (-not $bindingByReceipt.ContainsKey($receiptId)) {
    Add-Issue $issues "Receipt $receiptId must be bound to its capability by a capabilityBindings entry."
  }
}
# The denial receipt must bind an UNVERIFIED capability (the boundary rule).
if ($null -ne $denyReceipt -and $bindingByReceipt.ContainsKey("CR-LOCAL-TENANT-DENY-001")) {
  $denyCapId = [string]$bindingByReceipt["CR-LOCAL-TENANT-DENY-001"].com_capability
  $denyCap = $plannedCapabilityIds[$denyCapId]
  if ($null -eq $denyCap) {
    Add-Issue $issues "CR-LOCAL-TENANT-DENY-001 must bind an unverified planned capability, found: $denyCapId."
  }
  else {
    if (-not (Test-StrictBooleanTrue $denyCap.verifyInTenant) -or -not (Test-StrictBoolean $denyCap.verified) -or $denyCap.verified) {
      Add-Issue $issues "CR-LOCAL-TENANT-DENY-001 must bind a capability that is verifyInTenant=true and verified=false (unverified); $denyCapId is not unverified."
    }
  }
}
# The verification receipt must bind the VERIFIED capability.
if ($null -ne $verifyReceipt -and $bindingByReceipt.ContainsKey("CR-LOCAL-TENANT-VERIFY-001") -and $null -ne $verifiedCap) {
  $verifyCapId = [string]$bindingByReceipt["CR-LOCAL-TENANT-VERIFY-001"].com_capability
  if ($verifyCapId -ne [string]$verifiedCap.capabilityId) {
    Add-Issue $issues "CR-LOCAL-TENANT-VERIFY-001 must bind the verified capability $([string]$verifiedCap.capabilityId), found: $verifyCapId."
  }
  if ($bindingByReceipt["CR-LOCAL-TENANT-VERIFY-001"].bindingRole -ne "verification") {
    Add-Issue $issues "CR-LOCAL-TENANT-VERIFY-001 capabilityBindings entry must use bindingRole verification."
  }
}

# --- Boundary rule attempt --------------------------------------------------------------------
$boundary = $run.boundaryRuleAttempt
if ($null -eq $boundary) {
  Add-Issue $issues "Tenant readiness slice must carry a boundaryRuleAttempt block demonstrating the boundary rule."
}
else {
  $bCapId = [string]$boundary.attemptedOnCapability
  $bSubject = "Boundary rule attempt on $bCapId"
  if ([string]::IsNullOrWhiteSpace($bCapId) -or -not $plannedCapabilityIds.ContainsKey($bCapId)) {
    Add-Issue $issues "$bSubject must name an unverified planned capability, found: $bCapId."
  }
  else {
    $bCap = $plannedCapabilityIds[$bCapId]
    if (-not (Test-StrictBooleanTrue $bCap.verifyInTenant) -or $bCap.verified) {
      Add-Issue $issues "$bSubject must target a capability that is verifyInTenant=true and verified=false."
    }
  }
  if (-not (Test-HasNonEmptyField -Record $boundary -Field "attemptedAction")) {
    Add-Issue $issues "$bSubject must carry a non-empty attemptedAction."
  }
  if (-not (Test-HasNonEmptyField -Record $boundary -Field "attemptedBy")) {
    Add-Issue $issues "$bSubject must carry a non-empty attemptedBy."
  }
  if ([string]$boundary.denialReceipt -ne "CR-LOCAL-TENANT-DENY-001") {
    Add-Issue $issues "$bSubject denialReceipt must reference CR-LOCAL-TENANT-DENY-001, found: $($boundary.denialReceipt)."
  }
  elseif (-not $sliceReceiptIds.ContainsKey("CR-LOCAL-TENANT-DENY-001")) {
    Add-Issue $issues "$bSubject denialReceipt references a receipt not present in the slice."
  }
  if (-not (Test-HasNonEmptyField -Record $boundary -Field "rationale")) {
    Add-Issue $issues "$bSubject must carry a non-empty rationale."
  }
}

# --- No-live-write proof ---------------------------------------------------------------------
$noLiveWriteProof = @($run.noLiveWriteProof | Where-Object { $null -ne $_ })
if ($noLiveWriteProof.Count -lt 5) {
  Add-Issue $issues "noLiveWriteProof must bind every capability (four planned + one verified), found $($noLiveWriteProof.Count)."
}
$proofByCapability = @{}
foreach ($proof in $noLiveWriteProof) {
  $pCapId = [string]$proof.capability
  $pSubject = "No-live-write proof for $pCapId"
  if ([string]::IsNullOrWhiteSpace($pCapId) -or -not $seenCapabilityIds.ContainsKey($pCapId)) {
    Add-Issue $issues "$pSubject must name a capability minted in this slice."
    continue
  }
  if ($proofByCapability.ContainsKey($pCapId)) {
    Add-Issue $issues "$pSubject duplicate noLiveWriteProof entry for capability $pCapId."
  }
  else {
    $proofByCapability[$pCapId] = $proof
  }
  if ([string]$proof.guard -ne "noLiveWriteBeforeApprovedBoundary") {
    Add-Issue $issues "$pSubject guard must be noLiveWriteBeforeApprovedBoundary, found: $($proof.guard)."
  }
  if (-not (Test-StrictBooleanTrue $proof.value)) {
    Add-Issue $issues "$pSubject value must be strict boolean true, found: $($proof.value)."
  }
  if (-not (Test-HasNonEmptyField -Record $proof -Field "proof")) {
    Add-Issue $issues "$pSubject must carry a non-empty proof rationale."
  }
}
foreach ($capId in @($seenCapabilityIds.Keys)) {
  if (-not $proofByCapability.ContainsKey($capId)) {
    Add-Issue $issues "Missing noLiveWriteProof entry for capability $capId; coverage must be derived over every minted capability."
  }
}

# --- Live writes deferred --------------------------------------------------------------------
$liveWritesDeferred = @($run.liveWritesDeferred | Where-Object { $null -ne $_ })
$deferredByCapability = @{}
foreach ($deferred in $liveWritesDeferred) {
  $dCapId = [string]$deferred.capability
  $dSubject = "Live write deferred for $dCapId"
  if ([string]::IsNullOrWhiteSpace($dCapId) -or -not $seenCapabilityIds.ContainsKey($dCapId)) {
    Add-Issue $issues "$dSubject must name a capability minted in this slice."
    continue
  }
  if ($deferredByCapability.ContainsKey($dCapId)) {
    Add-Issue $issues "$dSubject duplicate liveWritesDeferred entry for capability $dCapId."
  }
  else {
    $deferredByCapability[$dCapId] = $deferred
  }
  if (-not (Test-HasNonEmptyField -Record $deferred -Field "deferredUpdate")) {
    Add-Issue $issues "$dSubject must carry a non-empty deferredUpdate."
  }
  elseif (([string]$deferred.deferredUpdate) -notmatch "receipt") {
    Add-Issue $issues "$dSubject deferredUpdate must state that the live write is receipt-gated."
  }
}
# The verified capability and the boundary-rule-denied capability must both have deferred entries.
if ($null -ne $verifiedCap -and [string]::IsNullOrWhiteSpace([string]$verifiedCap.capabilityId) -eq $false) {
  if (-not $deferredByCapability.ContainsKey([string]$verifiedCap.capabilityId)) {
    Add-Issue $issues "Missing liveWritesDeferred entry for the verified capability $([string]$verifiedCap.capabilityId); the live write that applies it to the tenant must be recorded as receipt-gated."
  }
}
if ($null -ne $denyReceipt -and $bindingByReceipt.ContainsKey("CR-LOCAL-TENANT-DENY-001")) {
  $denyCapId = [string]$bindingByReceipt["CR-LOCAL-TENANT-DENY-001"].com_capability
  if (-not $deferredByCapability.ContainsKey($denyCapId)) {
    Add-Issue $issues "Missing liveWritesDeferred entry for the boundary-rule-denied capability $denyCapId; the gated live write must be recorded."
  }
}

# --- Acceptance mapping -----------------------------------------------------------------------
foreach ($criterion in @(1, 2, 3)) {
  $mapping = @($tenant.acceptanceMapping) | Where-Object { $_.acceptanceCriterion -eq $criterion } | Select-Object -First 1
  if (-not $mapping) {
    Add-Issue $issues "Missing acceptance mapping for AC $criterion."
    continue
  }
  $evidenceStrings = @($mapping.localEvidence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($evidenceStrings.Count -lt 1) {
    Add-Issue $issues "Acceptance mapping for AC $criterion must list non-empty localEvidence."
  }
  if (-not (Test-HasNonEmptyField -Record $mapping -Field "tenantEvidenceRequired")) {
    Add-Issue $issues "Acceptance mapping for AC $criterion must state tenantEvidenceRequired."
  }
  # Bind each localEvidence string to the actual slice graph: it must contain at least one
  # resolvable identifier (a slice receipt id, a minted capability id, a referenced cross-slice
  # id) OR a dotted path into a real slice property. Bare assertions with no anchor fail.
  $validSlicePathTokens = @(
    "tenantReadinessRun.plannedCapabilities", "tenantReadinessRun.verifiedCapability",
    "tenantReadinessRun.receipts", "tenantReadinessRun.capabilityBindings",
    "tenantReadinessRun.noLiveWriteProof", "tenantReadinessRun.boundaryRuleAttempt",
    "tenantReadinessRun.failureCodeVocabulary", "tenantReadinessRun.capabilityKindVocabulary",
    "tenantReadinessRun.liveWritesDeferred", "tenantReadinessRun.decisionPolicy",
    "tenantReadinessRun.inputSlicesFrom", "guards.", "acceptanceMapping.",
    "plannedCapabilities", "verifiedCapability", "capabilityBindings", "noLiveWriteProof",
    "boundaryRuleAttempt", "failureCodeVocabulary", "capabilityKindVocabulary", "liveWritesDeferred"
  )
  foreach ($evidence in $evidenceStrings) {
    $text = [string]$evidence
    $resolved = $false
    foreach ($rid in @($sliceReceiptIds.Keys)) {
      if ($text -match [regex]::Escape($rid)) { $resolved = $true; break }
    }
    if (-not $resolved) {
      foreach ($cid in @($seenCapabilityIds.Keys)) {
        if ($text -match [regex]::Escape($cid)) { $resolved = $true; break }
      }
    }
    if (-not $resolved) {
      foreach ($wid in @($siblingIdUniverse.WorkItemIds.Keys)) {
        if ($text -match [regex]::Escape($wid)) { $resolved = $true; break }
      }
    }
    if (-not $resolved) {
      foreach ($token in $validSlicePathTokens) {
        if ($text -match [regex]::Escape($token)) { $resolved = $true; break }
      }
    }
    if (-not $resolved) {
      Add-Issue $issues "Acceptance mapping for AC $criterion localEvidence must anchor to a resolvable slice identifier or a real slice path; unanchored string: '$($text.Substring(0, [Math]::Min(80, $text.Length)))...'."
    }
  }
}

# --- Final minted-vs-referenced cross-check --------------------------------------------------
# runId uniqueness across sibling slice runIds (harvested live from $PSScriptRoot).
$siblingRunIds = @{}
foreach ($siblingFile in $siblingSliceFiles) {
  $siblingNode = Read-JsonInput -Path $siblingFile.FullName
  $harvest = Get-SliceIdentifiers -Node $siblingNode
  foreach ($sibRunId in $harvest.RunIds) {
    if (-not $siblingRunIds.ContainsKey($sibRunId)) { $siblingRunIds[$sibRunId] = $siblingFile.Name }
  }
}
if (Test-HasNonEmptyField -Record $run -Field "runId") {
  if ($siblingRunIds.ContainsKey([string]$run.runId)) {
    Add-Issue $issues "Tenant readiness run must use a new local runId, not a sibling slice runId ($($siblingRunIds[[string]$run.runId])): $($run.runId)."
  }
}
if ($siblingRunIds.Count -eq 0) {
  Add-Issue $issues "No sibling runIds could be harvested from *-slice.json files in $PSScriptRoot; runId collision checks would silently no-op."
}
# Minted capability ids must not appear in any sibling slice (CAP-* is new to this slice).
foreach ($capId in @($seenCapabilityIds.Keys)) {
  if ($siblingIdUniverse.CapabilityIds.ContainsKey($capId)) {
    Add-Issue $issues "Minted capability id $capId collides with a capability id in $($siblingIdUniverse.CapabilityIds[$capId]); CAP-LOCAL-* ids must be unique across all slices."
  }
}

  # Summary counts come from data parsed inside this validated run — never a post-validation
  # re-read of the slice file (an unvalidated re-read could drift from what was checked).
  if ($null -ne $SummaryCollector) {
    $SummaryCollector["PlannedCapabilities"] = $plannedCapabilities.Count
    $SummaryCollector["VerifiedCapabilities"] = @($run.verifiedCapability | Where-Object { $null -ne $_ }).Count
    $SummaryCollector["Receipts"] = $receipts.Count
    $SummaryCollector["CapabilityBindings"] = $bindings.Count
    $SummaryCollector["NoLiveWriteProofEntries"] = $noLiveWriteProof.Count
  }
  return $issues
}

# =================================================================================================
# Main flow: (1) required inputs, (2) proven-to-fail mutation battery over the committed fixtures,
# (3) only then the real slice. The OK token is unreachable on any path that skips the battery.
# =================================================================================================

# Required inputs: must all be present (a missing sibling would silently no-op a cross-slice tripwire).
$requiredInputs = @(
  $ManifestPath, $TenantSlicePath, $ApprovalBoundariesSlicePath,
  $FailurePolicyDenialSlicePath, $TenantDecisionPacketPath, $DemoEvidencePath
)
foreach ($path in $requiredInputs) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required tenant readiness gates validation input not found: $path"
  }
}

# LIVE cross-slice id harvest from $PSScriptRoot: every *-slice.json sibling on disk is scanned so
# a new sibling cannot silently escape the minted-vs-referenced tripwire by being added later.
# Harvested ONCE here and passed into every check-set call so fixture runs see the identical
# referenced-id universe as the real run (fixtures live in a subdirectory and never match this
# non-recursive *-slice.json harvest).
$siblingSliceFiles = @(
  Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*-slice.json" -File |
    Where-Object { $_.FullName -ne (Resolve-Path -LiteralPath $TenantSlicePath).Path }
)

# --- Proven-to-fail mutation battery ----------------------------------------------------------
# A gate that cannot fail proves nothing. Every run must first prove each committed fixture FAILS
# the exact same check set (same manifest/packet/sibling universe; only the tenant-slice path is
# substituted) before the real slice may be validated. Each fabrication class is machine-pinned
# to the check that catches it by the fixture's own top-level expectedIssuePatterns: a fixture
# passes the battery only if it produced >=1 issue AND every declared pattern matches at least
# one produced issue string — so deleting or neutering any fixture-pinnable check turns the
# battery red instead of leaving it vacuously green. Precisely: every check reachable by
# mutating the tenant slice is pinned by a committed fixture pattern; the input-decay tripwires
# over the manifest/packet facts (e.g. "Independent fact ... is missing or empty") cannot be
# reached by slice substitution and are runtime fail-closed guards instead, not battery-proven.
# A fixture producing zero issues is fatal; a fixture run that throws still counts as a produced
# failure (the gate refused it), but the synthetic throw issue is excluded from pattern matching
# outright (and patterns matching the fixed throw prefix are additionally rejected as too broad
# below), so decayed or malformed fixtures fail the battery loudly instead of vacuously passing it.
if (-not (Test-Path -LiteralPath $FixturesDirPath)) {
  Write-Host "Tenant readiness gates slice validation failed:"
  Write-Host "- Mutation battery missing: fixtures directory not found: $FixturesDirPath. The validator must prove it can fail before it may bless the real slice."
  exit 1
}
$fixtureFiles = @(Get-ChildItem -LiteralPath $FixturesDirPath -Filter "*.json" -File | Sort-Object -Property Name)
# Every canonical fabrication-class fixture must be present by name (six: the five intent-named
# classes plus the post-loopback fixture-06); a count alone could be satisfied by junk files
# while a named class (e.g. the 07-14 probe) silently disappears.
$canonicalFixtureNames = @(
  "fixture-01-evidence-field-dropped.json",
  "fixture-02-flip-without-receipt.json",
  "fixture-03-fabricated-evidence.json",
  "fixture-04-denial-rebound.json",
  "fixture-05-minted-id-collision.json",
  "fixture-06-resolvable-receipt-unproving.json"
)
$batterySetupProblems = [System.Collections.Generic.List[string]]::new()
if ($fixtureFiles.Count -lt 5) {
  $batterySetupProblems.Add("Mutation battery incomplete: found $($fixtureFiles.Count) fixture(s) in $FixturesDirPath; at least 5 committed fabrication-class fixtures are required before the real slice may be blessed.") | Out-Null
}
$fixtureFileNames = @($fixtureFiles | ForEach-Object { $_.Name })
foreach ($canonicalName in $canonicalFixtureNames) {
  if ($fixtureFileNames -notcontains $canonicalName) {
    $batterySetupProblems.Add("Mutation battery incomplete: canonical fixture $canonicalName is missing from $FixturesDirPath; every canonical fabrication-class fixture must be present before the real slice may be blessed.") | Out-Null
  }
}
if ($batterySetupProblems.Count -gt 0) {
  Write-Host "Tenant readiness gates slice validation failed:"
  foreach ($problem in $batterySetupProblems) { Write-Host "- $problem" }
  exit 1
}

$batteryFailures = [System.Collections.Generic.List[string]]::new()
# Single source of truth for the synthetic-throw sentinel: the catch that mints it, the
# pattern-matching skip, and the over-broad-pattern probe must always agree on this exact
# prefix — a reworded copy in any one place would let a throwing fixture's text become
# pattern-eligible again (the vacuous-satisfaction hole the pattern rules exist to close).
$fixtureThrowPrefix = "Fixture run threw (counted as a produced failure):"
foreach ($fixtureFile in $fixtureFiles) {
  # Every *.json in the fixtures dir must declare a non-empty top-level expectedIssuePatterns
  # array of regex strings — the machine-pinned proof of WHICH check catches its fabrication
  # class. A stray, clean, or malformed file thereby fails the battery loudly.
  $expectedPatterns = @()
  $metadataProblem = $null
  try {
    $fixtureMetadata = Read-JsonInput -Path $fixtureFile.FullName
    $rawPatterns = $null
    if ($null -ne $fixtureMetadata -and $fixtureMetadata -is [psobject] -and @($fixtureMetadata.PSObject.Properties.Name) -contains "expectedIssuePatterns") {
      $rawPatterns = $fixtureMetadata.expectedIssuePatterns
    }
    if ($null -eq $rawPatterns -or -not ($rawPatterns -is [Array] -or $rawPatterns -is [System.Collections.IList])) {
      $metadataProblem = "Fixture $($fixtureFile.Name) declares no top-level expectedIssuePatterns array; every committed fixture must machine-pin its fabrication class to the check that catches it. The real slice is not blessed."
    }
    else {
      $expectedPatterns = @($rawPatterns | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
      if ($expectedPatterns.Count -eq 0) {
        $metadataProblem = "Fixture $($fixtureFile.Name) expectedIssuePatterns array is empty; every committed fixture must machine-pin its fabrication class to the check that catches it. The real slice is not blessed."
      }
      else {
        $invalidPatterns = @()
        $overbroadPatterns = @()
        $syntheticThrowProbe = "$fixtureThrowPrefix probe"
        foreach ($pattern in $expectedPatterns) {
          try {
            [void][regex]::new($pattern)
            # A pattern the synthetic throw text can satisfy is too broad to pin a fabrication
            # class: a decayed fixture that merely throws would then pass the battery.
            if ($syntheticThrowProbe -match $pattern) { $overbroadPatterns += $pattern }
          }
          catch { $invalidPatterns += $pattern }
        }
        if ($invalidPatterns.Count -gt 0) {
          $metadataProblem = "Fixture $($fixtureFile.Name) expectedIssuePatterns entry is not a valid regex: $($invalidPatterns -join '; '). The real slice is not blessed."
          $expectedPatterns = @($expectedPatterns | Where-Object { $invalidPatterns -notcontains $_ })
        }
        elseif ($overbroadPatterns.Count -gt 0) {
          $metadataProblem = "Fixture $($fixtureFile.Name) expectedIssuePatterns entry is too broad (it matches the synthetic throw text, so it cannot pin a fabrication class): $($overbroadPatterns -join '; '). The real slice is not blessed."
        }
      }
    }
  }
  catch {
    $metadataProblem = "Fixture $($fixtureFile.Name) could not be read for its expectedIssuePatterns ($($_.Exception.Message)); every committed fixture must declare a non-empty expectedIssuePatterns array. The real slice is not blessed."
  }

  $fixtureIssues = $null
  try {
    $fixtureIssues = @(Invoke-TenantReadinessCheckSet `
        -ManifestPath $ManifestPath `
        -TenantSlicePath $fixtureFile.FullName `
        -ApprovalBoundariesSlicePath $ApprovalBoundariesSlicePath `
        -FailurePolicyDenialSlicePath $FailurePolicyDenialSlicePath `
        -TenantDecisionPacketPath $TenantDecisionPacketPath `
        -DemoEvidencePath $DemoEvidencePath `
        -SiblingSliceFiles $siblingSliceFiles)
  }
  catch {
    # A fixture that cannot even be parsed/processed was still refused by the gate; this
    # synthetic message is the only produced issue and cannot satisfy class-distinctive
    # patterns, so a throw never substitutes for the check the fixture exists to prove.
    $fixtureIssues = @("$fixtureThrowPrefix $($_.Exception.Message)")
  }

  $unmatchedPatterns = [System.Collections.Generic.List[string]]::new()
  $matchedPatternCount = 0
  foreach ($pattern in $expectedPatterns) {
    $patternMatched = $false
    foreach ($fixtureIssue in $fixtureIssues) {
      # The synthetic throw issue is never eligible to satisfy a class-distinctive pattern:
      # matching is restricted to real check-set output, so a throwing fixture always fails
      # its declared patterns regardless of what the exception message happens to contain.
      if (([string]$fixtureIssue).StartsWith($fixtureThrowPrefix)) { continue }
      if ($fixtureIssue -match $pattern) { $patternMatched = $true; break }
    }
    if ($patternMatched) { $matchedPatternCount++ } else { $unmatchedPatterns.Add($pattern) | Out-Null }
  }

  Write-Host "Self-test: $($fixtureFile.Name) produced $($fixtureIssues.Count) issue(s); $matchedPatternCount/$($expectedPatterns.Count) expected pattern(s) matched."
  if ($ShowFixtureIssues) {
    foreach ($fixtureIssue in $fixtureIssues) { Write-Host "  - $fixtureIssue" }
  }
  elseif ($fixtureIssues.Count -eq 1 -and ([string]$fixtureIssues[0]).StartsWith($fixtureThrowPrefix)) {
    # Always surface a throw's root cause: without this, a corrupt shared input or decayed
    # fixture appears only as unmatched-pattern noise in unattended logs.
    Write-Host "  - $($fixtureIssues[0])"
  }

  if ($null -ne $metadataProblem) {
    $batteryFailures.Add($metadataProblem) | Out-Null
  }
  if ($fixtureIssues.Count -eq 0) {
    $batteryFailures.Add("Self-test fixture $($fixtureFile.Name) passed the full check set with zero issues; a gate that cannot fail proves nothing. The real slice is not blessed.") | Out-Null
  }
  elseif ($unmatchedPatterns.Count -gt 0) {
    foreach ($unmatched in $unmatchedPatterns) {
      $batteryFailures.Add("Self-test fixture $($fixtureFile.Name) expected pattern went unmatched: '$unmatched'; the check that catches this fabrication class did not fire. The real slice is not blessed.") | Out-Null
    }
  }
}
if ($batteryFailures.Count -gt 0) {
  Write-Host "Tenant readiness gates slice validation failed:"
  foreach ($batteryFailure in $batteryFailures) {
    Write-Host "- $batteryFailure"
  }
  exit 1
}

# --- Real slice (reachable only after the battery proved the gate can fail) --------------------
$issues = $null
$realRunSummary = @{}
try {
  $issues = @(Invoke-TenantReadinessCheckSet `
      -ManifestPath $ManifestPath `
      -TenantSlicePath $TenantSlicePath `
      -ApprovalBoundariesSlicePath $ApprovalBoundariesSlicePath `
      -FailurePolicyDenialSlicePath $FailurePolicyDenialSlicePath `
      -TenantDecisionPacketPath $TenantDecisionPacketPath `
      -DemoEvidencePath $DemoEvidencePath `
      -SiblingSliceFiles $siblingSliceFiles `
      -SummaryCollector $realRunSummary)
}
catch {
  Write-Host "Tenant readiness gates slice validation failed:"
  Write-Host "- $($_.Exception.Message)"
  exit 1
}

if ($issues.Count -gt 0) {
  Write-Host "Tenant readiness gates slice validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

# Summary counts come from the data parsed inside the validated run above — never a
# post-validation re-read of the slice file.
Write-Host "Tenant readiness gates slice validation succeeded."
Write-Host "Planned (unverified) capabilities: $($realRunSummary["PlannedCapabilities"])"
Write-Host "Verified capabilities: $($realRunSummary["VerifiedCapabilities"])"
Write-Host "Receipts: $($realRunSummary["Receipts"])"
Write-Host "Capability bindings: $($realRunSummary["CapabilityBindings"])"
Write-Host "No-live-write proof entries: $($realRunSummary["NoLiveWriteProofEntries"])"
Write-Host "TENANT_READINESS_GATES_SLICE_VALIDATE_OK"
