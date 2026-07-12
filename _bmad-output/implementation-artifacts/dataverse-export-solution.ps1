[CmdletBinding()]
param(
  [string]$ManifestPath,
  [string]$OutputRoot,
  [switch]$SkipExport,
  [switch]$KeepZip
)

$ErrorActionPreference = "Stop"

if (-not $ManifestPath) {
  $ManifestPath = Join-Path $PSScriptRoot "dataverse-mvp-schema-manifest.json"
}
if (-not $OutputRoot) {
  $OutputRoot = Join-Path $PSScriptRoot "alm"
}

$manifest = Get-Content -Raw $ManifestPath | ConvertFrom-Json
$solutionName = [string]$manifest.solution.uniqueName
$environmentUrl = [string]$manifest.target.environmentUrl

$outputRootPath = if (Test-Path $OutputRoot) {
  (Resolve-Path $OutputRoot).Path
} else {
  New-Item -ItemType Directory -Force $OutputRoot | Out-Null
  (Resolve-Path $OutputRoot).Path
}

$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $outputRootPath.StartsWith($workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "OutputRoot must be inside workspace. OutputRoot=$outputRootPath Workspace=$workspaceRoot"
}

$zipDir = Join-Path $outputRootPath "exports"
$unpackDir = Join-Path $outputRootPath "unpacked\$solutionName"
$logDir = Join-Path $outputRootPath "logs"
New-Item -ItemType Directory -Force $zipDir, $unpackDir, $logDir | Out-Null

$zipPath = Join-Path $zipDir "${solutionName}_unmanaged.zip"
$unpackLogPath = Join-Path $logDir "${solutionName}_unpack.log"
$exportEvidencePath = Join-Path $outputRootPath "export-evidence.json"

function ConvertTo-WorkspaceRelativePath {
  param([AllowNull()][string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $null
  }

  $resolved = if (Test-Path $Path) { (Resolve-Path $Path).Path } else { [System.IO.Path]::GetFullPath($Path) }
  if ($resolved.StartsWith($workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return ($resolved.Substring($workspaceRoot.Length + 1) -replace '\\', '/')
  }

  return $resolved
}

if (-not $SkipExport) {
  Write-Host "Exporting unmanaged Dataverse solution: $solutionName"
  & pac solution export `
    --environment $environmentUrl `
    --name $solutionName `
    --path $zipPath `
    --overwrite
  if ($LASTEXITCODE -ne 0) {
    throw "pac solution export failed."
  }
}

if (-not (Test-Path $zipPath)) {
  throw "Solution zip not found: $zipPath"
}

Write-Host "Unpacking Dataverse solution source: $solutionName"
& pac solution unpack `
  --zipfile $zipPath `
  --folder $unpackDir `
  --packagetype Unmanaged `
  --allowWrite true `
  --allowDelete true `
  --clobber true `
  --log $unpackLogPath
if ($LASTEXITCODE -ne 0) {
  throw "pac solution unpack failed."
}

$requiredFiles = @(
  (Join-Path $unpackDir "Other\Solution.xml"),
  (Join-Path $unpackDir "Other\Customizations.xml")
)
foreach ($path in $requiredFiles) {
  if (-not (Test-Path $path)) {
    throw "Expected unpacked solution file missing: $path"
  }
}

$allFiles = Get-ChildItem -Path $unpackDir -Recurse -File
$evidence = [ordered]@{
  generatedAt = (Get-Date).ToString("o")
  environmentUrl = $environmentUrl
  solutionName = $solutionName
  unmanagedZipPath = if ($KeepZip) { ConvertTo-WorkspaceRelativePath -Path $zipPath } else { $null }
  unpackedPath = ConvertTo-WorkspaceRelativePath -Path $unpackDir
  unpackLogPath = ConvertTo-WorkspaceRelativePath -Path $unpackLogPath
  fileCount = $allFiles.Count
  containsSolutionXml = Test-Path (Join-Path $unpackDir "Other\Solution.xml")
  containsCustomizationsXml = Test-Path (Join-Path $unpackDir "Other\Customizations.xml")
  containsAppModule = ($allFiles | Where-Object { $_.FullName -match 'AppModule|appmodule|AppModules' }).Count -gt 0
  containsSiteMap = ($allFiles | Where-Object { $_.FullName -match 'SiteMap|sitemap|AppModuleSiteMap' }).Count -gt 0
}
$evidence | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $exportEvidencePath

if (-not $KeepZip -and (Test-Path $zipPath)) {
  Remove-Item -LiteralPath $zipPath -Force
}

Write-Host "Solution source files: $($allFiles.Count)"
Write-Host "Evidence: $exportEvidencePath"
Write-Host "DATAVERSE_EXPORT_SOLUTION_OK"
