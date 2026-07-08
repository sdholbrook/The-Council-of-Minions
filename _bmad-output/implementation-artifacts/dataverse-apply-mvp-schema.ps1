param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$DecisionPath = "$PSScriptRoot\tenant-decision-packet.json",
  [switch]$ExecuteWrites,
  [switch]$SeedSampleRows
)

$ErrorActionPreference = "Stop"

function New-Label {
  param([Parameter(Mandatory = $true)][string]$Text)

  @{
    "@odata.type" = "Microsoft.Dynamics.CRM.Label"
    LocalizedLabels = @(
      @{
        "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
        Label = $Text
        LanguageCode = 1033
        IsManaged = $false
      }
    )
  }
}

function New-RequiredLevel {
  param([bool]$Required)

  @{
    Value = if ($Required) { "ApplicationRequired" } else { "None" }
    CanBeChanged = $true
    ManagedPropertyLogicalName = "canmodifyrequirementlevelsettings"
  }
}

function ConvertTo-DisplayName {
  param([Parameter(Mandatory = $true)][string]$Name)

  (($Name -replace '^com_', '') -split '_' | ForEach-Object {
    if ($_.Length -eq 0) { return $_ }
    $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
  }) -join ' '
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
    $headers["MSCRM.SolutionUniqueName"] = $script:Manifest.solution.uniqueName
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

function Test-EntityExists {
  param([Parameter(Mandatory = $true)][string]$LogicalName)

  $result = Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName" -AllowNotFound
  return $null -ne $result
}

function Test-AttributeExists {
  param(
    [Parameter(Mandatory = $true)][string]$EntityLogicalName,
    [Parameter(Mandatory = $true)][string]$AttributeLogicalName
  )

  $result = Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='$EntityLogicalName')/Attributes(LogicalName='$AttributeLogicalName')?`$select=LogicalName" -AllowNotFound
  return $null -ne $result
}

function Get-EntityDefinition {
  param([Parameter(Mandatory = $true)][string]$LogicalName)

  Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName,EntitySetName,PrimaryIdAttribute"
}

function Ensure-Publisher {
  $publisher = $script:Manifest.solution
  $query = "publishers?`$select=publisherid,uniquename,customizationprefix&`$filter=uniquename eq '$($publisher.publisherUniqueName)'"
  $existing = Invoke-DataverseRequest -Method GET -Path $query
  if ($existing.value.Count -gt 0) {
    Write-Host "Publisher exists: $($publisher.publisherUniqueName)"
    return $existing.value[0].publisherid
  }

  Write-Host "Creating publisher: $($publisher.publisherUniqueName)"
  $body = @{
    friendlyname = $publisher.publisherDisplayName
    uniquename = $publisher.publisherUniqueName
    customizationprefix = $publisher.publisherPrefix
  }
  $created = Invoke-DataverseRequest -Method POST -Path "publishers" -Body $body
  if ($created.publisherid) {
    return $created.publisherid
  }

  $existing = Invoke-DataverseRequest -Method GET -Path $query
  return $existing.value[0].publisherid
}

function Ensure-Solution {
  param([Parameter(Mandatory = $true)][string]$PublisherId)

  $solution = $script:Manifest.solution
  $query = "solutions?`$select=solutionid,uniquename&`$filter=uniquename eq '$($solution.uniqueName)'"
  $existing = Invoke-DataverseRequest -Method GET -Path $query
  if ($existing.value.Count -gt 0) {
    Write-Host "Solution exists: $($solution.uniqueName)"
    return
  }

  Write-Host "Creating solution: $($solution.uniqueName)"
  $body = @{
    friendlyname = $solution.displayName
    uniquename = $solution.uniqueName
    version = $solution.version
    "publisherid@odata.bind" = "/publishers($PublisherId)"
  }
  Invoke-DataverseRequest -Method POST -Path "solutions" -Body $body | Out-Null
}

function Ensure-GlobalChoice {
  param(
    [Parameter(Mandatory = $true)]$Choice,
    [int]$ChoiceIndex
  )

  $path = "GlobalOptionSetDefinitions(Name='$($Choice.name)')?`$select=Name,MetadataId"
  $existing = Invoke-DataverseRequest -Method GET -Path $path -AllowNotFound
  if ($existing) {
    Write-Host "Choice exists: $($Choice.name)"
    return
  }

  Write-Host "Creating choice: $($Choice.name)"
  $baseValue = 950000000 + ($ChoiceIndex * 1000)
  $options = @()
  for ($i = 0; $i -lt $Choice.values.Count; $i++) {
    $options += @{
      Value = $baseValue + $i
      Label = New-Label -Text ([string]$Choice.values[$i])
    }
  }

  $body = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
    Name = $Choice.name
    DisplayName = New-Label -Text $Choice.displayName
    Description = New-Label -Text "Council of Minions global choice: $($Choice.displayName)"
    OptionSetType = "Picklist"
    Options = $options
  }

  Invoke-DataverseRequest -Method POST -Path "GlobalOptionSetDefinitions" -Body $body -IncludeSolutionHeader | Out-Null
}

function Ensure-Table {
  param([Parameter(Mandatory = $true)]$Table)

  if (Test-EntityExists -LogicalName $Table.schemaName) {
    Write-Host "Table exists: $($Table.schemaName)"
    return
  }

  Write-Host "Creating table: $($Table.schemaName)"
  $primaryName = [string]$Table.primaryNameColumn
  $primaryColumn = $Table.columns | Where-Object { $_.name -eq $primaryName } | Select-Object -First 1
  if (-not $primaryColumn) {
    throw "Primary column $primaryName not found for $($Table.schemaName)."
  }

  $body = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = $Table.schemaName
    DisplayName = New-Label -Text $Table.displayName
    DisplayCollectionName = New-Label -Text "$($Table.displayName)s"
    Description = New-Label -Text "Council of Minions MVP table backed by $($Table.contract)."
    OwnershipType = "UserOwned"
    IsActivity = $false
    HasActivities = $false
    HasNotes = $true
    Attributes = @(
      @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        AttributeType = "String"
        AttributeTypeName = @{ Value = "StringType" }
        SchemaName = $primaryName
        DisplayName = New-Label -Text (ConvertTo-DisplayName -Name $primaryName)
        Description = New-Label -Text "Primary name for $($Table.displayName)."
        IsPrimaryName = $true
        RequiredLevel = New-RequiredLevel -Required ([bool]$primaryColumn.required)
        FormatName = @{ Value = "Text" }
        MaxLength = 200
      }
    )
  }

  Invoke-DataverseRequest -Method POST -Path "EntityDefinitions" -Body $body -IncludeSolutionHeader | Out-Null
}

function Get-GlobalChoiceMetadataId {
  param([Parameter(Mandatory = $true)][string]$ChoiceName)

  $path = "GlobalOptionSetDefinitions(Name='$ChoiceName')?`$select=Name,MetadataId"
  $choice = Invoke-DataverseRequest -Method GET -Path $path
  return $choice.MetadataId
}

function New-ColumnBody {
  param(
    [Parameter(Mandatory = $true)]$Column,
    [int]$LocalChoiceIndex
  )

  $displayName = ConvertTo-DisplayName -Name ([string]$Column.name)
  $required = [bool]$Column.required
  $common = @{
    SchemaName = [string]$Column.name
    DisplayName = New-Label -Text $displayName
    Description = New-Label -Text "Council field: $displayName."
    RequiredLevel = New-RequiredLevel -Required $required
  }

  switch ([string]$Column.type) {
    "text" {
      return $common + @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        AttributeType = "String"
        AttributeTypeName = @{ Value = "StringType" }
        FormatName = @{ Value = "Text" }
        MaxLength = 850
      }
    }
    "url" {
      return $common + @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        AttributeType = "String"
        AttributeTypeName = @{ Value = "StringType" }
        FormatName = @{ Value = "Url" }
        MaxLength = 850
      }
    }
    "multiline" {
      return $common + @{
        "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        AttributeType = "Memo"
        AttributeTypeName = @{ Value = "MemoType" }
        Format = "TextArea"
        ImeMode = "Disabled"
        MaxLength = 4000
        IsLocalizable = $false
      }
    }
    "datetime" {
      return $common + @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        AttributeType = "DateTime"
        AttributeTypeName = @{ Value = "DateTimeType" }
        Format = "DateAndTime"
        DateTimeBehavior = @{ Value = "UserLocal" }
      }
    }
    "decimal" {
      return $common + @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
        AttributeType = "Decimal"
        AttributeTypeName = @{ Value = "DecimalType" }
        MaxValue = if ($null -ne $Column.max) { [decimal]$Column.max } else { [decimal]1000000000 }
        MinValue = if ($null -ne $Column.min) { [decimal]$Column.min } else { [decimal]-1000000000 }
        Precision = 4
      }
    }
    "boolean" {
      return $common + @{
        "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
        AttributeType = "Boolean"
        AttributeTypeName = @{ Value = "BooleanType" }
        DefaultValue = if ($null -ne $Column.default) { [bool]$Column.default } else { $false }
        OptionSet = @{
          OptionSetType = "Boolean"
          TrueOption = @{ Value = 1; Label = New-Label -Text "Yes" }
          FalseOption = @{ Value = 0; Label = New-Label -Text "No" }
        }
      }
    }
    "choice" {
      if ($Column.choice) {
        $choiceId = Get-GlobalChoiceMetadataId -ChoiceName ([string]$Column.choice)
        return $common + @{
          "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
          AttributeType = "Picklist"
          AttributeTypeName = @{ Value = "PicklistType" }
          SourceTypeMask = 0
          "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($choiceId)"
        }
      }

      $baseValue = 960000000 + ($LocalChoiceIndex * 1000)
      $options = @()
      for ($i = 0; $i -lt $Column.values.Count; $i++) {
        $options += @{
          Value = $baseValue + $i
          Label = New-Label -Text ([string]$Column.values[$i])
        }
      }

      return $common + @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        AttributeType = "Picklist"
        AttributeTypeName = @{ Value = "PicklistType" }
        SourceTypeMask = 0
        OptionSet = @{
          "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
          IsGlobal = $false
          OptionSetType = "Picklist"
          Options = $options
        }
      }
    }
    default {
      throw "Unsupported column type '$($Column.type)' for $($Column.name)."
    }
  }
}

function Ensure-Columns {
  $localChoiceIndex = 0
  foreach ($table in $script:Manifest.tables) {
    foreach ($column in $table.columns) {
      if ($column.name -eq $table.primaryNameColumn -or $column.type -eq "lookup") {
        continue
      }

      if (Test-AttributeExists -EntityLogicalName $table.schemaName -AttributeLogicalName $column.name) {
        Write-Host "Column exists: $($table.schemaName).$($column.name)"
        continue
      }

      Write-Host "Creating column: $($table.schemaName).$($column.name)"
      $body = New-ColumnBody -Column $column -LocalChoiceIndex $localChoiceIndex
      if ($column.type -eq "choice" -and $column.values) {
        $localChoiceIndex++
      }
      $path = "EntityDefinitions(LogicalName='$($table.schemaName)')/Attributes"
      Invoke-DataverseRequest -Method POST -Path $path -Body $body -IncludeSolutionHeader | Out-Null
    }
  }
}

function Ensure-Relationship {
  param(
    [Parameter(Mandatory = $true)]$Table,
    [Parameter(Mandatory = $true)]$Column
  )

  if (Test-AttributeExists -EntityLogicalName $Table.schemaName -AttributeLogicalName $Column.name) {
    Write-Host "Lookup exists: $($Table.schemaName).$($Column.name)"
    return
  }

  $target = [string]$Column.target
  $targetDef = Get-EntityDefinition -LogicalName $target
  $schemaName = "com_$($target -replace '^com_council','')_$($Table.schemaName -replace '^com_council','')_$($Column.name -replace '^com_','')"
  if ($schemaName.Length -gt 95) {
    $schemaName = $schemaName.Substring(0, 95)
  }

  Write-Host "Creating lookup: $($Table.schemaName).$($Column.name) -> $target"
  $displayName = ConvertTo-DisplayName -Name ([string]$Column.name)
  $body = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
    SchemaName = $schemaName
    ReferencedEntity = $target
    ReferencedAttribute = $targetDef.PrimaryIdAttribute
    ReferencingEntity = [string]$Table.schemaName
    ReferencedEntityNavigationPropertyName = "${schemaName}_referenced"
    ReferencingEntityNavigationPropertyName = [string]$Column.name
    AssociatedMenuConfiguration = @{
      Behavior = "UseCollectionName"
      Group = "Details"
      Label = New-Label -Text $displayName
      Order = 10000
    }
    CascadeConfiguration = @{
      Assign = "NoCascade"
      Delete = "Restrict"
      Merge = "NoCascade"
      Reparent = "NoCascade"
      Share = "NoCascade"
      Unshare = "NoCascade"
    }
    Lookup = @{
      "@odata.type" = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
      AttributeType = "Lookup"
      AttributeTypeName = @{ Value = "LookupType" }
      SchemaName = [string]$Column.name
      DisplayName = New-Label -Text $displayName
      Description = New-Label -Text "Council lookup to $target."
      RequiredLevel = New-RequiredLevel -Required ([bool]$Column.required)
    }
  }

  Invoke-DataverseRequest -Method POST -Path "RelationshipDefinitions" -Body $body -IncludeSolutionHeader | Out-Null
}

function Ensure-Relationships {
  foreach ($table in $script:Manifest.tables) {
    foreach ($column in ($table.columns | Where-Object { $_.type -eq "lookup" })) {
      Ensure-Relationship -Table $table -Column $column
    }
  }
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

function Invoke-PublishAll {
  Write-Host "Publishing customizations"
  Invoke-DataverseRequest -Method POST -Path "PublishAllXml" -Body @{} | Out-Null
}

function Ensure-ModelDrivenApp {
  if ($script:Manifest.modelDrivenApp -eq $null) {
    return
  }

  $appName = [string]$script:Manifest.modelDrivenApp.displayName
  $queryName = $appName.Replace("'", "''")
  $existing = Invoke-DataverseRequest -Method GET -Path "appmodules?`$select=appmoduleid,name&`$filter=name eq '$queryName'"
  if ($existing.value.Count -gt 0) {
    Write-Host "Model-driven app exists: $appName"
    return
  }

  Write-Host "Creating model-driven app: $appName"
  $description = "Council of Minions MVP queue for source records, proposed work items, receipts, knowledge, and governance."
  $output = & pac model create --name $appName --description $description --solution $script:Manifest.solution.uniqueName --publish 2>&1
  $exitCode = $LASTEXITCODE
  $output | ForEach-Object { Write-Host $_ }
  if ($exitCode -ne 0) {
    throw "Model-driven app creation failed."
  }
}

function New-SampleRows {
  $sourceDef = Get-EntityDefinition -LogicalName "com_councilsourcerecord"
  $workDef = Get-EntityDefinition -LogicalName "com_councilworkitem"
  $sourceSet = $sourceDef.EntitySetName
  $workSet = $workDef.EntitySetName
  $sourceExternalId = "manual-sample-" + (Get-Date).ToString("yyyyMMdd-HHmmss")

  Write-Host "Creating sample Source Record"
  $sourceBody = @{
    com_name = "Manual sample source record"
    com_council_source_record_id = $sourceExternalId
    com_source_system = Get-GlobalChoiceValue -ChoiceName "com_sourcesystem" -Label "manual"
    com_source_kind = Get-GlobalChoiceValue -ChoiceName "com_sourcekind" -Label "manual_note"
    com_source_object_ref = $sourceExternalId
    com_captured_at = (Get-Date).ToUniversalTime().ToString("o")
    com_captured_by = "Doug"
    com_extraction_status = Get-GlobalChoiceValue -ChoiceName "com_extractionstatus" -Label "new"
    com_data_boundary_policy = Get-GlobalChoiceValue -ChoiceName "com_databoundarypolicy" -Label "link_only"
  }
  $createdSource = Invoke-DataverseRequest -Method POST -Path $sourceSet -Body $sourceBody
  $sourceId = $createdSource."com_councilsourcerecordid"

  if (-not $sourceId) {
    $lookup = Invoke-DataverseRequest -Method GET -Path "${sourceSet}?`$select=com_councilsourcerecordid&`$filter=com_council_source_record_id eq '$sourceExternalId'"
    $sourceId = $lookup.value[0].com_councilsourcerecordid
  }

  Write-Host "Creating sample proposed Work Item"
  $workBody = @{
    com_title = "Review the first Council source record"
    com_council_work_item_id = "work-sample-" + (Get-Date).ToString("yyyyMMdd-HHmmss")
    com_type = Get-GlobalChoiceValue -ChoiceName "com_workitemtype" -Label "request"
    com_summary = "First tenant-seeded work item proving the Council intake path."
    com_state_group = Get-GlobalChoiceValue -ChoiceName "com_workitemstategroup" -Label "proposed"
    com_risk_class = Get-GlobalChoiceValue -ChoiceName "com_riskclass" -Label "none"
    "com_primary_source_record@odata.bind" = "/$sourceSet($sourceId)"
    com_rationale = "Seed row created by the guarded Council MVP Dataverse apply script."
    com_approval_required = $true
    com_semantic_contract_version = "2026-07-08"
  }
  Invoke-DataverseRequest -Method POST -Path $workSet -Body $workBody | Out-Null

  Write-Host "Seed rows created: $sourceExternalId"
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
  Write-Host "Would create/update solution $($script:Manifest.solution.uniqueName), $($script:Manifest.choices.Count) choices, $($script:Manifest.tables.Count) tables, non-lookup columns, lookups, and publish customizations."
  if ($SeedSampleRows) {
    Write-Host "Would also seed one sample Source Record and one proposed Work Item."
  }
  Write-Host "DATAVERSE_APPLY_MVP_SCHEMA_DRY_RUN_OK"
  exit 0
}

if ($decision.decisions.dataverseMvpOperationalStore.value -ne "approved") {
  throw "Dataverse MVP operational store is not approved in the tenant decision packet."
}
if ($decision.decisions.dataverseSandboxWrites.value -ne "allowed_after_readonly_preflight") {
  throw "Dataverse writes are not approved in the tenant decision packet."
}
if ($decision.decisions.sourceBodyPolicy.value -ne "link_only") {
  throw "The live seed path only supports link_only source body policy."
}

powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\tenant-decision-packet-validate.ps1" -RequireComplete
powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\dataverse-preflight-readonly.ps1"

$script:WebApiEndpoint = [string]$script:Manifest.target.webApiEndpoint
$script:AccessToken = Get-AccessToken -EnvironmentUrl ([string]$script:Manifest.target.environmentUrl)

$publisherId = Ensure-Publisher
Ensure-Solution -PublisherId $publisherId

$choiceIndex = 0
foreach ($choice in $script:Manifest.choices) {
  Ensure-GlobalChoice -Choice $choice -ChoiceIndex $choiceIndex
  $choiceIndex++
}

foreach ($table in $script:Manifest.tables) {
  Ensure-Table -Table $table
}

Ensure-Columns
Ensure-Relationships
Invoke-PublishAll
Ensure-ModelDrivenApp

if ($SeedSampleRows) {
  New-SampleRows
}

Write-Host "DATAVERSE_APPLY_MVP_SCHEMA_OK"
