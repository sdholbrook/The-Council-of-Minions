---
baseline_commit: 38fb9f90f5e0b8cecc6ce4037bb8591c350e4f31
---

# Story 1.2: Capture Outlook Source References

Status: in-progress

<!-- Generated from bmad-create-story context on 2026-07-08, then advanced through the local non-tenant implementation path. Tenant reads and writes remain gated. -->

## Story

As Doug,
I want Outlook messages and threads captured as Source Records with links and conversation context,
so that email-driven work can be reviewed without losing its original source.

## Acceptance Criteria

1. Given Outlook/Graph reads are authorized for the target tenant, when an Outlook message or thread is captured, then the Source Record must preserve the Outlook source link, source object reference, conversation or thread reference, capture actor, capture time, and available source version metadata, and the Source Record must not become a Work Item directly.
2. Given live Outlook/Graph reads are not authorized, when the MVP is demonstrated, then the system must support a mock or manually-entered Outlook Source Record, and the record must be marked as mock/manual evidence rather than verified tenant evidence.

## Tasks / Subtasks

- [x] Confirm story gates before implementation.
  - [x] Verify Outlook/Graph live-read approval, Dataverse write approval, source body policy, publisher prefix, and model-driven app acceptance before any live tenant read or write.
  - [x] If approval is not present, keep work local to story, manifest, validation, and mock/manual reference artifacts.
- [x] Define the Outlook Source Record reference slice.
  - [x] Use `Council Source Record` / `com_councilsourcerecord`; do not create an Outlook-specific work item table.
  - [x] Require Outlook source system, message/thread source kind, source object reference, source link when safe, conversation reference, capture actor/time, source version metadata, permission/sensitivity/retention notes, extraction status, rationale, and data boundary policy.
  - [x] Specify that authorized Graph reads must request immutable Outlook identifiers with `Prefer: IdType="ImmutableId"` and must still preserve conversation context.
  - [x] Ensure saving an Outlook Source Record never creates or mutates a Work Item.
- [x] Support a mock/manual Outlook fallback.
  - [x] Add mock message and thread reference samples that are visibly marked as not tenant verified.
  - [x] Keep sample body capture link-only or hash-only unless source body policy is explicitly approved.
  - [x] Preserve conversation/thread reference shape even without live Graph access.
- [ ] Configure the first review surface after tenant approval.
  - [ ] In the model-driven `Council Queue` app, expose Outlook Source Records in the Intake group.
  - [ ] Provide Outlook Source Records and Mock Outlook Source Records views.
  - [ ] Put source link, object reference, conversation reference, source version, permission/sensitivity/retention notes, data boundary policy, extraction status, and rationale in the visible form path.
- [x] Strengthen validation around this slice.
  - [x] Add a local Outlook Source Reference slice validator.
  - [x] Wire the validator into `council-mvp-local-validate.ps1`.
  - [x] Run required local validation before committing.

## Dev Notes

### Product and Architecture Guardrails

- BMAD is the delivery harness, not the product runtime. Keep all product semantics in Council contracts and implementation artifacts. [Source: `_bmad-output/project-context.md#Technology-Stack-&-Versions`]
- Outlook is the first intake source, not the top-level product boundary. The product stays work-item-first with Source Records preceding any Work Item extraction. [Source: `_bmad-output/project-context.md#Product-Model-Rules`; `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/ARCHITECTURE-SPINE.md#AD-13---Outlook-first-intake-Council-first-review-ADOPTED`]
- A Source Record can later propose zero, one, or many Work Items, but Source Records never become Work Items by mutation. [Source: `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/source-record-contract.md#Invariant`]
- Live Microsoft tenant behavior, connector use, app registration, Graph permission, automation, or data write remains `VERIFY IN TENANT` until authorized and evidenced. [Source: `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/ARCHITECTURE-SPINE.md#AD-10---Tenant-interaction-remains-VERIFY-IN-TENANT-ADOPTED`]
- The Council Semantic Contract remains canonical. Microsoft Graph message properties and Dataverse fields are bindings/projections, not competing domain definitions. [Source: `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/semantic-contract.md#Authority`]

### Microsoft Graph Reference Facts

Checked on 2026-07-08 against official Microsoft Learn sources:

- Microsoft Graph `message` has `conversationId`, `conversationIndex`, `changeKey`, `internetMessageId`, `parentFolderId`, `receivedDateTime`, `lastModifiedDateTime`, `hasAttachments`, and `webLink` properties relevant to Source Record provenance. [Source: https://learn.microsoft.com/en-us/graph/api/resources/message?view=graph-rest-1.0]
- Microsoft Graph message `id` can change when an item is moved; authorized reads that persist IDs for later use should request immutable IDs using `Prefer: IdType="ImmutableId"`. [Source: https://learn.microsoft.com/en-us/graph/api/resources/message?view=graph-rest-1.0; https://learn.microsoft.com/en-us/graph/outlook-immutable-id]
- The immutable ID header must be included on every request that should return immutable IDs, and immutable IDs remain stable only while the item stays in the same mailbox. [Source: https://learn.microsoft.com/en-us/graph/outlook-immutable-id]
- `GET /me/messages/{id}` and `/users/{id | userPrincipalName}/messages/{id}` are read paths for message references, with delegated `Mail.ReadBasic`/`Mail.Read` or application `Mail.ReadBasic.All`/`Mail.Read` permissions. Do not request or use these until Doug authorizes live reads. [Source: https://learn.microsoft.com/en-us/graph/api/message-get?view=graph-rest-1.0]
- Microsoft Graph mail API documentation warns not to assume message and mail folder IDs always remain the same; immutable IDs are the supported mitigation for many move scenarios. [Source: https://learn.microsoft.com/en-us/graph/api/resources/mail-api-overview?view=graph-rest-1.0]

### Dataverse Slice

The existing manifest already models Outlook-capable Source Records. Reuse these fields:

| Column | Story use |
| --- | --- |
| `com_source_system` | Must be `outlook`. |
| `com_source_kind` | `message` for a single message, `thread` for a conversation/thread capture. |
| `com_source_object_ref` | Native Graph message ID, immutable Graph ID when authorized, or mock/manual reference. |
| `com_source_object_url` | Outlook `webLink` when safe to store, or mock/manual URL when live reads are not authorized. |
| `com_conversation_ref` | Outlook `conversationId` or manual/mock thread reference. |
| `com_parent_ref` | Parent message, folder, or source reference when useful. |
| `com_observed_modified_at` | Message `lastModifiedDateTime` when available. |
| `com_source_version_ref` | `changeKey`, `internetMessageId`, last modified timestamp, or mock version reference. |
| `com_attachment_refs` | Attachment metadata only when allowed; never hidden full content. |
| `com_permission_snapshot` | Known mailbox/source access or `mock/manual evidence, not tenant verified`. |
| `com_sensitivity_label` | Sensitivity or `unknown`. |
| `com_retention_or_hold_flags` | Retention/hold state or `unknown`. |
| `com_data_boundary_policy` | Starts link-only or hash-only unless Doug approves richer capture. |

Relevant artifacts:

- `_bmad-output/implementation-artifacts/dataverse-mvp-schema-manifest.json`
- `_bmad-output/implementation-artifacts/outlook-source-reference-slice.json`
- `_bmad-output/implementation-artifacts/outlook-source-reference-slice-validate.ps1`

### Previous Story Intelligence

Story 1.1 established the local implementation pattern:

- Create a story-specific JSON slice that proves the contract without tenant writes.
- Add a PowerShell validator with a clear success marker.
- Wire the validator into `council-mvp-local-validate.ps1`.
- Treat tenant-dependent model-driven app configuration as split: Dataverse table components are now proven for the scoped app, while Outlook-specific live Graph reads and curated views/forms remain open.

Files and patterns to preserve:

- `_bmad-output/implementation-artifacts/manual-source-record-slice.json`
- `_bmad-output/implementation-artifacts/manual-source-record-slice-validate.ps1`
- `_bmad-output/implementation-artifacts/council-mvp-local-validate.ps1`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`

### Anti-Patterns to Avoid

- Do not store Outlook body text when live reads or source body policy are not approved.
- Do not treat a mock Outlook Source Record as verified tenant evidence.
- Do not create a Work Item when an Outlook Source Record is saved.
- Do not use Graph message IDs, Outlook web links, or Dataverse row IDs as Council product identities.
- Do not request broad Graph permissions, create an app registration, publish a flow, or create a connector dependency inside this story.
- Do not treat conversation/thread context as optional; a single message ID without `conversation_ref` is insufficient for Story 1.2.

## Testing Requirements

Minimum local validation before review:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\outlook-source-reference-slice-validate.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\dataverse-manifest-validate.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\council-mvp-local-validate.ps1
git diff --check
```

Expected local success markers:

```text
OUTLOOK_SOURCE_REFERENCE_SLICE_VALIDATE_OK
COUNCIL_MVP_LOCAL_VALIDATE_OK
```

Tenant validation after Doug approval and interactive auth:

```powershell
pac auth create --environment ba9a96b2-f562-40f6-931d-6b55873954ee --name Council-SDH-Dev
pac auth who
pac env who
pac env list-settings
```

Do not perform live Graph reads until `tenant-decision-packet-validate.ps1 -RequireComplete` passes with live reads allowed and the tenant/environment is proven.

## Definition of Done

- Outlook message and thread Source Records can be represented without creating Work Items.
- Mock/manual Outlook Source Records are visibly marked as not tenant verified.
- Conversation/thread context is preserved.
- Link-only and hash-only body policies prevent accidental content storage.
- Local validator and full MVP validator pass.
- If tenant implementation occurs later, tenant evidence and source-controlled solution/export artifacts are committed.
- No outbound action, flow publish, agent publish, app registration, Fabric mutation, or Graph write occurs.

## Open Questions / Required User Decisions

These remain required before live Story 1.2 completion:

1. Are read-only Outlook/Graph checks allowed?
2. What tenant domain or tenant ID should Graph validation use?
3. What source body policy is allowed for Outlook samples: link-only, hash-only, summary allowed, or full snapshot allowed?
4. Does Doug approve Dataverse writes after read-only preflight proves the target environment?
5. Which curated model-driven app views/forms should be used for the first Council Queue Intake surface?

## Project Context Reference

Read `_bmad-output/project-context.md` before implementation. The highest-risk rules for this story are:

- Treat emails as Source Records first.
- Preserve source-to-work-item provenance and rationale.
- Keep Source Records, Work Items, Receipts, graph entities, and audit events distinct.
- Prefer restrictive behavior when governance, provenance, or approval boundaries are unclear.
- Mark tenant-specific unknowns as `VERIFY IN TENANT`.

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-08 | Created Story 1.2 from BMAD epic context and implemented the local Outlook Source Reference slice. Story remains in-progress because live Outlook/Graph reads are still gated and Outlook-specific app views/forms are not curated. |

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

- Red check: `outlook-source-reference-slice-validate.ps1` failed before `outlook-source-reference-slice.json` existed.
- Green check: `outlook-source-reference-slice-validate.ps1` passes and prints `OUTLOOK_SOURCE_REFERENCE_SLICE_VALIDATE_OK`.
- Regression gate: `council-mvp-local-validate.ps1` passes and prints `COUNCIL_MVP_LOCAL_VALIDATE_OK`.

### Completion Notes List

- Story context created from BMAD epics, project context, architecture contracts, Source Record contract, Story 1.1 learnings, current manifest/scripts, and official Microsoft Graph documentation.
- Local non-tenant implementation proves Outlook message/thread reference shape, immutable-ID guidance, conversation reference preservation, mock/manual fallback marking, and Source Record / Work Item separation.
- Tenant-dependent work remains open for live Outlook capture: Doug must approve live Graph reads and any expanded source body policy before this story can satisfy the remaining live-read task.

### File List

- `_bmad-output/implementation-artifacts/1-2-capture-outlook-source-references.md`
- `_bmad-output/implementation-artifacts/outlook-source-reference-slice.json`
- `_bmad-output/implementation-artifacts/outlook-source-reference-slice-validate.ps1`
- `_bmad-output/implementation-artifacts/dataverse-mvp-schema-manifest.json`
- `_bmad-output/implementation-artifacts/council-mvp-local-validate.ps1`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
