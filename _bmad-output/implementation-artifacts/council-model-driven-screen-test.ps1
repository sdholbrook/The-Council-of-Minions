[CmdletBinding()]
param(
  [string]$ManifestPath,
  [string]$AppCurationEvidencePath,
  [string]$NodePath = "C:\Users\DougHolbrook\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe",
  [string]$NodeModulePath = "C:\Users\DougHolbrook\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\node_modules",
  [string]$RunnerPath,
  [string]$ArtifactRoot,
  [string]$UserDataDir,
  [string]$BrowserChannel = "msedge",
  [switch]$InteractiveLogin,
  [switch]$Headed
)

$ErrorActionPreference = "Stop"

if (-not $ManifestPath) {
  $ManifestPath = Join-Path $PSScriptRoot "dataverse-mvp-schema-manifest.json"
}
if (-not $AppCurationEvidencePath) {
  $AppCurationEvidencePath = Join-Path $PSScriptRoot "app-curation-evidence.json"
}
if (-not $RunnerPath) {
  $RunnerPath = Join-Path $PSScriptRoot "..\test-artifacts\model-driven-screen\council-model-driven-screen-test.js"
}
if (-not $ArtifactRoot) {
  $ArtifactRoot = Join-Path $PSScriptRoot "..\test-artifacts\model-driven-screen\runs"
}
if (-not $UserDataDir) {
  $UserDataDir = Join-Path $PSScriptRoot "..\test-artifacts\model-driven-screen\.auth\chromium"
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

function Invoke-DataverseGet {
  param(
    [Parameter(Mandatory = $true)][string]$WebApiEndpoint,
    [Parameter(Mandatory = $true)][string]$AccessToken,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $headers = @{
    Authorization = "Bearer $AccessToken"
    Accept = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
  }

  $uri = "$WebApiEndpoint/$Path"
  try {
    Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
  }
  catch {
    $response = $_.Exception.Response
    $detail = $null
    if ($response -and $response.GetResponseStream()) {
      $reader = [System.IO.StreamReader]::new($response.GetResponseStream())
      $detail = $reader.ReadToEnd()
    }
    throw "Dataverse GET failed: $uri`n$($_.Exception.Message)`n$detail"
  }
}

function Get-EntityDefinition {
  param(
    [Parameter(Mandatory = $true)][string]$LogicalName,
    [Parameter(Mandatory = $true)][string]$WebApiEndpoint,
    [Parameter(Mandatory = $true)][string]$AccessToken
  )

  Invoke-DataverseGet -WebApiEndpoint $WebApiEndpoint -AccessToken $AccessToken -Path "EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName,EntitySetName,PrimaryIdAttribute"
}

function Get-RequiredCuratedViewId {
  param(
    [Parameter(Mandatory = $true)][object]$CurationEvidence,
    [Parameter(Mandatory = $true)][string]$Table,
    [Parameter(Mandatory = $true)][string]$ViewName
  )

  $match = @($CurationEvidence.curatedViews | Where-Object { $_.table -eq $Table -and $_.name -eq $ViewName }) | Select-Object -First 1
  if (-not $match) {
    throw "Curated view not found in app curation evidence: $Table / $ViewName"
  }
  [string]$match.id
}

function Get-RequiredRecordId {
  param(
    [Parameter(Mandatory = $true)][string]$WebApiEndpoint,
    [Parameter(Mandatory = $true)][string]$AccessToken,
    [Parameter(Mandatory = $true)][string]$EntitySetName,
    [Parameter(Mandatory = $true)][string]$PrimaryIdAttribute,
    [Parameter(Mandatory = $true)][string]$LookupField,
    [Parameter(Mandatory = $true)][string]$LookupValue
  )

  $safeValue = $LookupValue.Replace("'", "''")
  $path = "${EntitySetName}?`$select=$PrimaryIdAttribute,$LookupField&`$filter=$LookupField eq '$safeValue'&`$top=1"
  $result = Invoke-DataverseGet -WebApiEndpoint $WebApiEndpoint -AccessToken $AccessToken -Path $path
  if (-not $result.value -or $result.value.Count -lt 1) {
    throw "Required screen-test record not found in $EntitySetName where $LookupField = '$LookupValue'."
  }
  [string]$result.value[0].$PrimaryIdAttribute
}

function Format-ModelDrivenViewId {
  param([Parameter(Mandatory = $true)][string]$ViewId)

  "%7B$ViewId%7D"
}

$manifest = Get-Content -Raw $ManifestPath | ConvertFrom-Json
$environmentUrl = [string]$manifest.target.environmentUrl
$webApiEndpoint = [string]$manifest.target.webApiEndpoint
$appUniqueName = [string]$manifest.modelDrivenApp.uniqueName
$appDisplayName = [string]$manifest.modelDrivenApp.displayName

if (-not (Test-Path $NodePath)) {
  throw "Node executable not found: $NodePath"
}
if (-not (Test-Path $RunnerPath)) {
  throw "Screen test runner not found: $RunnerPath"
}
if (-not (Test-Path $AppCurationEvidencePath)) {
  throw "App curation evidence not found: $AppCurationEvidencePath"
}

$token = Invoke-JsonCommand -FilePath "az" -Arguments @("account", "get-access-token", "--resource", $environmentUrl)
$accessToken = [string]$token.accessToken
$curationEvidence = Get-Content -Raw $AppCurationEvidencePath | ConvertFrom-Json
$appUniqueQueryValue = $appUniqueName.Replace("'", "''")
$appQuery = "appmodules?`$select=appmoduleid,name,uniquename&`$filter=uniquename eq '$appUniqueQueryValue'"
$apps = Invoke-DataverseGet -WebApiEndpoint $webApiEndpoint -AccessToken $accessToken -Path $appQuery
if (-not $apps.value -or $apps.value.Count -lt 1) {
  $appNameQueryValue = $appDisplayName.Replace("'", "''")
  $appQuery = "appmodules?`$select=appmoduleid,name,uniquename&`$filter=name eq '$appNameQueryValue'"
  $apps = Invoke-DataverseGet -WebApiEndpoint $webApiEndpoint -AccessToken $accessToken -Path $appQuery
}
if (-not $apps.value -or $apps.value.Count -lt 1) {
  throw "Model-driven app not found by unique name '$appUniqueName' or display name '$appDisplayName'."
}

$appId = [string]$apps.value[0].appmoduleid
$appUrl = "$environmentUrl/main.aspx?appid=$appId"
$sourceDef = Get-EntityDefinition -LogicalName "com_councilsourcerecord" -WebApiEndpoint $webApiEndpoint -AccessToken $accessToken
$workDef = Get-EntityDefinition -LogicalName "com_councilworkitem" -WebApiEndpoint $webApiEndpoint -AccessToken $accessToken
$receiptDef = Get-EntityDefinition -LogicalName "com_councilreceipt" -WebApiEndpoint $webApiEndpoint -AccessToken $accessToken
$briefDef = Get-EntityDefinition -LogicalName "com_councilbrief" -WebApiEndpoint $webApiEndpoint -AccessToken $accessToken

$sourceRecordId = Get-RequiredRecordId -WebApiEndpoint $webApiEndpoint -AccessToken $accessToken -EntitySetName $sourceDef.EntitySetName -PrimaryIdAttribute $sourceDef.PrimaryIdAttribute -LookupField "com_council_source_record_id" -LookupValue "manual-demo-source-001"
$workItemId = Get-RequiredRecordId -WebApiEndpoint $webApiEndpoint -AccessToken $accessToken -EntitySetName $workDef.EntitySetName -PrimaryIdAttribute $workDef.PrimaryIdAttribute -LookupField "com_council_work_item_id" -LookupValue "CWI-DEMO-001"
$receiptId = Get-RequiredRecordId -WebApiEndpoint $webApiEndpoint -AccessToken $accessToken -EntitySetName $receiptDef.EntitySetName -PrimaryIdAttribute $receiptDef.PrimaryIdAttribute -LookupField "com_receipt_id" -LookupValue "CR-DEMO-PROPOSED-001"
$briefId = Get-RequiredRecordId -WebApiEndpoint $webApiEndpoint -AccessToken $accessToken -EntitySetName $briefDef.EntitySetName -PrimaryIdAttribute $briefDef.PrimaryIdAttribute -LookupField "com_council_brief_id" -LookupValue "BRIEF-DEMO-001"

$newSourceRecordsViewId = Get-RequiredCuratedViewId -CurationEvidence $curationEvidence -Table "com_councilsourcerecord" -ViewName "New Source Records"
$proposedWorkItemsViewId = Get-RequiredCuratedViewId -CurationEvidence $curationEvidence -Table "com_councilworkitem" -ViewName "Proposed Work Items"
$approvedWorkItemsViewId = Get-RequiredCuratedViewId -CurationEvidence $curationEvidence -Table "com_councilworkitem" -ViewName "Approved Work Items"
$blockedHeldWorkItemsViewId = Get-RequiredCuratedViewId -CurationEvidence $curationEvidence -Table "com_councilworkitem" -ViewName "Blocked or Held Work Items"
$inReviewWorkItemsViewId = Get-RequiredCuratedViewId -CurationEvidence $curationEvidence -Table "com_councilworkitem" -ViewName "In Review"
$completedWorkItemsViewId = Get-RequiredCuratedViewId -CurationEvidence $curationEvidence -Table "com_councilworkitem" -ViewName "Completed Recently"
$failedWorkItemsViewId = Get-RequiredCuratedViewId -CurationEvidence $curationEvidence -Table "com_councilworkitem" -ViewName "Failed Needs Review"
$recentReceiptsViewId = Get-RequiredCuratedViewId -CurationEvidence $curationEvidence -Table "com_councilreceipt" -ViewName "Recent Receipts"

$appHomeDefinition = @{
  name = "app-home"
  screenType = "app-home"
  mustContainAll = @(
    "Council Queue",
    "Intake",
    "Work",
    "Brief",
    "Knowledge",
    "Governance",
    "Council Source Records",
    "Council Work Items",
    "Council Receipts",
    "Council Briefs"
  )
  mustNotContainAny = @("Loading...")
}

$screenDefinitions = @(
  @{
    name = "new-source-records-view"
    screenType = "curated-view"
    table = "com_councilsourcerecord"
    viewName = "New Source Records"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilsourcerecord&viewid=$(Format-ModelDrivenViewId $newSourceRecordsViewId)&viewType=1039"
    mustContainAll = @("New Source Records", "Manual sample source record")
  },
  @{
    name = "proposed-work-items-view"
    screenType = "curated-view"
    table = "com_councilworkitem"
    viewName = "Proposed Work Items"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilworkitem&viewid=$(Format-ModelDrivenViewId $proposedWorkItemsViewId)&viewType=1039"
    mustContainAll = @(
      "Proposed Work Items",
      "Review the first Council source record"
    )
  },
  @{
    name = "approved-work-items-view"
    screenType = "curated-view"
    table = "com_councilworkitem"
    viewName = "Approved Work Items"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilworkitem&viewid=$(Format-ModelDrivenViewId $approvedWorkItemsViewId)&viewType=1039"
    mustContainAll = @("Approved Work Items", "Approve demo Council work item")
  },
  @{
    name = "blocked-held-work-items-view"
    screenType = "curated-view"
    table = "com_councilworkitem"
    viewName = "Blocked or Held Work Items"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilworkitem&viewid=$(Format-ModelDrivenViewId $blockedHeldWorkItemsViewId)&viewType=1039"
    mustContainAll = @("Blocked or Held Work Items", "Block demo Council work item", "Hold demo Council work item")
  },
  @{
    name = "in-review-work-items-view"
    screenType = "curated-view"
    table = "com_councilworkitem"
    viewName = "In Review"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilworkitem&viewid=$(Format-ModelDrivenViewId $inReviewWorkItemsViewId)&viewType=1039"
    mustContainAll = @("In Review", "Review demo Council work item")
  },
  @{
    name = "completed-work-items-view"
    screenType = "curated-view"
    table = "com_councilworkitem"
    viewName = "Completed Recently"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilworkitem&viewid=$(Format-ModelDrivenViewId $completedWorkItemsViewId)&viewType=1039"
    mustContainAll = @("Completed Recently", "Complete demo Council work item")
  },
  @{
    name = "failed-work-items-view"
    screenType = "curated-view"
    table = "com_councilworkitem"
    viewName = "Failed Needs Review"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilworkitem&viewid=$(Format-ModelDrivenViewId $failedWorkItemsViewId)&viewType=1039"
    mustContainAll = @("Failed Needs Review", "Fail demo Council work item")
  },
  @{
    name = "recent-receipts-view"
    screenType = "curated-view"
    table = "com_councilreceipt"
    viewName = "Recent Receipts"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilreceipt&viewid=$(Format-ModelDrivenViewId $recentReceiptsViewId)&viewType=1039"
    mustContainAll = @(
      "Recent Receipts",
      "CR-DEMO-PROPOSED-001",
      "CR-DEMO-STATE-APPROVED-APPROVED",
      "CR-DEMO-STATE-HELD-HELD",
      "CR-DEMO-STATE-BLOCKED-BLOCKED",
      "CR-DEMO-STATE-INREVIEW-INREVIEW",
      "CR-DEMO-STATE-COMPLETED-COMPLETED",
      "CR-DEMO-STATE-FAILED-FAILED"
    )
  },
  @{
    name = "briefs-view"
    screenType = "baseline-view"
    table = "com_councilbrief"
    viewName = "Active Council Briefs"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilbrief"
    mustContainAll = @("Council Briefs", "Demo Minion Brief")
  },
  @{
    name = "source-record-form"
    screenType = "record-form"
    table = "com_councilsourcerecord"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entityrecord&etn=com_councilsourcerecord&id=$sourceRecordId"
    mustContainAll = @("Manual sample source record", "manual-demo-source-001")
  },
  @{
    name = "work-item-form"
    screenType = "record-form"
    table = "com_councilworkitem"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entityrecord&etn=com_councilworkitem&id=$workItemId"
    mustContainAll = @("Review the first Council source record", "CWI-DEMO-001")
  },
  @{
    name = "receipt-form"
    screenType = "record-form"
    table = "com_councilreceipt"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entityrecord&etn=com_councilreceipt&id=$receiptId"
    mustContainAll = @("CR-DEMO-PROPOSED-001")
  },
  @{
    name = "brief-form"
    screenType = "record-form"
    table = "com_councilbrief"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entityrecord&etn=com_councilbrief&id=$briefId"
    mustContainAll = @("Demo Minion Brief", "BRIEF-DEMO-001")
  }
)

New-Item -ItemType Directory -Force $ArtifactRoot | Out-Null
$configPath = Join-Path $ArtifactRoot "current-screen-test-config.json"
$config = @{
  environmentUrl = $environmentUrl
  webApiEndpoint = $webApiEndpoint
  appUniqueName = $appUniqueName
  appDisplayName = $appDisplayName
  resolvedAppUniqueName = [string]$apps.value[0].uniquename
  appId = $appId
  appUrl = $appUrl
  artifactRoot = (Resolve-Path $ArtifactRoot).Path
  appHome = $appHomeDefinition
  screens = $screenDefinitions
}
$config | ConvertTo-Json -Depth 20 | Set-Content -Encoding utf8 $configPath

$previousNodePath = $env:NODE_PATH
$previousInteractive = $env:COUNCIL_SCREEN_INTERACTIVE
$previousHeaded = $env:COUNCIL_SCREEN_HEADED
$previousUserDataDir = $env:COUNCIL_SCREEN_USER_DATA_DIR
$previousBrowserChannel = $env:COUNCIL_SCREEN_CHANNEL
try {
  $pnpmNodeModulePath = Join-Path $NodeModulePath ".pnpm\node_modules"
  $env:NODE_PATH = @($NodeModulePath, $pnpmNodeModulePath) -join [System.IO.Path]::PathSeparator
  $env:COUNCIL_SCREEN_INTERACTIVE = if ($InteractiveLogin) { "1" } else { "0" }
  $env:COUNCIL_SCREEN_HEADED = if ($Headed) { "1" } else { "0" }
  $env:COUNCIL_SCREEN_USER_DATA_DIR = $UserDataDir
  $env:COUNCIL_SCREEN_CHANNEL = $BrowserChannel

  & $NodePath $RunnerPath --config $configPath
  if ($LASTEXITCODE -ne 0) {
    throw "Council model-driven screen test failed. Inspect artifacts under $ArtifactRoot."
  }
}
finally {
  $env:NODE_PATH = $previousNodePath
  $env:COUNCIL_SCREEN_INTERACTIVE = $previousInteractive
  $env:COUNCIL_SCREEN_HEADED = $previousHeaded
  $env:COUNCIL_SCREEN_USER_DATA_DIR = $previousUserDataDir
  $env:COUNCIL_SCREEN_CHANNEL = $previousBrowserChannel
}
