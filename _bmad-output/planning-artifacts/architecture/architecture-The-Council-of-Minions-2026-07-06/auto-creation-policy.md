# Auto-Creation Policy

Status: architecture-ready  
Updated: 2026-07-07

## Purpose

Define when the Council may auto-create low-risk Work Items and when it must stop at proposal or human review.

## Default Rule

Propose first. Auto-creation is an exception for narrow, low-risk `follow_up` and `meeting_action` items. Auto-created does not mean auto-approved for external action.

## Allowed Auto-Creation Types

| Type | Auto-create policy |
| --- | --- |
| follow_up | Allowed only when low-risk criteria and confidence thresholds pass. |
| meeting_action | Allowed only when source wording clearly states an action/owner/date or equivalent commitment. |
| decision | Never auto-create as executable; proposal only. |
| delegation | Proposal only; human approval required. |
| request | Proposal only unless reduced to a low-risk follow-up. |
| risk | Proposal only; human review required. |
| artifact_task | Proposal only in MVP. |

## Low-Risk Criteria

All must be true:

- No legal, finance, contract, relationship, sensitive, compliance, governance, or tenant-affecting exposure.
- No outbound message, commitment, file write, permission change, app registration, automation publish, or external action.
- Source is concrete and recent enough to justify action.
- Owner and next action are obvious from the source or explicit human input.
- Action can be safely reversed, ignored, or reviewed without material harm.
- Source permissions and sensitivity are not unknown in a way that would affect visibility.

## Confidence Thresholds

| Dimension | Minimum for auto-create |
| --- | --- |
| Source identification | 0.95 |
| Work Item Type | 0.90 |
| Low-risk classification | 0.95 |
| Owner or responsible party | 0.85, unless owner is not needed |
| Next action | 0.90 |

If a dimension is unavailable, contradictory, or policy-sensitive, create a proposal instead of auto-creating.

## Required Receipt

Every auto-created item must append a `proposed` receipt with:

- Source Record reference.
- Confidence scores.
- Low-risk rationale.
- Actor identity or trusted-source rule.
- Idempotency key.
- Policy flags checked.

## Escalation

Escalate to human review when:

- Confidence is below threshold.
- Source contains legal, finance, contract, relationship, or sensitive indicators.
- Owner selection is uncertain or politically meaningful.
- The next action could imply a commitment, concession, deadline, payment, approval, or external stance.
- Doug is likely expected to personally respond.

## Non-Negotiable Boundary

No outbound action, sensitive handling, authority expansion, tenant write, memory promotion, skill expansion, or external system mutation can happen merely because a Work Item was auto-created.
