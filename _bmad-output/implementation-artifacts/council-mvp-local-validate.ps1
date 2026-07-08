[CmdletBinding()]
param(
  [string]$ProjectRoot
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
