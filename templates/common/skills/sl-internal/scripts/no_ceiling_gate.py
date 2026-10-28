#!/usr/bin/env python3
"""no_ceiling_gate.py — block a premature "class-A / tool-ceiling" relabel (no-ceiling.md).

The recurring coherent-and-wrong (5x in this project): a hard-but-CLOSEABLE goal is relabeled a
"tool ceiling" (class-A / "WP can't" / "store-bloat wall") and parked, when it is class-C unfinished
work. `refutation_probe.py` already gates this in principle, but its soundness needs a DISJOINT
attestor the producer can't influence — structurally absent in a SOLO run, where the producer
self-certifies "class-A, lever-attested." This gate makes the class-A label UNWRITABLE without a
checkable artifact bundle, and UNATTESTED without a disjoint judge. It flips the burden of proof:
**class-C is the default; class-A is a rare, evidence-heavy, disjointly-attested exception.**

A residue may be recorded class-A / CEILING only if ALL mechanical checks pass AND a disjoint
attestation confirms it. Any missing/failing check ⇒ the label defaults to class-C (REJECT). A
bundle-complete claim with no disjoint attestation ⇒ PENDING (not class-A yet; it is an OPEN class-C
row that BLOCKS the terminus — you cannot reach "done" by relabeling).

Mechanical checks (each auto-defaults to class-C on failure):
  1. GOAL-DUMP     — the actual VC was dumped and its obstacle NAMED (a term/hypotheses), not "timeout".
                     Absent, or a bare timeout/"unknown"/mischaracterization ⇒ REJECT (you didn't read it).
  2. REPRODUCER    — a <=10-line twin was bisected. Twin PROVES ⇒ REJECT (artifact localized elsewhere:
                     CFG/model/context — not a ceiling). Absent ⇒ REJECT.
  3. COQ-RESIDUAL  — the WP->Coq escalation was ACTUALLY RUN. Not attempted ⇒ REJECT (the mandatory
                     step). Coq CLOSED it ⇒ REJECT (class-C, closeable). Only attempted-AND-failed is eligible.
  4. STORE-BLOAT   — proves-in-isolation ∧ times-out-in-context ⇒ class-C (store-bloat), NEVER a ceiling.
Then: disjoint_attestation.verdict == "ceiling" ⇒ PASS(CEILING-ATTESTED);
      missing/null ⇒ PENDING(needs disjoint judge — blocks terminus);
      "missing-hyp"/"closeable" ⇒ REJECT (the judge refuted the ceiling).

Usage:  no_ceiling_gate.py <claims.json>   # gate class-A/ceiling claims
        no_ceiling_gate.py --selftest       # calibrate: catch fakes, pass a genuine attested ceiling
Exit 0 = every ceiling claim is genuine+attested; 1 = at least one REJECT or PENDING; 2 = usage.

Descriptor schema (claims.json):
  {"claims": [
    {"id": "...", "claim": "class-A",
     "goal_dump":   {"present": true|false, "obstacle": "<named term/why, or empty>"},
     "reproducer":  {"present": true|false, "twin_verdict": "fails"|"proves"|"no-twin"|null},
     "coq_residual":{"attempted": true|false, "verdict": "failed"|"closed"|null},
     "store_bloat": {"proves_in_isolation": true|false, "times_out_in_context": true|false},
     "disjoint_attestation": {"judge": "<who>"|null, "verdict": "ceiling"|"missing-hyp"|"closeable"|null}}]}
"""
import json
import sys

# obstacle strings that are NOT a real diagnosis (a bare tool symptom, not a read goal)
_NON_OBSTACLES = {"", "timeout", "times out", "timed out", "unknown", "hard", "smt-hard",
                  "store-bloat", "store bloat", "wall", "trivial identical fact", "n/a"}


def _mechanical_failures(c):
    """Return the list of reasons this claim is NOT eligible for a ceiling label (class-C defaults)."""
    fails = []
    gd = c.get("goal_dump") or {}
    if not gd.get("present"):
        fails.append("GOAL-DUMP absent — the actual VC was never dumped/read (you did not read the goal)")
    elif (gd.get("obstacle") or "").strip().lower() in _NON_OBSTACLES:
        fails.append(f"GOAL-DUMP obstacle is a bare tool-symptom, not a named diagnosis "
                     f"({gd.get('obstacle')!r}) — 'it timed out' is not reading the goal")

    rp = c.get("reproducer") or {}
    tv = rp.get("twin_verdict")
    if not rp.get("present"):
        fails.append("REPRODUCER absent — no minimal-twin bisect was run")
    elif tv == "proves":
        fails.append("REPRODUCER: the minimal twin PROVES — the property is closeable; the artifact is "
                     "localized elsewhere (CFG/model/context), NOT a ceiling -> class-C")

    cq = c.get("coq_residual") or {}
    if not cq.get("attempted"):
        fails.append("COQ-RESIDUAL: the mandatory WP->Coq escalation was NOT run — class-A is ineligible "
                     "until Coq is attempted-and-failed (Coq's assumption/frame tactics beat store-bloat)")
    elif cq.get("verdict") == "closed":
        fails.append("COQ-RESIDUAL: Coq CLOSED the goal -> it was closeable -> class-C, not a ceiling")
    elif cq.get("verdict") != "failed":
        fails.append(f"COQ-RESIDUAL: verdict {cq.get('verdict')!r} is not a recorded attempted-and-failed")

    sb = c.get("store_bloat") or {}
    if sb.get("proves_in_isolation"):
        fails.append("STORE-BLOAT: proves 1/1 in isolation but times out in context -> class-C "
                     "(store-bloat: clear the context / Coq assumption / checkpoint-slice), NEVER a ceiling")
    return fails


def gate(claims):
    out = []
    for c in claims:
        cid = c.get("id", "<unnamed>")
        if str(c.get("claim", "")).lower() not in ("class-a", "ceiling", "class_a", "not-closeable"):
            out.append((cid, "PASS", "not a ceiling claim — gate N/A"))
            continue
        fails = _mechanical_failures(c)
        if fails:
            out.append((cid, "REJECT", "NOT a ceiling -> class-C. " + " | ".join(fails)))
            continue
        att = c.get("disjoint_attestation") or {}
        v = att.get("verdict")
        if v == "ceiling":
            out.append((cid, "PASS", f"CEILING-ATTESTED — bundle complete + disjoint judge "
                                     f"({att.get('judge')}) independently confirmed non-entailment"))
        elif v in ("missing-hyp", "closeable"):
            out.append((cid, "REJECT", f"disjoint judge ({att.get('judge')}) REFUTED the ceiling "
                                       f"({v}) -> class-C"))
        else:
            out.append((cid, "PENDING", "bundle complete but NO disjoint attestation — CEILING-CLAIM "
                                        "(PENDING); an open class-C row that BLOCKS the terminus"))
    return out


def report(title, results):
    bad = [r for r in results if r[1] in ("REJECT", "FAIL", "PENDING")]
    mark = {"PASS": "ok ", "REJECT": "XX ", "FAIL": "XX ", "PENDING": ".. "}
    print(f"\n{title}")
    print("=" * 72)
    for cid, status, msg in results:
        print(f"  {mark.get(status, '   ')}{status:<8} {cid}: {msg}")
    print("=" * 72)
    print(f"  {len(bad)} REJECT/PENDING / {len(results)} claims "
          f"(class-A stands only on PASS)\n")
    return bool(bad)


def selftest():
    cases = [
        # fake ceilings — each must be caught
        {"id": "fake-storebloat", "claim": "class-A",
         "goal_dump": {"present": True, "obstacle": "valid_rd over t vs t1 (a real term)"},
         "reproducer": {"present": True, "twin_verdict": "fails"},
         "coq_residual": {"attempted": True, "verdict": "failed"},
         "store_bloat": {"proves_in_isolation": True, "times_out_in_context": True}},   # REJECT (store-bloat)
        {"id": "fake-no-coq", "claim": "class-A",
         "goal_dump": {"present": True, "obstacle": "to_sint32(12+12*vlen) peel"},
         "reproducer": {"present": True, "twin_verdict": "fails"},
         "coq_residual": {"attempted": False, "verdict": None},
         "store_bloat": {"proves_in_isolation": False}},                                # REJECT (no Coq)
        {"id": "fake-unread-goal", "claim": "class-A",
         "goal_dump": {"present": False, "obstacle": ""},
         "reproducer": {"present": True, "twin_verdict": "fails"},
         "coq_residual": {"attempted": True, "verdict": "failed"},
         "store_bloat": {"proves_in_isolation": False}},                                # REJECT (unread)
        {"id": "fake-twin-proves", "claim": "class-A",
         "goal_dump": {"present": True, "obstacle": "land-masked index bound"},
         "reproducer": {"present": True, "twin_verdict": "proves"},
         "coq_residual": {"attempted": True, "verdict": "failed"},
         "store_bloat": {"proves_in_isolation": False}},                                # REJECT (twin proves)
        {"id": "fake-bare-timeout", "claim": "class-A",
         "goal_dump": {"present": True, "obstacle": "timeout"},
         "reproducer": {"present": True, "twin_verdict": "fails"},
         "coq_residual": {"attempted": True, "verdict": "failed"},
         "store_bloat": {"proves_in_isolation": False}},                                # REJECT (bare symptom)
        {"id": "coq-closed-it", "claim": "class-A",
         "goal_dump": {"present": True, "obstacle": "nonlinear block_size*num"},
         "reproducer": {"present": True, "twin_verdict": "fails"},
         "coq_residual": {"attempted": True, "verdict": "closed"},
         "store_bloat": {"proves_in_isolation": False}},                                # REJECT (Coq closed)
        # bundle complete, no attestation -> PENDING
        {"id": "pending-unattested", "claim": "class-A",
         "goal_dump": {"present": True, "obstacle": "cbits xor-extensionality, irreducible"},
         "reproducer": {"present": True, "twin_verdict": "fails"},
         "coq_residual": {"attempted": True, "verdict": "failed"},
         "store_bloat": {"proves_in_isolation": False},
         "disjoint_attestation": {"judge": None, "verdict": None}},                     # PENDING
        # genuine, disjointly attested ceiling -> PASS
        {"id": "genuine-attested", "claim": "class-A",
         "goal_dump": {"present": True, "obstacle": "Why3 cbits: no bit-extensionality lemma"},
         "reproducer": {"present": True, "twin_verdict": "fails"},
         "coq_residual": {"attempted": True, "verdict": "failed"},
         "store_bloat": {"proves_in_isolation": False},
         "disjoint_attestation": {"judge": "ollama@$(cat ~/.local-llm-machine-ip.txt)", "verdict": "ceiling"}},  # PASS
        # a non-ceiling row -> gate N/A -> PASS
        {"id": "a-class-c-row", "claim": "class-C",
         "goal_dump": {"present": True, "obstacle": "missing \\valid(p)"}},             # PASS (N/A)
    ]
    results = gate(cases)
    got = {cid: st for cid, st, _ in results}
    expect = {"fake-storebloat": "REJECT", "fake-no-coq": "REJECT", "fake-unread-goal": "REJECT",
              "fake-twin-proves": "REJECT", "fake-bare-timeout": "REJECT", "coq-closed-it": "REJECT",
              "pending-unattested": "PENDING", "genuine-attested": "PASS", "a-class-c-row": "PASS"}
    report("NO-CEILING GATE — selftest", results)
    ok = got == expect
    # discriminating band: some rejected, not all, and at least one genuine PASS
    rej = sum(1 for v in got.values() if v == "REJECT")
    band_ok = 0 < rej < len(got) and "PASS" in got.values()
    print("selftest:", "PASS — gate discriminates (catches every fake, passes the attested one)"
          if (ok and band_ok) else f"FAIL — got {got}\n              expected {expect}")
    return 0 if (ok and band_ok) else 1


def main():
    args = sys.argv[1:]
    if args == ["--selftest"]:
        sys.exit(selftest())
    if len(args) != 1:
        print("usage: no_ceiling_gate.py <claims.json> | --selftest")
        sys.exit(2)
    doc = json.load(open(args[0]))
    failed = report(f"NO-CEILING GATE — {args[0]}", gate(doc.get("claims", [])))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
