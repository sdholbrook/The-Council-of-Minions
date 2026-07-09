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
  $EvidencePath = Join-Path $PSScriptRoot "app-curation-evidence.json"
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
    [switch]$AllowNotFound,
    [switch]$IncludeSolutionHeader
  )

  $headers = @{
    Authorization = "Bearer $script:AccessToken"
    Accept = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
  }

  if ($IncludeSolutionHeader) {
    $headers["MSCRM.SolutionUniqueName"] = [string]$script:Manifest.solution.uniqueName
  }

  $uri = "$($script:WebApiEndpoint)/$Path"
  $attempt = 0
  while ($true) {
    $attempt += 1
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
      if ($attempt -lt 3 -and (-not $response -or [int]$response.StatusCode -ge 500)) {
        Start-Sleep -Seconds (2 * $attempt)
        continue
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
}

function Format-ODataStringLiteral {
  param([Parameter(Mandatory = $true)][string]$Value)

  return $Value.Replace("'", "''")
}

function Format-XmlAttribute {
  param([AllowNull()][string]$Value)

  if ($null -eq $Value) {
    return ""
  }

  return [System.Security.SecurityElement]::Escape($Value)
}

function Get-AppModule {
  $appName = Format-ODataStringLiteral -Value ([string]$script:Manifest.modelDrivenApp.displayName)
  $existing = Invoke-DataverseRequest -Method GET -Path "appmodules?`$select=appmoduleid,appmoduleidunique,name&`$filter=name eq '$appName'"
  if ($existing.value.Count -eq 0) {
    throw "Model-driven app not found: $($script:Manifest.modelDrivenApp.displayName)"
  }

  return $existing.value[0]
}

function Get-AppComponents {
  param([Parameter(Mandatory = $true)][string]$AppId)

  $result = Invoke-DataverseRequest -Method GET -Path "RetrieveAppComponents(AppModuleId=$AppId)"
  return @($result.value)
}

function Get-EntityDefinition {
  param([Parameter(Mandatory = $true)][string]$LogicalName)

  Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName,PrimaryIdAttribute,ObjectTypeCode"
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

function Get-FirstMainForm {
  param([Parameter(Mandatory = $true)][string]$TableName)

  $escaped = Format-ODataStringLiteral -Value $TableName
  $result = Invoke-DataverseRequest -Method GET -Path "systemforms?`$select=formid,name,type,objecttypecode&`$filter=objecttypecode eq '$escaped' and type eq 2 and formactivationstate eq 1&`$orderby=name asc&`$top=1"
  if ($result.value.Count -eq 0) {
    throw "No active main form found for $TableName."
  }

  return $result.value[0]
}

function Get-FirstActiveView {
  param([Parameter(Mandatory = $true)][string]$TableName)

  $escaped = Format-ODataStringLiteral -Value $TableName
  $result = Invoke-DataverseRequest -Method GET -Path "savedqueries?`$select=savedqueryid,name,returnedtypecode,querytype,isdefault&`$filter=returnedtypecode eq '$escaped' and querytype eq 0 and statecode eq 0&`$orderby=isdefault desc,name asc&`$top=1"
  if ($result.value.Count -eq 0) {
    throw "No active system view found for $TableName."
  }

  return $result.value[0]
}

function Get-SavedQueryByName {
  param(
    [Parameter(Mandatory = $true)][string]$TableName,
    [Parameter(Mandatory = $true)][string]$ViewName
  )

  $escapedTable = Format-ODataStringLiteral -Value $TableName
  $escapedName = Format-ODataStringLiteral -Value $ViewName
  $result = Invoke-DataverseRequest -Method GET -Path "savedqueries?`$select=savedqueryid,name,returnedtypecode,querytype&`$filter=returnedtypecode eq '$escapedTable' and name eq '$escapedName' and querytype eq 0&`$top=1"
  if ($result.value.Count -eq 0) {
    return $null
  }

  return $result.value[0]
}

function New-FetchXml {
  param(
    [Parameter(Mandatory = $true)][string]$TableName,
    [Parameter(Mandatory = $true)][string[]]$Fields,
    [Parameter(Mandatory = $true)][string]$SortField,
    [object[]]$Conditions
  )

  $table = Format-XmlAttribute -Value $TableName
  $sort = Format-XmlAttribute -Value $SortField
  $xml = [System.Text.StringBuilder]::new()
  [void]$xml.Append('<fetch version="1.0" mapping="logical">')
  [void]$xml.Append("<entity name=""$table"">")
  foreach ($field in $Fields) {
    $name = Format-XmlAttribute -Value $field
    [void]$xml.Append("<attribute name=""$name"" />")
  }
  [void]$xml.Append("<order attribute=""$sort"" descending=""false"" />")
  [void]$xml.Append('<filter type="and">')
  [void]$xml.Append('<condition attribute="statecode" operator="eq" value="0" />')
  foreach ($condition in @($Conditions)) {
    $attribute = Format-XmlAttribute -Value ([string]$condition["attribute"])
    $operator = Format-XmlAttribute -Value ([string]$condition["operator"])
    if ($condition.ContainsKey("values")) {
      [void]$xml.Append("<condition attribute=""$attribute"" operator=""$operator"">")
      foreach ($value in @($condition["values"])) {
        $escapedValue = Format-XmlAttribute -Value ([string]$value)
        [void]$xml.Append("<value>$escapedValue</value>")
      }
      [void]$xml.Append('</condition>')
    }
    else {
      $value = Format-XmlAttribute -Value ([string]$condition["value"])
      [void]$xml.Append("<condition attribute=""$attribute"" operator=""$operator"" value=""$value"" />")
    }
  }
  [void]$xml.Append('</filter>')
  [void]$xml.Append('</entity>')
  [void]$xml.Append('</fetch>')
  return $xml.ToString()
}

function New-LayoutXml {
  param(
    [Parameter(Mandatory = $true)][string]$TableName,
    [Parameter(Mandatory = $true)][int]$ObjectTypeCode,
    [Parameter(Mandatory = $true)][string]$PrimaryIdAttribute,
    [Parameter(Mandatory = $true)][string[]]$Fields,
    [Parameter(Mandatory = $true)][string]$JumpField
  )

  $table = Format-XmlAttribute -Value $TableName
  $id = Format-XmlAttribute -Value $PrimaryIdAttribute
  $jump = Format-XmlAttribute -Value $JumpField
  $xml = [System.Text.StringBuilder]::new()
  [void]$xml.Append("<grid name=""$table"" object=""$ObjectTypeCode"" jump=""$jump"" select=""1"" icon=""1"" preview=""1"">")
  [void]$xml.Append("<row name=""result"" id=""$id"">")
  foreach ($field in $Fields) {
    if ($field -eq $PrimaryIdAttribute) {
      continue
    }
    $name = Format-XmlAttribute -Value $field
    $width = if ($field -match 'summary|rationale|refs|flags') { 260 } elseif ($field -match '_at$|occurred|captured') { 150 } else { 180 }
    [void]$xml.Append("<cell name=""$name"" width=""$width"" />")
  }
  [void]$xml.Append('</row>')
  [void]$xml.Append('</grid>')
  return $xml.ToString()
}

function New-CuratedView {
  param(
    [Parameter(Mandatory = $true)][string]$TableName,
    [Parameter(Mandatory = $true)][string]$ViewName,
    [Parameter(Mandatory = $true)][string[]]$Fields,
    [Parameter(Mandatory = $true)][string]$JumpField,
    [Parameter(Mandatory = $true)][string]$SortField,
    [object[]]$Conditions
  )

  $existing = Get-SavedQueryByName -TableName $TableName -ViewName $ViewName
  if ($existing) {
    return $existing
  }

  $entity = Get-EntityDefinition -LogicalName $TableName
  $fieldList = @($entity.PrimaryIdAttribute) + @($Fields | Where-Object { $_ -ne $entity.PrimaryIdAttribute })
  $body = @{
    name = $ViewName
    returnedtypecode = $TableName
    querytype = 0
    isquickfindquery = $false
    isdefault = $false
    fetchxml = New-FetchXml -TableName $TableName -Fields $fieldList -SortField $SortField -Conditions $Conditions
    layoutxml = New-LayoutXml -TableName $TableName -ObjectTypeCode ([int]$entity.ObjectTypeCode) -PrimaryIdAttribute ([string]$entity.PrimaryIdAttribute) -Fields $fieldList -JumpField $JumpField
    columnsetxml = "<columnset version=""1.0"">$(($fieldList | ForEach-Object { "<column>$_</column>" }) -join '')</columnset>"
    description = "Council MVP curated app view: $ViewName."
  }

  Write-Host "Creating curated view: $TableName / $ViewName"
  Invoke-DataverseRequest -Method POST -Path "savedqueries" -Body $body -IncludeSolutionHeader | Out-Null
  $created = Get-SavedQueryByName -TableName $TableName -ViewName $ViewName
  if (-not $created) {
    throw "Curated view was not found after create: $TableName / $ViewName"
  }

  return $created
}

function Add-AppComponentIfMissing {
  param(
    [Parameter(Mandatory = $true)][string]$AppId,
    [Parameter(Mandatory = $true)]$Components,
    [Parameter(Mandatory = $true)][ValidateSet("savedquery", "systemform")][string]$ComponentKind,
    [Parameter(Mandatory = $true)][string]$ObjectId,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $componentType = if ($ComponentKind -eq "savedquery") { 26 } else { 60 }
  $existing = $Components | Where-Object { $_.componenttype -eq $componentType -and [string]$_.objectid -eq $ObjectId } | Select-Object -First 1
  if ($existing) {
    Write-Host "App component exists: $ComponentKind / $Label"
    return $false
  }

  $component = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.$ComponentKind"
  }
  if ($ComponentKind -eq "savedquery") {
    $component.savedqueryid = $ObjectId
  }
  else {
    $component.formid = $ObjectId
  }

  Write-Host "Adding app component: $ComponentKind / $Label"
  Invoke-DataverseRequest -Method POST -Path "AddAppComponents" -Body @{ AppId = $AppId; Components = @($component) } -IncludeSolutionHeader | Out-Null
  return $true
}

function Get-ConditionSet {
  param(
    [Parameter(Mandatory = $true)][string]$TableName,
    [Parameter(Mandatory = $true)][string]$ViewName
  )

  switch ("$TableName|$ViewName") {
    "com_councilsourcerecord|New Source Records" { return @(@{ attribute = "com_extraction_status"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_extractionstatus" -Label "new") }) }
    "com_councilsourcerecord|Outlook Source Records" { return @(@{ attribute = "com_source_system"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_sourcesystem" -Label "outlook") }) }
    "com_councilsourcerecord|Mock Outlook Source Records" { return @(@{ attribute = "com_source_system"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_sourcesystem" -Label "outlook") }, @{ attribute = "com_source_object_ref"; operator = "like"; value = "%mock%" }) }
    "com_councilsourcerecord|Held Source Records" { return @(@{ attribute = "com_extraction_status"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_extractionstatus" -Label "held") }) }
    "com_councilsourcerecord|Extracted Source Records" { return @(@{ attribute = "com_extraction_status"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_extractionstatus" -Label "extracted") }) }
    "com_councilsourcerecord|Source Records With Drift Risk" { return @(@{ attribute = "com_observed_modified_at"; operator = "not-null" }) }
    "com_councilworkitem|Proposed Work Items" { return @(@{ attribute = "com_state_group"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_workitemstategroup" -Label "proposed") }) }
    "com_councilworkitem|Needs Human Approval" { return @(@{ attribute = "com_approval_required"; operator = "eq"; value = "1" }, @{ attribute = "com_state_group"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_workitemstategroup" -Label "proposed") }) }
    "com_councilworkitem|Approved Work Items" { return @(@{ attribute = "com_state_group"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_workitemstategroup" -Label "approved") }) }
    "com_councilworkitem|Blocked or Held Work Items" { return @(@{ attribute = "com_state_group"; operator = "in"; values = @((Get-GlobalChoiceValue -ChoiceName "com_workitemstategroup" -Label "blocked"), (Get-GlobalChoiceValue -ChoiceName "com_workitemstategroup" -Label "held")) }) }
    "com_councilworkitem|In Review" { return @(@{ attribute = "com_state_group"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_workitemstategroup" -Label "in_review") }) }
    "com_councilworkitem|Completed Recently" { return @(@{ attribute = "com_state_group"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_workitemstategroup" -Label "completed") }) }
    "com_councilworkitem|Failed Needs Review" { return @(@{ attribute = "com_state_group"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_workitemstategroup" -Label "failed") }) }
    "com_councilreceipt|Recent Receipts" { return @() }
    "com_councilreceipt|Failed Receipts" { return @(@{ attribute = "com_result"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_receiptresult" -Label "failed") }) }
    "com_councilreceipt|Policy Denials" { return @(@{ attribute = "com_verb"; operator = "eq"; value = (Get-GlobalChoiceValue -ChoiceName "com_receiptverb" -Label "policy_denied") }) }
    "com_councilreceipt|External Action Requests" { return @(@{ attribute = "com_verb"; operator = "in"; values = @((Get-GlobalChoiceValue -ChoiceName "com_receiptverb" -Label "external_action_requested"), (Get-GlobalChoiceValue -ChoiceName "com_receiptverb" -Label "external_action_completed")) }) }
    "com_councilreceipt|Memory Receipts" { return @(@{ attribute = "com_verb"; operator = "in"; values = @((Get-GlobalChoiceValue -ChoiceName "com_receiptverb" -Label "memory_proposed"), (Get-GlobalChoiceValue -ChoiceName "com_receiptverb" -Label "memory_promoted")) }) }
    default { return @() }
  }
}

function Get-ViewFields {
  param([Parameter(Mandatory = $true)][string]$TableName)

  switch ($TableName) {
    "com_councilsourcerecord" { return @("com_name", "com_council_source_record_id", "com_source_system", "com_source_kind", "com_extraction_status", "com_data_boundary_policy", "com_captured_at") }
    "com_councilworkitem" { return @("com_title", "com_council_work_item_id", "com_type", "com_state_group", "com_approval_required", "com_risk_class", "com_recommended_next_action") }
    "com_councilreceipt" { return @("com_receipt_id", "com_verb", "com_actor_type", "com_actor_id", "com_before_state", "com_after_state", "com_result", "com_occurred_at") }
    default { throw "No curated field set for $TableName." }
  }
}

function Invoke-AppCuration {
  $app = Get-AppModule
  $appId = [string]$app.appmoduleid
  $components = Get-AppComponents -AppId $appId
  $tables = @()
  foreach ($group in $script:Manifest.modelDrivenApp.navigationGroups) {
    $tables += @($group.tables)
  }
  $tables = @($tables | Select-Object -Unique)

  $curatedViews = @()
  foreach ($table in $script:Manifest.tables) {
    if (-not $table.views) {
      continue
    }

    $tableName = [string]$table.schemaName
    foreach ($viewName in @($table.views)) {
      $fields = Get-ViewFields -TableName $tableName
      $jump = if ($tableName -eq "com_councilworkitem") { "com_title" } else { $fields[0] }
      $view = New-CuratedView -TableName $tableName -ViewName ([string]$viewName) -Fields $fields -JumpField $jump -SortField $jump -Conditions (Get-ConditionSet -TableName $tableName -ViewName ([string]$viewName))
      $curatedViews += [ordered]@{
        table = $tableName
        name = [string]$view.name
        id = [string]$view.savedqueryid
      }
    }
  }

  $pinnedForms = @()
  $pinnedViews = @()
  foreach ($tableName in $tables) {
    $form = Get-FirstMainForm -TableName ([string]$tableName)
    if (Add-AppComponentIfMissing -AppId $appId -Components $components -ComponentKind "systemform" -ObjectId ([string]$form.formid) -Label "$tableName / $($form.name)") {
      $components = Get-AppComponents -AppId $appId
    }
    $pinnedForms += [ordered]@{ table = [string]$tableName; name = [string]$form.name; id = [string]$form.formid }

    $view = Get-FirstActiveView -TableName ([string]$tableName)
    if (Add-AppComponentIfMissing -AppId $appId -Components $components -ComponentKind "savedquery" -ObjectId ([string]$view.savedqueryid) -Label "$tableName / $($view.name)") {
      $components = Get-AppComponents -AppId $appId
    }
    $pinnedViews += [ordered]@{ table = [string]$tableName; name = [string]$view.name; id = [string]$view.savedqueryid; baseline = $true }
  }

  foreach ($view in $curatedViews) {
    if (Add-AppComponentIfMissing -AppId $appId -Components $components -ComponentKind "savedquery" -ObjectId ([string]$view.id) -Label "$($view.table) / $($view.name)") {
      $components = Get-AppComponents -AppId $appId
    }
    $pinnedViews += [ordered]@{ table = [string]$view.table; name = [string]$view.name; id = [string]$view.id; baseline = $false }
  }

  Write-Host "Publishing customizations"
  Invoke-DataverseRequest -Method POST -Path "PublishAllXml" -Body @{} | Out-Null

  $validation = Invoke-DataverseRequest -Method GET -Path "ValidateApp(AppModuleId=$appId)"
  $issues = @($validation.AppValidationResponse.ValidationIssueList)
  $formViewWarnings = @($issues | Where-Object { [string]$_.Message -match "doesn't reference a form or view" })
  if ($validation.AppValidationResponse.ValidationSuccess -ne $true -or $formViewWarnings.Count -gt 0) {
    $issueText = @($issues | ForEach-Object { "$($_.ErrorType): $($_.Message)" }) -join "; "
    throw "Model-driven app curation validation failed: $issueText"
  }

  $evidence = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    environmentUrl = [string]$script:Manifest.target.environmentUrl
    appId = $appId
    appName = [string]$script:Manifest.modelDrivenApp.displayName
    appTables = $tables
    pinnedFormCount = $pinnedForms.Count
    pinnedViewCount = $pinnedViews.Count
    curatedViewCount = $curatedViews.Count
    pinnedForms = $pinnedForms
    pinnedViews = $pinnedViews
    curatedViews = $curatedViews
    validateAppSuccess = [bool]$validation.AppValidationResponse.ValidationSuccess
    validationIssueCount = $issues.Count
    validationIssues = @($issues | ForEach-Object { [ordered]@{ errorType = $_.ErrorType; message = $_.Message; componentType = $_.ComponentType; displayName = $_.DisplayName } })
    formViewWarningsRemaining = $formViewWarnings.Count
  }
  $evidence | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 $EvidencePath

  Write-Host "Pinned forms: $($pinnedForms.Count)"
  Write-Host "Pinned views: $($pinnedViews.Count)"
  Write-Host "Curated views: $($curatedViews.Count)"
  Write-Host "ValidateApp issues: $($issues.Count)"
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
  $tables = @()
  foreach ($group in $script:Manifest.modelDrivenApp.navigationGroups) {
    $tables += @($group.tables)
  }
  $tables = @($tables | Select-Object -Unique)
  $curatedViewCount = @($script:Manifest.tables | Where-Object { $_.views } | ForEach-Object { @($_.views) }).Count
  Write-Host "DRY RUN ONLY. No tenant writes will be performed."
  Write-Host "Would pin one main form and one baseline system view for $($tables.Count) app tables."
  Write-Host "Would ensure and pin $curatedViewCount manifest-curated views."
  Write-Host "DATAVERSE_APPLY_APP_CURATION_DRY_RUN_OK"
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

Invoke-AppCuration
Write-Host "DATAVERSE_APPLY_APP_CURATION_OK"
