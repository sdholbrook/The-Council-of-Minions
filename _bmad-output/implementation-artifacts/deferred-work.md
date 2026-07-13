# Deferred Work

- source_spec: `_bmad-output/implementation-artifacts/spec-1-4-handle-zero-item-and-multi-item-extraction.md`
  summary: The four pre-existing sibling steps in `council-mvp-local-validate.ps1` (tenant packet, manual slice, Outlook slice, 1.3 extraction slice) throw on a child validator's non-zero exit before echoing its output, so the child's issue list is swallowed on exactly the runs where it matters.
  evidence: Reproduced during the story 1.4 review — a failing child validator's diagnostics never appear in suite output because `throw` precedes `$output | ForEach-Object { Write-Host $_ }`; the new 1.4 step already prints first and can serve as the template.
- source_spec: `_bmad-output/implementation-artifacts/spec-1-4-handle-zero-item-and-multi-item-extraction.md`
  summary: The story 1.1/1.2/1.3 slice validators' `Add-Issue` lacks `[AllowEmptyCollection()]`, so on any failing slice the first `Add-Issue` call crashes with a parameter-binding error instead of listing the violations (exit code still non-zero, diagnostics lost).
  evidence: Demonstrated during the story 1.4 review against a mutated copy of the 1.3 slice; the 1.4 validator carries the one-attribute fix at `zero-multi-item-extraction-slice-validate.ps1:13`, and backporting was out of scope because the spec froze the 1.1–1.3 validators.
- source_spec: `_bmad-output/implementation-artifacts/spec-1-4-handle-zero-item-and-multi-item-extraction.md`
  summary: No committed artifact exercises any slice validator's failure path; negative (mutation) tests exist only as ad-hoc scratchpad runs, so a mistyped property name could silently neuter a check while the suite stays green.
  evidence: PowerShell returns `$null` for absent properties without error, so a validator check can decay invisibly; all Epic 1 validators (1.1 through 1.4) share this gap, and the 1.4 review's 12-mutation probe set would be a ready seed for a committed negative-test harness.
