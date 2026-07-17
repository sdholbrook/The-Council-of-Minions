#!/usr/bin/env python3
"""catch_emit.py — a Gate emits its own Catch; nothing infers one afterwards.

A Catch is the record of a Gate DECISION. Every refusal must become visible
evidence, and the evidence must be produced by the Gate at the moment it
decides — reconstructing a Catch later by parsing free-text run notes is how
the fleet ended up with evidence that existed but could not be read.

Shape
-----
An append-only JSON-LD node, one object per line (ND-JSON), written to
``<export-dir>/<key>.catches.jsonld``. Append-only is the point: a retry must
never clobber the prior Catch, because the prior Catch is exactly the evidence
worth keeping. The Ledger renders this file; it renders nothing else.

Vocabulary
----------
Axes come from Axon's published SKOS vocabulary and are NEVER redefined here:

    axon:result        accepted | rejected | succeeded | failed | superseded | no_op
    axon:failure_cause verification | timeout | error
    axon:actor_type    human | agent | system | connector

A Gate is a ``system`` actor. A refusal is ``result/rejected``; the cause axis
says WHY in the vocabulary the whole fleet already speaks, which is why this
module has no bespoke "severity" of its own.

``meridian:`` adds only what Axon does not publish: which gate, which run,
which attempt, and the human-readable reason.

Identity
--------
``(runId, key, gate, attempt)``, expressed as
``@id = <runId>/<key>#<gate>#<attempt>``.

The runId is IN the ``@id``, not merely a property beside it. In JSON-LD the
``@id`` *is* the identity: drop the runId and two Catches from different runs
of the same story become the same RDF node, so merging the evidence graph
silently conflates them. An identity tuple that the identifier does not encode
is not an identity.

``attempt`` is DERIVED, not passed in: nothing upstream tracks an attempt
number, and asking a caller to supply one invites it to lie. Counting the
prior Catches for the same (runId, key, gate) in the append-only record keeps
the number honest — the evidence numbers itself.

Stdlib only. This runs inside every fleet repo's vendored bridge and must not
acquire dependencies.
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone

CONTEXT = {
    "skos": "http://www.w3.org/2004/02/skos/core#",
    "axon": "https://synapticsci.github.io/SynSci-Axon/vocab/",
    "meridian": "https://synapticsci.github.io/SynSci-Meridian/vocab/",
}

# Gate decisions, expressed in Axon's published result scheme.
REJECTED = "axon:result/rejected"
ACCEPTED = "axon:result/accepted"

# Why a Gate refused, expressed in Axon's published failure_cause scheme.
VERIFICATION = "axon:failure_cause/verification"   # the work is wrong
ERROR = "axon:failure_cause/error"                 # the harness is wrong
TIMEOUT = "axon:failure_cause/timeout"


def catches_path(export_dir: str, key: str) -> str:
    return os.path.join(export_dir, f"{key}.catches.jsonld")


def _next_attempt(path: str, run_id: str, key: str, gate: str) -> int:
    """Derive the attempt number by counting this gate's prior Catches.

    A malformed line never blocks emission: evidence that cannot be parsed is
    worse than evidence that is one short, and a Gate that crashes while
    recording a refusal has swallowed the refusal.
    """
    n = 0
    try:
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    node = json.loads(line)
                except ValueError:
                    continue
                if (node.get("meridian:runId") == run_id
                        and node.get("meridian:workItem") == key
                        and node.get("meridian:gate") == gate):
                    n += 1
    except OSError:
        pass
    return n + 1


def emit(export_dir, key, gate, decision, reason, run_id="unknown",
         cause=VERIFICATION, locus=(), coupon=False, origin="factory"):
    """Append one Catch node and return it.

    Args:
        export_dir: directory the verified patch is exported to; the Catch
            record lives beside it so evidence and artifact travel together.
        key: the Work Item (story) key.
        gate: which gate decided — "check", "ownership", "tests-docs".
        decision: REJECTED or ACCEPTED.
        reason: human-readable; this is what the operator actually reads.
        run_id: the Ringer run name, so Catches from different runs never
            collide in identity.
        cause: an axon:failure_cause concept; ignored when ACCEPTED.
        locus: the paths the refusal is ABOUT, as structured data. A Gate that
            knows its locus and renders it only into ``reason`` has destroyed
            the evidence: downstream must then decide whether the refusal was
            the Line's own bug (a refusal whose locus is a contract artifact is
            self-inflicted), and the only way back to a stringified list is the
            prose-parsing this architecture forbids. Emit what you know.
        coupon: whether this Work Item is planted fault injection. **Always
            written, never omitted.** An absent flag reads as False downstream,
            and False authorizes the patch — so omission is what would let a
            Coupon's patch apply and silently defeat the whole point of
            planting it.
        origin: who authored the work — "factory" (a Gate is the factory) or
            "human".
    """
    os.makedirs(export_dir, exist_ok=True)
    path = catches_path(export_dir, key)
    attempt = _next_attempt(path, run_id, key, gate)

    node = {
        "@context": CONTEXT,
        "@id": f"{run_id}/{key}#{gate}#{attempt}",
        "@type": "meridian:Catch",
        "axon:result": {"@id": decision},
        "axon:actor_type": {"@id": "axon:actor_type/system"},
        "meridian:runId": run_id,
        "meridian:workItem": key,
        "meridian:gate": gate,
        "meridian:attempt": attempt,
        "meridian:reason": reason,
        "meridian:locus": list(locus),
        # Written unconditionally, including False. Absence is not "no coupon" —
        # absence is silence, and downstream reads silence as permission.
        "meridian:coupon": bool(coupon),
        "meridian:origin": origin,
        "meridian:at": datetime.now(timezone.utc).isoformat(),
    }
    if decision == REJECTED:
        node["axon:failure_cause"] = {"@id": cause}

    with open(path, "a") as fh:
        fh.write(json.dumps(node, sort_keys=True) + "\n")
    return node
