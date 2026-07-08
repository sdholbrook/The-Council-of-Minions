param(
  [string]$ManifestPath = "$PSScriptRoot\dataverse-mvp-schema-manifest.json",
  [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
)

$ErrorActionPreference = "Stop"

function Add-Issue {
  param(
    [Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$Issues,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $Issues.Add($Message) | Out-Null
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Manifest not found: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$issues = [System.Collections.Generic.List[string]]::new()

if (-not $manifest.target.environmentUrl) {
  Add-Issue $issues "Missing target.environmentUrl."
}
if (-not $manifest.target.environmentUniqueName) {
  Add-Issue $issues "Missing target.environmentUniqueName."
}
if (-not $manifest.target.environmentId) {
  Add-Issue $issues "Missing target.environmentId."
}
if (-not $manifest.target.organizationId) {
  Add-Issue $issues "Missing target.organizationId."
}
if (-not $manifest.target.webApiEndpoint) {
  Add-Issue $issues "Missing target.webApiEndpoint."
}
if (-not $manifest.target.discoveryEndpoint) {
  Add-Issue $issues "Missing target.discoveryEndpoint."
}
if (-not $manifest.solution.publisherPrefix) {
  Add-Issue $issues "Missing solution.publisherPrefix."
}

$choiceNames = @{}
foreach ($choice in @($manifest.choices)) {
  if (-not $choice.name) {
    Add-Issue $issues "Choice entry is missing name."
    continue
  }
  if ($choiceNames.ContainsKey($choice.name)) {
    Add-Issue $issues "Duplicate choice name: $($choice.name)."
  }
  $choiceNames[$choice.name] = $true
  if (-not $choice.values -or $choice.values.Count -eq 0) {
    Add-Issue $issues "Choice $($choice.name) has no values."
  }
}

$tables = @($manifest.tables)
if ($tables.Count -eq 0) {
  Add-Issue $issues "Manifest has no tables."
}

$tableNames = @{}
foreach ($table in $tables) {
  if (-not $table.schemaName) {
    Add-Issue $issues "Table entry is missing schemaName."
    continue
  }
  if ($tableNames.ContainsKey($table.schemaName)) {
    Add-Issue $issues "Duplicate table schemaName: $($table.schemaName)."
  }
  $tableNames[$table.schemaName] = $true
}

$contractRoot = Join-Path $ProjectRoot "_bmad-output\planning-artifacts"
foreach ($table in $tables) {
  if (-not $table.displayName) {
    Add-Issue $issues "Table $($table.schemaName) is missing displayName."
  }
  if (-not $table.primaryNameColumn) {
    Add-Issue $issues "Table $($table.schemaName) is missing primaryNameColumn."
  }
  if (-not $table.contract) {
    Add-Issue $issues "Table $($table.schemaName) is missing contract reference."
  } else {
    $contractMatches = Get-ChildItem -LiteralPath $contractRoot -Recurse -File -Filter $table.contract -ErrorAction SilentlyContinue
    if (-not $contractMatches) {
      Add-Issue $issues "Table $($table.schemaName) references missing contract file: $($table.contract)."
    }
  }

  $columns = @($table.columns)
  if ($columns.Count -eq 0) {
    Add-Issue $issues "Table $($table.schemaName) has no columns."
    continue
  }

  $columnNames = @{}
  foreach ($column in $columns) {
    if (-not $column.name) {
      Add-Issue $issues "Table $($table.schemaName) has a column without name."
      continue
    }
    if ($columnNames.ContainsKey($column.name)) {
      Add-Issue $issues "Table $($table.schemaName) has duplicate column: $($column.name)."
    }
    $columnNames[$column.name] = $true

    if (-not $column.type) {
      Add-Issue $issues "Column $($table.schemaName).$($column.name) is missing type."
    }

    if ($column.type -eq "choice") {
      if (-not $column.choice -and -not $column.values) {
        Add-Issue $issues "Choice column $($table.schemaName).$($column.name) has neither choice nor inline values."
      }
      if ($column.choice -and -not $choiceNames.ContainsKey($column.choice)) {
        Add-Issue $issues "Choice column $($table.schemaName).$($column.name) references unknown choice: $($column.choice)."
      }
      if ($column.values -and $column.values.Count -eq 0) {
        Add-Issue $issues "Choice column $($table.schemaName).$($column.name) has empty inline values."
      }
    }

    if ($column.type -eq "lookup") {
      if (-not $column.target) {
        Add-Issue $issues "Lookup column $($table.schemaName).$($column.name) is missing target."
      } elseif (-not $tableNames.ContainsKey($column.target)) {
        Add-Issue $issues "Lookup column $($table.schemaName).$($column.name) references unknown table: $($column.target)."
      }
    }
  }

  if ($table.primaryNameColumn -and -not $columnNames.ContainsKey($table.primaryNameColumn)) {
    Add-Issue $issues "Table $($table.schemaName) primaryNameColumn $($table.primaryNameColumn) is not in columns."
  }
}

foreach ($group in @($manifest.modelDrivenApp.navigationGroups)) {
  foreach ($tableRef in @($group.tables)) {
    if (-not $tableNames.ContainsKey($tableRef)) {
      Add-Issue $issues "Model-driven app group $($group.name) references unknown table: $tableRef."
    }
  }
}

if ($issues.Count -gt 0) {
  Write-Host "Dataverse manifest validation failed:"
  foreach ($issue in $issues) {
    Write-Host "- $issue"
  }
  exit 1
}

Write-Host "Dataverse manifest validation succeeded."
Write-Host "Tables: $($tables.Count)"
Write-Host "Choices: $(@($manifest.choices).Count)"
Write-Host "Model-driven app: $($manifest.modelDrivenApp.displayName)"
