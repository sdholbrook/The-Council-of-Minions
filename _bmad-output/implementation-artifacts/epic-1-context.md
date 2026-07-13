# Epic 1 Context: Source Intake and Proposed Work Items

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Enable Doug to capture Outlook-first and manual Microsoft work context as Source Records, then explicitly extract explainable proposed Work Items from them. The epic establishes the intake half of the Council's source-to-work-item control plane: every piece of work context enters as a Source Record with full provenance, extraction is an explicit step that can yield zero, one, or many proposed Work Items with rationale and confidence, and later source changes create drift evidence instead of silently rewriting history. This keeps intake scope broader than queue scope and prevents the classic failure of treating every email or note as a task.

## Stories

- Story 1.1: Capture Manual Source Records
- Story 1.2: Capture Outlook Source References
- Story 1.3: Extract Proposed Work Items From Source Records
- Story 1.4: Handle Zero-Item and Multi-Item Extraction
- Story 1.5: Handle Source Drift and Supersession

## Requirements & Constraints

- All intake enters as a Source Record before any extraction. Source Records never mutate into Work Items; a Work Item is created only by explicit extraction or explicit human input.
- Extraction must produce zero, one, or many proposed Work Items. Zero-item outcomes mark the Source Record `ignored` or `held` with rationale — never create a Work Item just to satisfy a one-source-one-task assumption.
- Every Source Record preserves provenance: source system, source kind, native object reference, capture time and actor, source version/drift detector, permission/sensitivity/retention metadata (may be `unknown`), attachment references when captured, and source-to-work-item rationale (why work was or was not proposed).
- Outlook captures must preserve the source link and conversation/thread context, not just a single message id. When live Outlook/Graph reads are unauthorized, a mock/manually-entered Outlook Source Record must be supported and marked as mock/manual evidence, not verified tenant evidence.
- Each proposed Work Item carries a controlled type (`decision`, `delegation`, `follow_up`, `request`, `risk`, `artifact_task`, `meeting_action`), summary, extraction rationale, confidence, uncertainty, suggested owner, urgency, risk class, and recommended next action.
- Multiple Work Items from one Source Record each carry their own rationale, confidence, type, and source binding. A Work Item may reference multiple Source Records but exactly one primary source rationale must be explicit.
- Legal, finance, relationship, sensitive, or low-confidence extraction paths produce proposed-only Work Items — never auto-created ones.
- Source body capture defaults to link-only until a fuller policy is approved. Link-only, hash-only, and summary-only capture must be supported, and the data boundary policy must be visible on the record. Extraction is blocked while the policy is unknown unless a link-only/hash-only safe fallback is used.
- Source drift creates a new source version reference, a drift receipt, or a superseding Source Record. Prior rationale and receipts remain unchanged; a drifted source that affects an existing Work Item must flag the Work Item for review, and any resulting state change needs a new Receipt.
- Source Records, Work Items, Receipts, Memory Candidates, and Graph Entities are distinct concepts with distinct identities — never collapse them into one generic row or platform object.
- No live tenant writes, app registrations, broad permissions, or external actions without explicit approval; preserve least-privilege and DLP/sensitivity behavior wherever available.

## Technical Decisions

- **Store:** Dataverse is the MVP operational system of record; native Microsoft systems (Outlook/Exchange, Teams, SharePoint) remain the source of truth for the artifacts themselves. Council records reference them, they do not copy them by default.
- **Identity:** Stable Council-level IDs (`council_source_record_id`, `council_work_item_id`) are the primary product identifiers. Dataverse row IDs and Microsoft/Graph IDs are stored only as source references or bindings.
- **Source Record contract fields:** source_system, source_kind, source_object_ref, source_object_url, conversation_ref, parent_ref, captured_at, captured_by, observed_modified_at, source_version_ref (ETag/change key/hash), content_snapshot_ref, content_hash, attachment_refs, permission_snapshot, sensitivity_label, retention_or_hold_flags, extraction_status, extraction_confidence, source_to_work_item_rationale, plus a data boundary policy (Link Only / Hash Only / Summary Allowed / Full Snapshot Allowed / Unknown).
- **Extraction status vocabulary:** `new`, `extracted`, `ignored`, `held`, `failed`, `superseded`.
- **Work Item shell:** type, title, summary, state_group, owner candidate + confidence, urgency, risk class, confidence explanation, primary source lookup, rationale, recommended next action, approval_required, semantic_contract_version, creation receipt reference. New extractions land in state group `proposed` (state groups: proposed, approved, blocked, held, in_review, completed, failed).
- **Multi-source provenance:** a Work Item Source join table links Work Items to supporting Source Records with a role (Primary / Supporting / Contradicting / Superseding), rationale, and confidence, while the Work Item keeps its primary source lookup.
- **Receipts:** append-only; every meaningful mutation (including `source_drifted`) appends a Receipt before or atomically with the state projection. Corrections are new Receipts. Connector-, schedule-, or agent-triggered mutations require idempotency keys.
- **Vocabulary:** the Council Semantic Contract is canonical. Use the exact nouns Source Record, Work Item, Receipt, Meaning Graph, Memory Candidate, Minion Brief in schema display names, descriptions, views, and UI copy. Timestamps are ISO 8601.
- **Dataverse naming:** solution `CouncilOfMinionsMVP`, publisher prefix `com_`, tables such as `com_councilsourcerecord`, `com_councilworkitem`, `com_councilworkitemsource` (confirm prefix before tenant writes).
- **Tenant gates:** live Outlook/Graph reads and any Dataverse writes are `VERIFY IN TENANT` until readiness evidence exists; development must support a mock/local path.

## UX & Interaction Patterns

- MVP review surface is a Dataverse model-driven app ("Council Queue"). Epic 1 lives in the Intake area: Source Records grid plus New Source Records and Held Source Records views, and Source Record forms.
- Source Record grid sorts by captured time descending and shows source system, source kind, extraction status, data boundary policy, source object reference, captured by, and a drift indicator. The form puts source link, data boundary policy, sensitivity, retention flags, extraction status, rationale, and related Work Items above less-used metadata.
- Core flow: create/save Source Record, then run an explicit Extract command; the proposed Work Item opens showing its primary Source Record while the Source Record remains a separate record.
- The extraction command must refuse to run while source body policy is `unknown` unless a link-only/hash-only fallback is chosen; unknown-policy sources surface "Source body policy is unknown."
- Drift shows a warning on both source and Work Item detail and requires review before state movement when drift affects rationale.
- Microcopy is direct and evidence-first; status is never conveyed by color alone; empty intake shows "No Source Records yet." with a New Source Record action.

## Cross-Story Dependencies

- Stories 1.1 and 1.2 produce the Source Records that 1.3, 1.4, and 1.5 consume; 1.3 defines the extraction pipeline that 1.4 extends to zero-item and multi-item cardinality.
- Story 1.3 creates proposed Work Items inside the canonical execution shell owned by Epic 2 (Story 2.1); drift receipts and review-needed state changes in 1.5 rely on Epic 2's receipt ledger semantics (Story 2.3).
- The confidence, risk class, and type metadata produced by extraction here is the input Epic 2's auto-creation policy evaluates; this epic itself only ever creates proposed Work Items.
- Dataverse environment readiness, publisher prefix approval, and live Outlook/Graph read authorization are gated by Epic 5 (Stories 5.4 and 5.5); Epic 1 work must degrade to mock/manual evidence paths until those gates pass.
