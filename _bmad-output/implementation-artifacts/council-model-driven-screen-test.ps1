[CmdletBinding()]
param(
  [string]$ManifestPath,
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

  Invoke-RestMethod -Method GET -Uri "$WebApiEndpoint/$Path" -Headers $headers
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

$token = Invoke-JsonCommand -FilePath "az" -Arguments @("account", "get-access-token", "--resource", $environmentUrl)
$accessToken = [string]$token.accessToken
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
$screenDefinitions = @(
  @{
    name = "source-records"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilsourcerecord"
    mustContainAll = @("Council Source Records", "Manual sample source record")
  },
  @{
    name = "proposed-work-items"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilworkitem"
    mustContainAll = @(
      "Council Work Items",
      "Review the first Council source record",
      "Approve demo Council work item",
      "Hold demo Council work item",
      "Block demo Council work item",
      "Review demo Council work item",
      "Complete demo Council work item",
      "Fail demo Council work item"
    )
  },
  @{
    name = "receipts"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilreceipt"
    mustContainAll = @(
      "Council Receipts",
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
    name = "briefs"
    url = "$environmentUrl/main.aspx?appid=$appId&pagetype=entitylist&etn=com_councilbrief"
    mustContainAll = @("Council Briefs", "Demo Minion Brief")
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
