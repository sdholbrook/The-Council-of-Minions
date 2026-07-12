# Source Record Contract

Status: architecture-ready  
Updated: 2026-07-07

## Purpose

Define the storage-neutral source identity and provenance contract for Microsoft work artifacts and manual captures before they become Work Items.

## Invariant

All intake enters as a Source Record. A Source Record can propose zero, one, or many Work Items. Source Records never become Work Items by mutation.

## Required Fields

| Field | Meaning |
| --- | --- |
| council_source_record_id | Stable Council source identifier. |
| source_system | Outlook, Teams, SharePoint, OneDrive, Calendar, manual, or other approved source. |
| source_kind | Message, thread, chat, meeting, file, comment, task, manual note, or other controlled kind. |
| source_object_ref | Native source identifier or pointer. |
| source_object_url | Resolvable source link when allowed. |
| conversation_ref | Thread, chat, meeting, or conversation binding when available. |
| parent_ref | Parent message, file, meeting, or source record when relevant. |
| captured_at | ISO 8601 capture timestamp. |
| captured_by | User, Minion, connector, or trusted-source rule that captured it. |
| observed_modified_at | Native source modified timestamp when available. |
| source_version_ref | ETag, change key, version id, hash, or equivalent drift detector. |
| content_snapshot_ref | Reference to captured text or summary snapshot if stored. |
| content_hash | Hash of captured content or extracted text when allowed. |
| attachment_refs | Attachment identifiers, names, content hashes, and permission notes where captured. |
| permission_snapshot | Best-known access scope at capture time. |
| sensitivity_label | Sensitivity, confidentiality, or classification metadata when available. |
| retention_or_hold_flags | Retention, legal hold, or policy flags when visible. |
| extraction_status | new, extracted, ignored, held, failed, superseded. |
| extraction_confidence | Confidence for extracted facts or reason not extracted. |
| source_to_work_item_rationale | Why a Work Item was or was not proposed. |

## Microsoft-Specific Notes

- Outlook message and thread identity must preserve conversation/thread context, not only a single message id.
- Teams and meeting sources must preserve meeting/chat context and speaker/participant constraints where available.
- SharePoint / OneDrive file sources must preserve file version or change metadata when available.
- Permission, sensitivity, retention, and DLP metadata are part of the source contract even when the first implementation can only mark them `unknown`.

## Work Item Extraction Rules

- Extraction must preserve source reference, rationale, confidence, uncertainty, and suggested Work Item Type.
- Multiple Work Items from one Source Record must each carry their own rationale and source binding.
- A Work Item can reference multiple Source Records, but one primary source rationale must be explicit.
- Legal, finance, relationship, sensitive, or low-confidence extraction paths produce proposed Work Items only.

## Drift Handling

When a source changes after capture, the Council must not silently rewrite prior receipts or work-item rationale. Later source changes create a new source version reference, a drift receipt, or a superseding Source Record depending on implementation.
