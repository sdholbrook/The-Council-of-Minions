[CmdletBinding()]
param(
  [string]$ManifestPath,
  [string]$DecisionPath,
  [string]$EvidencePath,
  [switch]$ExecuteWrites
)

$ErrorActionPreference = "Stop"

if (-not $ManifestPath) {
  $ManifestPath = Join-Path $PSScriptRoot "dataverse-mvp-schema-manifest.json"
}
if (-not $DecisionPath) {
  $DecisionPath = Join-Path $PSScriptRoot "tenant-decision-packet.json"
}
if (-not $EvidencePath) {
  $EvidencePath = Join-Path $PSScriptRoot "state-transition-demo-evidence.json"
}

function Invoke-JsonCommand {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  $output = & $FilePath @Arguments 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed: $FilePath $($Arguments -join ' ')"
  }

  ($output | Out-String) | ConvertFrom-Json
}

function Get-AccessToken {
  param([Parameter(Mandatory = $true)][string]$EnvironmentUrl)

  $token = Invoke-JsonCommand -FilePath "az" -Arguments @(
    "account",
    "get-access-token",
    "--resource",
    $EnvironmentUrl
  )
  return [string]$token.accessToken
}

function Invoke-DataverseRequest {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("GET", "POST", "PATCH")][string]$Method,
    [Parameter(Mandatory = $true)][string]$Path,
    [object]$Body,
    [switch]$AllowNotFound
  )

  $headers = @{
    Authorization = "Bearer $script:AccessToken"
    Accept = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
  }

  $uri = "$($script:WebApiEndpoint)/$Path"

  try {
    if ($null -eq $Body) {
      return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers
    }

    $json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $json -ContentType "application/json; charset=utf-8"
  }
  catch {
    $response = $_.Exception.Response
    if ($AllowNotFound -and $response -and [int]$response.StatusCode -eq 404) {
      return $null
    }

    $message = $_.Exception.Message
    if ($_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
      $message = "$message`n$($_.ErrorDetails.Message)"
    }
    if ($response -and $response.GetResponseStream()) {
      $reader = [System.IO.StreamReader]::new($response.GetResponseStream())
      $detail = $reader.ReadToEnd()
      if (-not [string]::IsNullOrWhiteSpace($detail)) {
        $message = "$message`n$detail"
      }
    }

    throw "Dataverse $Method failed for $Path`n$message"
  }
}

function Get-EntityDefinition {
  param([Parameter(Mandatory = $true)][string]$LogicalName)

  Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName,EntitySetName,PrimaryIdAttribute"
}

function Format-ODataStringLiteral {
  param([Parameter(Mandatory = $true)][string]$Value)

  return $Value.Replace("'", "''")
}

function Get-FirstRecordByText {
  param(
    [Parameter(Mandatory = $true)][string]$EntitySetName,
    [Parameter(Mandatory = $true)][string]$Select,
    [Parameter(Mandatory = $true)][string]$Field,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $escaped = Format-ODataStringLiteral -Value $Value
  $result = Invoke-DataverseRequest -Method GET -Path "${EntitySetName}?`$select=$Select&`$filter=$Field eq '$escaped'&`$top=1"
  if ($result.value.Count -eq 0) {
    return $null
  }

  return $result.value[0]
}

function New-RecordIfMissing {
  param(
    [Parameter(Mandatory = $true)][string]$EntitySetName,
    [Parameter(Mandatory = $true)][string]$PrimaryIdAttribute,
    [Parameter(Mandatory = $true)][string]$LookupField,
    [Parameter(Mandatory = $true)][string]$LookupValue,
    [Parameter(Mandatory = $true)]$Body
  )

  $existing = Get-FirstRecordByText -EntitySetName $EntitySetName -Select $PrimaryIdAttribute -Field $LookupField -Value $LookupValue
  if ($existing) {
    return [string]$existing.$PrimaryIdAttribute
  }

  Invoke-DataverseRequest -Method POST -Path $EntitySetName -Body $Body | Out-Null
  $created = Get-FirstRecordByText -EntitySetName $EntitySetName -Select $PrimaryIdAttribute -Field $LookupField -Value $LookupValue
  if (-not $created) {
    throw "Created record could not be found in $EntitySetName where $LookupField='$LookupValue'."
  }

  return [string]$created.$PrimaryIdAttribute
}

function Get-GlobalChoiceValue {
  param(
    [Parameter(Mandatory = $true)][string]$ChoiceName,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $choice = Invoke-DataverseRequest -Method GET -Path "GlobalOptionSetDefinitions(Name='$ChoiceName')"
  foreach ($option in $choice.Options) {
    $candidate = [string]$option.Label.UserLocalizedLabel.Label
    if ($candidate -eq $Label) {
      return [int]$option.Value
    }
  }

  throw "Choice value '$Label' not found in $ChoiceName."
}

function Get-LocalChoiceValue {
  param(
    [Parameter(Mandatory = $true)][string]$EntityLogicalName,
    [Parameter(Mandatory = $true)][string]$AttributeLogicalName,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $path = "EntityDefinitions(LogicalName='$EntityLogicalName')/Attributes(LogicalName='$AttributeLogicalName')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$expand=OptionSet"
  $attribute = Invoke-DataverseRequest -Method GET -Path $path
  foreach ($option in $attribute.OptionSet.Options) {
    $candidate = [string]$option.Label.UserLocalizedLabel.Label
    if ($candidate -eq $Label) {
      return [int]$option.Value
    }
  }

  throw "Local choice value '$Label' not found in $EntityLogicalName.$AttributeLogicalName."
}

function New-ReceiptSourceIfMissing {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$ReceiptId,
    [Parameter(Mandatory = $true)][string]$SourceId
  )

  $body = @{
    com_name = $Name
    "com_receipt@odata.bind" = "/$script:ReceiptSet($ReceiptId)"
    "com_source_record@odata.bind" = "/$script:SourceSet($SourceId)"
    com_evidence_role = Get-LocalChoiceValue -EntityLogicalName "com_councilreceiptsource" -AttributeLogicalName "com_evidence_role" -Label "supporting"
  }
  New-RecordIfMissing -EntitySetName $script:ReceiptSourceSet -PrimaryIdAttribute $script:ReceiptSourceDef.PrimaryIdAttribute -LookupField "com_name" -LookupValue $Name -Body $body | Out-Null
}

function New-ReceiptIfMissing {
  param(
    [Parameter(Mandatory = $true)][string]$ReceiptExternalId,
    [Parameter(Mandatory = $true)][string]$WorkId,
    [Parameter(Mandatory = $true)][string]$Verb,
    [Parameter(Mandatory = $true)][string]$BeforeState,
    [Parameter(Mandatory = $true)][string]$AfterState,
    [Parameter(Mandatory = $true)][string]$Rationale,
    [Parameter(Mandatory = $true)][string]$Result,
    [string]$FailureCode
  )

  $body = @{
    com_receipt_id = $ReceiptExternalId
    "com_work_item@odata.bind" = "/$script:WorkSet($WorkId)"
    com_verb = Get-GlobalChoiceValue -ChoiceName "com_receiptverb" -Label $Verb
    com_actor_type = Get-GlobalChoiceValue -ChoiceName "com_actortype" -Label "human"
    com_actor_id = "Doug"
    com_authority_basis = "Doug-approved scoped MVP state transition demo; no outbound action."
    com_occurred_at = $script:Timestamp
    com_idempotency_key = $ReceiptExternalId
    com_before_state = $BeforeState
    com_after_state = $AfterState
    com_evidence_refs = $script:SourceExternalId
    com_decision_rationale = $Rationale
    com_confidence = [decimal]1
    com_result = Get-GlobalChoiceValue -ChoiceName "com_receiptresult" -Label $Result
    com_policy_flags = "no_outbound_action;internal_state_only;demo_seed"
    com_append_only_locked = $true
  }
  if (-not [string]::IsNullOrWhiteSpace($FailureCode)) {
    $body.com_failure_code = $FailureCode
  }

  $receiptId = New-RecordIfMissing -EntitySetName $script:ReceiptSet -PrimaryIdAttribute $script:ReceiptDef.PrimaryIdAttribute -LookupField "com_receipt_id" -LookupValue $ReceiptExternalId -Body $body
  New-ReceiptSourceIfMissing -Name "$ReceiptExternalId source evidence" -ReceiptId $receiptId -SourceId $script:SourceId
  return $receiptId
}

function Invoke-StateTransitionDemo {
  $script:SourceDef = Get-EntityDefinition -LogicalName "com_councilsourcerecord"
  $script:WorkDef = Get-EntityDefinition -LogicalName "com_councilworkitem"
  $script:ReceiptDef = Get-EntityDefinition -LogicalName "com_councilreceipt"
  $script:ReceiptSourceDef = Get-EntityDefinition -LogicalName "com_councilreceiptsource"
  $script:BriefDef = Get-EntityDefinition -LogicalName "com_councilbrief"
  $script:SourceSet = $script:SourceDef.EntitySetName
  $script:WorkSet = $script:WorkDef.EntitySetName
  $script:ReceiptSet = $script:ReceiptDef.EntitySetName
  $script:ReceiptSourceSet = $script:ReceiptSourceDef.EntitySetName
  $script:BriefSet = $script:BriefDef.EntitySetName
  $script:SourceExternalId = "manual-demo-source-001"
  $script:Timestamp = (Get-Date).ToUniversalTime().ToString("o")

  $source = Get-FirstRecordByText -EntitySetName $script:SourceSet -Select $script:SourceDef.PrimaryIdAttribute -Field "com_council_source_record_id" -Value $script:SourceExternalId
  if (-not $source) {
    throw "Required demo source record not found: $script:SourceExternalId. Run dataverse-apply-mvp-schema.ps1 -ExecuteWrites -SeedSampleRows first."
  }
  $script:SourceId = [string]$source.$($script:SourceDef.PrimaryIdAttribute)

  $transitions = @(
    [ordered]@{ suffix = "APPROVED"; state = "approved"; verb = "approved"; result = "accepted"; title = "Approve demo Council work item"; rationale = "Doug approves this item for internal Council work only."; next = "Proceed internally within declared authority."; failureCode = $null },
    [ordered]@{ suffix = "HELD"; state = "held"; verb = "held"; result = "accepted"; title = "Hold demo Council work item"; rationale = "Doug holds this item pending judgment or timing."; next = "Wait for Doug to resume or clarify."; failureCode = $null },
    [ordered]@{ suffix = "BLOCKED"; state = "blocked"; verb = "blocked"; result = "accepted"; title = "Block demo Council work item"; rationale = "Doug blocks this item on an external dependency."; next = "Resolve the blocker before work proceeds."; failureCode = $null },
    [ordered]@{ suffix = "INREVIEW"; state = "in_review"; verb = "reviewed"; result = "accepted"; title = "Review demo Council work item"; rationale = "Doug moves this item into review after output exists."; next = "Review output before completion."; failureCode = $null },
    [ordered]@{ suffix = "COMPLETED"; state = "completed"; verb = "completed"; result = "accepted"; title = "Complete demo Council work item"; rationale = "Doug closes this item as accepted for MVP proof."; next = "No further action for this demo item."; failureCode = $null },
    [ordered]@{ suffix = "FAILED"; state = "failed"; verb = "failed"; result = "failed"; title = "Fail demo Council work item"; rationale = "Doug records a failed demo outcome requiring review."; next = "Review failure evidence before retry."; failureCode = "demo_failed_state" }
  )

  $createdWorkItems = @()
  $createdReceipts = @()
  foreach ($transition in $transitions) {
    $workExternalId = "CWI-DEMO-STATE-$($transition.suffix)"
    $proposalReceiptId = "CR-DEMO-STATE-$($transition.suffix)-PROPOSED"
    $transitionReceiptId = "CR-DEMO-STATE-$($transition.suffix)-$($transition.suffix)"

    Write-Host "Ensuring state demo Work Item: $workExternalId -> $($transition.state)"
    $workBody = @{
      com_title = [string]$transition.title
      com_council_work_item_id = $workExternalId
      com_type = Get-GlobalChoiceValue -ChoiceName "com_workitemtype" -Label "request"
      com_summary = "Demo Work Item proving receipt-backed state group '$($transition.state)' in Council Queue."
      com_state_group = Get-GlobalChoiceValue -ChoiceName "com_workitemstategroup" -Label "proposed"
      com_risk_class = Get-GlobalChoiceValue -ChoiceName "com_riskclass" -Label "none"
      "com_primary_source_record@odata.bind" = "/$script:SourceSet($script:SourceId)"
      com_rationale = "State transition demo row created by guarded Council MVP Dataverse script."
      com_recommended_next_action = [string]$transition.next
      com_approval_required = $true
      com_semantic_contract_version = "2026-07-08"
      com_policy_flags = "no_outbound_action;internal_state_only;demo_seed"
    }
    $workId = New-RecordIfMissing -EntitySetName $script:WorkSet -PrimaryIdAttribute $script:WorkDef.PrimaryIdAttribute -LookupField "com_council_work_item_id" -LookupValue $workExternalId -Body $workBody

    $proposalReceiptRowId = New-ReceiptIfMissing -ReceiptExternalId $proposalReceiptId -WorkId $workId -Verb "proposed" -BeforeState "none" -AfterState "proposed" -Rationale "Proposal receipt for deterministic state transition demo item $workExternalId." -Result "accepted"
    $transitionReceiptRowId = New-ReceiptIfMissing -ReceiptExternalId $transitionReceiptId -WorkId $workId -Verb ([string]$transition.verb) -BeforeState "proposed" -AfterState ([string]$transition.state) -Rationale ([string]$transition.rationale) -Result ([string]$transition.result) -FailureCode ([string]$transition.failureCode)

    $patch = @{
      com_state_group = Get-GlobalChoiceValue -ChoiceName "com_workitemstategroup" -Label ([string]$transition.state)
      com_recommended_next_action = [string]$transition.next
      "com_created_receipt@odata.bind" = "/$script:ReceiptSet($proposalReceiptRowId)"
    }
    if ($transition.state -eq "approved") {
      $patch.com_approved_owner = "Doug"
    }
    Invoke-DataverseRequest -Method PATCH -Path "$script:WorkSet($workId)" -Body $patch | Out-Null

    $createdWorkItems += $workExternalId
    $createdReceipts += $proposalReceiptId
    $createdReceipts += $transitionReceiptId
  }

  $brief = Get-FirstRecordByText -EntitySetName $script:BriefSet -Select $script:BriefDef.PrimaryIdAttribute -Field "com_council_brief_id" -Value "BRIEF-DEMO-001"
  if ($brief) {
    $briefId = [string]$brief.$($script:BriefDef.PrimaryIdAttribute)
    $briefPatch = @{
      com_priority_summary = "Demo queue now includes proposed plus receipt-backed approved, held, blocked, in-review, completed, and failed state examples."
      com_decisions_needed = "Use the state demo rows to verify Council Queue filtering and receipt-backed movement."
      com_blockers = "No Dataverse/model-driven app blocker remains for the scoped demo; live Outlook/Graph reads and broader governance checks remain separate gates."
      com_recent_receipts = ($createdReceipts -join "; ")
    }
    Invoke-DataverseRequest -Method PATCH -Path "$script:BriefSet($briefId)" -Body $briefPatch | Out-Null
  }

  $evidence = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    environmentUrl = [string]$script:Manifest.target.environmentUrl
    sourceRecordId = $script:SourceExternalId
    workItemCount = $createdWorkItems.Count
    receiptCount = $createdReceipts.Count
    stateGroups = @($transitions | ForEach-Object { $_.state })
    workItemIds = $createdWorkItems
    receiptIds = $createdReceipts
    noOutboundAction = $true
    idempotencyBasis = "deterministic Work Item IDs and Receipt IDs"
  }
  $evidence | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $EvidencePath

  Write-Host "State transition demo Work Items: $($createdWorkItems.Count)"
  Write-Host "State transition demo Receipts: $($createdReceipts.Count)"
  Write-Host "Evidence: $EvidencePath"
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Manifest not found: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $DecisionPath)) {
  throw "Decision packet not found: $DecisionPath"
}

$script:Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$decision = Get-Content -LiteralPath $DecisionPath -Raw | ConvertFrom-Json

if (-not $ExecuteWrites) {
  Write-Host "DRY RUN ONLY. No tenant writes will be performed."
  Write-Host "Would create or update deterministic receipt-backed state demo rows for approved, held, blocked, in_review, completed, and failed Work Items."
  Write-Host "DATAVERSE_APPLY_STATE_TRANSITION_DEMO_DRY_RUN_OK"
  exit 0
}

if ($decision.decisions.dataverseMvpOperationalStore.value -ne "approved") {
  throw "Dataverse MVP operational store is not approved in the tenant decision packet."
}
if ($decision.decisions.dataverseSandboxWrites.value -ne "allowed_after_readonly_preflight") {
  throw "Dataverse writes are not approved in the tenant decision packet."
}
if ($decision.decisions.modelDrivenAppSurface.value -ne "accepted") {
  throw "Model-driven app review surface is not accepted in the tenant decision packet."
}

& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\tenant-decision-packet-validate.ps1" -RequireComplete
if ($LASTEXITCODE -ne 0) {
  throw "Tenant decision packet validation failed."
}

& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\dataverse-preflight-readonly.ps1"
if ($LASTEXITCODE -ne 0) {
  throw "Dataverse read-only preflight failed."
}

$script:WebApiEndpoint = [string]$script:Manifest.target.webApiEndpoint
$script:AccessToken = Get-AccessToken -EnvironmentUrl ([string]$script:Manifest.target.environmentUrl)

Invoke-StateTransitionDemo
Write-Host "DATAVERSE_APPLY_STATE_TRANSITION_DEMO_OK"
