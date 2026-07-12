# Architecture Spine Review - Adversarial Divergence

## Verdict

Pass after finish-plan updates. Two downstream teams could independently build source intake, queue, delegation support, Meaning Graph context, Skill Registry, receipts, and Minion Brief without choosing incompatible ownership or mutation paths, provided they follow AD-2 through AD-13 and the companion contracts.

## Divergence Tests

### Test 1: Outlook intake team vs meeting-action team

Potential divergence: one team turns messages directly into tasks while another turns meetings into separate action records.

Result: closed by AD-2 and AD-3. Both must enter inputs as Source Records and create Work Items through the canonical shell with a `type` field.

### Test 2: Brief team vs graph team

Potential divergence: the Brief team mutates state based on summary decisions while the graph team encodes workflow state in graph edges.

Result: closed by AD-5 and AD-6. State changes require Receipts, and the Meaning Graph cannot own state transitions or queue movement.

### Test 3: Skill team vs governance team

Potential divergence: a new Minion skill silently grants data access or outbound authority.

Result: closed by AD-4 and AD-8. Skill authority expansion requires approval, and skills must declare authority, allowed context, and proof owed.

### Test 4: Memory team vs source/provenance team

Potential divergence: an agent note becomes durable instruction while source provenance remains evidence-only.

Result: closed by AD-7. Durable memory starts as a Memory Candidate and becomes binding instruction only after approval or trusted-source policy.

### Test 5: Custom graph team vs Microsoft platform team

Potential divergence: one team builds a custom ontology/graph/memory substrate while another uses Work IQ, Dataverse intelligence, Power Apps MCP, or Fabric IQ as the native plane.

Result: closed by AD-9, AD-10, and AD-11. The product contract stays storage-neutral, tenant behavior stays `VERIFY IN TENANT`, and custom substrate work must first document why Microsoft-native planes do not satisfy the Council contract.

### Test 6: Dataverse semantic model team vs Fabric ontology team

Potential divergence: one team edits Dataverse glossary terms while another creates Fabric IQ entities with different definitions.

Result: closed by AD-12 and `semantic-contract.md`. Both platform artifacts project from the Council Semantic Contract, and platform-inferred changes are candidates until approved.

### Test 7: Outlook team vs queue team

Potential divergence: one team builds an Outlook-only triage assistant while another builds a generic Council dashboard.

Result: closed by AD-13. MVP intake is Outlook-first plus manual capture; the first review and approval surface is Minion Brief plus Council Queue.

## Remaining Watch Item

The first implementation story set must cite the companion contracts directly so `Source Record`, `Work Item`, `Receipt`, `Memory Candidate`, and `Graph Entity` are not collapsed into a single generic row/document or hidden behind a Microsoft platform object too early.
