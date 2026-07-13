[CmdletBinding()]
param(
  [string]$ProjectRoot,
  [switch]$RequireScreenEvidence
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
  $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Invoke-ValidationStep {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Script
  )

  Write-Host ""
  Write-Host "== $Name"
  & $Script
}

Push-Location $ProjectRoot
try {
  Invoke-ValidationStep "Git whitespace check" {
    git diff --check
    if ($LASTEXITCODE -ne 0) {
      throw "git diff --check failed."
    }
  }

  Invoke-ValidationStep "BMAD config resolver" {
    $env:PYTHONIOENCODING = "utf-8"
    uv run --python 3.11 _bmad/scripts/resolve_config.py --project-root $ProjectRoot | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "BMAD config resolver failed."
    }
  }

  Invoke-ValidationStep "Dataverse manifest validation" {
    powershell -NoProfile -ExecutionPolicy Bypass -File "_bmad-output\implementation-artifacts\dataverse-manifest-validate.ps1"
    if ($LASTEXITCODE -ne 0) {
      throw "Dataverse manifest validation failed."
    }
  }

  Invoke-ValidationStep "Tenant decision packet validation" {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File "_bmad-output\implementation-artifacts\tenant-decision-packet-validate.ps1"
    if ($LASTEXITCODE -ne 0) {
      throw "Tenant decision packet validation failed."
    }
    $output | ForEach-Object { Write-Host $_ }
    if (($output -join "`n") -notmatch "TENANT_DECISION_PACKET_VALIDATE_OK") {
      throw "Tenant decision packet validation did not print success marker."
    }
  }

  Invoke-ValidationStep "Manual Source Record slice validation" {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File "_bmad-output\implementation-artifacts\manual-source-record-slice-validate.ps1"
    if ($LASTEXITCODE -ne 0) {
      throw "Manual Source Record slice validation failed."
    }
    $output | ForEach-Object { Write-Host $_ }
    if (($output -join "`n") -notmatch "MANUAL_SOURCE_RECORD_SLICE_VALIDATE_OK") {
      throw "Manual Source Record slice validation did not print success marker."
    }
  }

  Invoke-ValidationStep "Outlook Source Reference slice validation" {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File "_bmad-output\implementation-artifacts\outlook-source-reference-slice-validate.ps1"
    if ($LASTEXITCODE -ne 0) {
      throw "Outlook Source Reference slice validation failed."
    }
    $output | ForEach-Object { Write-Host $_ }
    if (($output -join "`n") -notmatch "OUTLOOK_SOURCE_REFERENCE_SLICE_VALIDATE_OK") {
      throw "Outlook Source Reference slice validation did not print success marker."
    }
  }

  Invoke-ValidationStep "Proposed Work Item extraction slice validation" {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File "_bmad-output\implementation-artifacts\proposed-work-item-extraction-slice-validate.ps1"
    if ($LASTEXITCODE -ne 0) {
      throw "Proposed Work Item extraction slice validation failed."
    }
    $output | ForEach-Object { Write-Host $_ }
    if (($output -join "`n") -notmatch "PROPOSED_WORK_ITEM_EXTRACTION_SLICE_VALIDATE_OK") {
      throw "Proposed Work Item extraction slice validation did not print success marker."
    }
  }

  Invoke-ValidationStep "Zero/multi-item extraction slice validation" {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File "_bmad-output\implementation-artifacts\zero-multi-item-extraction-slice-validate.ps1"
    $output | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
      throw "Zero/multi-item extraction slice validation failed."
    }
    if (($output -join "`n") -notmatch "ZERO_MULTI_ITEM_EXTRACTION_SLICE_VALIDATE_OK") {
      throw "Zero/multi-item extraction slice validation did not print success marker."
    }
  }

  Invoke-ValidationStep "Dataverse deployment dry run" {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File "_bmad-output\implementation-artifacts\dataverse-deployment-plan.ps1"
    if ($LASTEXITCODE -ne 0) {
      throw "Dataverse deployment dry run failed."
    }
    $output | ForEach-Object { Write-Host $_ }
    if (($output -join "`n") -notmatch "DRY RUN ONLY") {
      throw "Deployment plan did not prove dry-run mode."
    }
  }

  Invoke-ValidationStep "Dataverse ALM export source check" {
    $almRoot = "_bmad-output\implementation-artifacts\alm"
    $solutionRoot = Join-Path $almRoot "unpacked\CouncilOfMinionsMVP"
    $evidencePath = Join-Path $almRoot "export-evidence.json"
    $solutionXml = Join-Path $solutionRoot "Other\Solution.xml"
    $customizationsXml = Join-Path $solutionRoot "Other\Customizations.xml"
    $appModuleXml = Join-Path $solutionRoot "AppModules\council_queue_61fd2b5e\AppModule.xml"
    $siteMapXml = Join-Path $solutionRoot "AppModuleSiteMaps\council_queue_61fd2b5e\AppModuleSiteMap.xml"

    foreach ($path in @($evidencePath, $solutionXml, $customizationsXml, $appModuleXml, $siteMapXml)) {
      if (-not (Test-Path $path)) {
        throw "Missing ALM export artifact: $path"
      }
    }

    $evidence = Get-Content -Raw $evidencePath | ConvertFrom-Json
    if ($evidence.solutionName -ne "CouncilOfMinionsMVP") {
      throw "ALM evidence solutionName mismatch: $($evidence.solutionName)"
    }
    if ($evidence.fileCount -lt 216) {
      throw "ALM evidence file count unexpectedly low: $($evidence.fileCount)"
    }
    foreach ($flag in @("containsSolutionXml", "containsCustomizationsXml", "containsAppModule", "containsSiteMap")) {
      if ($evidence.$flag -ne $true) {
        throw "ALM evidence flag is not true: $flag"
      }
    }

    $entityCount = @(Get-ChildItem (Join-Path $solutionRoot "Entities") -Directory -Filter "com_council*").Count
    if ($entityCount -ne 14) {
      throw "Expected 14 Council entity folders in unpacked solution, found $entityCount."
    }

    $optionSetCount = @(Get-ChildItem (Join-Path $solutionRoot "OptionSets") -File -Filter "com_*.xml").Count
    if ($optionSetCount -ne 15) {
      throw "Expected 15 Council option set files in unpacked solution, found $optionSetCount."
    }

    $siteMapText = Get-Content -Raw $siteMapXml
    foreach ($marker in @("group_intake", "group_work", "group_brief", "group_knowledge", "group_governance", "subarea_com_councilsourcerecord", "subarea_com_councilworkitem")) {
      if ($siteMapText -notmatch [regex]::Escape($marker)) {
        throw "AppModuleSiteMap missing marker: $marker"
      }
    }

    $appModuleText = Get-Content -Raw $appModuleXml
    foreach ($marker in @('AppModuleComponent type="26"', 'AppModuleComponent type="60"')) {
      if ($appModuleText -notmatch [regex]::Escape($marker)) {
        throw "AppModule missing form/view component marker: $marker"
      }
    }

    foreach ($viewName in @("New Source Records", "Proposed Work Items", "Needs Human Approval", "Recent Receipts", "Memory Receipts")) {
      $matches = @(Get-ChildItem (Join-Path $solutionRoot "Entities") -Recurse -File -Filter "*.xml" | Where-Object {
          (Get-Content -Raw -LiteralPath $_.FullName) -match [regex]::Escape($viewName)
        })
      if ($matches.Count -lt 1) {
        throw "Unpacked solution missing curated view XML marker: $viewName"
      }
    }

    Write-Host "Dataverse ALM export source OK."
  }

  Invoke-ValidationStep "Receipt-backed state transition evidence check" {
    $scriptPath = "_bmad-output\implementation-artifacts\dataverse-apply-state-transition-demo.ps1"
    $evidencePath = "_bmad-output\implementation-artifacts\state-transition-demo-evidence.json"
    if (-not (Test-Path $scriptPath)) {
      throw "Missing state transition demo script: $scriptPath"
    }
    if (-not (Test-Path $evidencePath)) {
      throw "Missing state transition evidence: $evidencePath"
    }

    $dryRun = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath
    if ($LASTEXITCODE -ne 0) {
      throw "State transition demo dry run failed."
    }
    if (($dryRun -join "`n") -notmatch "DATAVERSE_APPLY_STATE_TRANSITION_DEMO_DRY_RUN_OK") {
      throw "State transition demo dry run did not print success marker."
    }

    $evidence = Get-Content -Raw $evidencePath | ConvertFrom-Json
    if ($evidence.environmentUrl -ne "https://sdhdev.crm.dynamics.com") {
      throw "State transition evidence environment mismatch: $($evidence.environmentUrl)"
    }
    if ($evidence.workItemCount -ne 6) {
      throw "Expected 6 state transition demo Work Items, found $($evidence.workItemCount)."
    }
    if ($evidence.receiptCount -ne 12) {
      throw "Expected 12 state transition demo Receipts, found $($evidence.receiptCount)."
    }
    foreach ($state in @("approved", "held", "blocked", "in_review", "completed", "failed")) {
      if (@($evidence.stateGroups) -notcontains $state) {
        throw "State transition evidence missing state: $state"
      }
    }
    if ($evidence.noOutboundAction -ne $true) {
      throw "State transition evidence must assert noOutboundAction."
    }

    Write-Host "Receipt-backed state transition evidence OK."
  }

  Invoke-ValidationStep "Model-driven app form/view curation evidence check" {
    $scriptPath = "_bmad-output\implementation-artifacts\dataverse-apply-app-curation.ps1"
    $evidencePath = "_bmad-output\implementation-artifacts\app-curation-evidence.json"
    if (-not (Test-Path $scriptPath)) {
      throw "Missing app curation script: $scriptPath"
    }
    if (-not (Test-Path $evidencePath)) {
      throw "Missing app curation evidence: $evidencePath"
    }

    $dryRun = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath
    if ($LASTEXITCODE -ne 0) {
      throw "App curation dry run failed."
    }
    if (($dryRun -join "`n") -notmatch "DATAVERSE_APPLY_APP_CURATION_DRY_RUN_OK") {
      throw "App curation dry run did not print success marker."
    }

    $evidence = Get-Content -Raw $evidencePath | ConvertFrom-Json
    if ($evidence.environmentUrl -ne "https://sdhdev.crm.dynamics.com") {
      throw "App curation evidence environment mismatch: $($evidence.environmentUrl)"
    }
    if ($evidence.appName -ne "Council Queue") {
      throw "App curation evidence appName mismatch: $($evidence.appName)"
    }
    if (@($evidence.appTables).Count -ne 12) {
      throw "Expected 12 app tables in app curation evidence, found $(@($evidence.appTables).Count)."
    }
    if ($evidence.pinnedFormCount -ne 12) {
      throw "Expected 12 pinned forms, found $($evidence.pinnedFormCount)."
    }
    if ($evidence.pinnedViewCount -lt 30) {
      throw "Expected at least 30 pinned views, found $($evidence.pinnedViewCount)."
    }
    if ($evidence.curatedViewCount -ne 18) {
      throw "Expected 18 curated views, found $($evidence.curatedViewCount)."
    }
    if ($evidence.publishedCuratedViewComponentCount -ne $evidence.curatedViewCount) {
      throw "Published curated view component count does not match curated view count: $($evidence.publishedCuratedViewComponentCount) / $($evidence.curatedViewCount)."
    }
    foreach ($view in @($evidence.curatedViews)) {
      $publishedMatches = @($evidence.publishedCuratedViewComponents | Where-Object { $_.table -eq $view.table -and $_.name -eq $view.name -and $_.id -eq $view.id })
      if ($publishedMatches.Count -ne 1) {
        throw "Published app component evidence missing or duplicated for curated view: $($view.table) / $($view.name)"
      }
    }
    if ($evidence.validateAppSuccess -ne $true) {
      throw "App curation evidence must have validateAppSuccess=true."
    }
    if ($evidence.formViewWarningsRemaining -ne 0) {
      throw "App curation evidence still has form/view warnings: $($evidence.formViewWarningsRemaining)."
    }
    foreach ($viewName in @("New Source Records", "Proposed Work Items", "Needs Human Approval", "Failed Needs Review", "Recent Receipts", "Memory Receipts")) {
      if (@($evidence.curatedViews.name) -notcontains $viewName) {
        throw "App curation evidence missing curated view: $viewName"
      }
    }

    Write-Host "Model-driven app form/view curation evidence OK."
  }

  Invoke-ValidationStep "Epics placeholder check" {
    rg -n "\{\{|\}\}" "_bmad-output\planning-artifacts\epics.md"
    if ($LASTEXITCODE -eq 0) {
      throw "Placeholder tokens remain in epics.md."
    }
    if ($LASTEXITCODE -ne 1) {
      throw "Placeholder search failed."
    }
    Write-Host "No epics placeholders found."
  }

  Invoke-ValidationStep "Sprint status YAML check" {
    $path = "_bmad-output\implementation-artifacts\sprint-status.yaml"
    $lines = Get-Content $path
    $statusLines = $lines | Where-Object { $_ -match '^  [a-z0-9-]+: (backlog|ready-for-dev|in-progress|review|done|optional)$' }
    $epics = $statusLines | Where-Object { $_ -match '^  epic-[0-9]+: (backlog|in-progress|done)$' }
    $stories = $statusLines | Where-Object { $_ -match '^  [0-9]+-[0-9]+-' }
    $retrospectives = $statusLines | Where-Object { $_ -match '^  epic-[0-9]+-retrospective: (optional|done)$' }
    $invalid = $lines | Where-Object { $_ -match '^  [a-z0-9-]+: ' -and $_ -notmatch '^  [a-z0-9-]+: (backlog|ready-for-dev|in-progress|review|done|optional)$' }

    if ($epics.Count -ne 5) {
      throw "Expected 5 epics in sprint status, found $($epics.Count)."
    }
    if ($stories.Count -ne 25) {
      throw "Expected 25 stories in sprint status, found $($stories.Count)."
    }
    if ($retrospectives.Count -ne 5) {
      throw "Expected 5 retrospectives in sprint status, found $($retrospectives.Count)."
    }
    if ($invalid) {
      $invalid | ForEach-Object { Write-Host $_ }
      throw "Illegal sprint status lines found."
    }
    Write-Host "Sprint status YAML OK."
  }

  Invoke-ValidationStep "UX spine check" {
    $workspace = "_bmad-output\planning-artifacts\ux-designs\ux-The-Council-of-Minions-2026-07-08"
    $design = Join-Path $workspace "DESIGN.md"
    $experience = Join-Path $workspace "EXPERIENCE.md"
    $memlog = Join-Path $workspace ".memlog.md"
    foreach ($path in @($design, $experience, $memlog)) {
      if (-not (Test-Path $path)) {
        throw "Missing UX artifact: $path"
      }
    }

    $designText = Get-Content -Raw $design
    foreach ($heading in @("## Brand & Style", "## Colors", "## Typography", "## Components", "## Do's and Don'ts")) {
      if ($designText -notmatch [regex]::Escape($heading)) {
        throw "DESIGN.md missing heading: $heading"
      }
    }

    $experienceText = Get-Content -Raw $experience
    foreach ($heading in @("## Foundation", "## Information Architecture", "## Voice and Tone", "## Component Patterns", "## State Patterns", "## Interaction Primitives", "## Accessibility Floor", "## Key Flows")) {
      if ($experienceText -notmatch [regex]::Escape($heading)) {
        throw "EXPERIENCE.md missing heading: $heading"
      }
    }
    Write-Host "UX spines OK."
  }

  Invoke-ValidationStep "Model-driven app screen gate harness check" {
    $screenRunner = "_bmad-output\implementation-artifacts\council-model-driven-screen-test.ps1"
    $screenReadme = "_bmad-output\test-artifacts\model-driven-screen\README.md"
    $screenJs = "_bmad-output\test-artifacts\model-driven-screen\council-model-driven-screen-test.js"
    foreach ($path in @($screenRunner, $screenReadme, $screenJs)) {
      if (-not (Test-Path $path)) {
        throw "Missing model-driven app screen gate artifact: $path"
      }
    }

    $readmeText = Get-Content -Raw $screenReadme
    foreach ($marker in @("Council Queue", "screenshots", "Playwright trace", "curated view IDs", "record forms", 'Do not mark the MVP screen surface complete from `ValidateApp` alone')) {
      if ($readmeText -notmatch [regex]::Escape($marker)) {
        throw "Screen gate README missing marker: $marker"
      }
    }

    $screenText = Get-Content -Raw $screenJs
    if ($screenText -match "waitForTimeout") {
      throw "Model-driven app screen runner must not use fixed sleeps for screen readiness."
    }

    Write-Host "Model-driven app screen gate harness exists."
  }

  if ($RequireScreenEvidence) {
    Invoke-ValidationStep "Model-driven app screen evidence" {
      $output = & powershell -NoProfile -ExecutionPolicy Bypass -File "_bmad-output\implementation-artifacts\council-model-driven-screen-test.ps1"
      if ($LASTEXITCODE -ne 0) {
        throw "Model-driven app screen evidence failed. Run the same script with -InteractiveLogin -Headed if browser authentication is required."
      }
      $output | ForEach-Object { Write-Host $_ }
      if (($output -join "`n") -notmatch "COUNCIL_MODEL_DRIVEN_SCREEN_TEST_PASSED") {
        throw "Model-driven app screen evidence did not print success marker."
      }
    }
  }

  Invoke-ValidationStep "Stale BMAD gate reference check" {
    rg -n -g "!council-mvp-local-validate.ps1" 'pending-workflow-completion|pending workflow completion|Doug sends `C`|Doug replies `C`|Minimal Reply Needed|implementation readiness remains incomplete|readiness analysis can begin|final workflow completion' "_bmad-output\planning-artifacts" "_bmad-output\implementation-artifacts"
    if ($LASTEXITCODE -eq 0) {
      throw "Stale BMAD gate references remain."
    }
    if ($LASTEXITCODE -ne 1) {
      throw "Stale gate reference search failed."
    }
    Write-Host "No stale BMAD gate references found."
  }

  Write-Host ""
  Write-Host "COUNCIL_MVP_LOCAL_VALIDATE_OK"
}
finally {
  Pop-Location
}
