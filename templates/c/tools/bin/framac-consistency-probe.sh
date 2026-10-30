#!/bin/sh
# framac-consistency-probe.sh — lower-bound integrity gate for definitional axiomatics (WS5.2).
# An inconsistent axiom set proves everything, so every green it yields is vacuous
# (coherent-and-wrong AT THE HARD BOUND, paper §10). This gate enforces, for any file declaring an
# `axiomatic`, that a *symbol-referencing* consistency-probe lemma exists and is UNPROVABLE.
#
# IMPORTANT (a real finding, see wp-gotchas.md): a bare `lemma \false;` is INSUFFICIENT — SMT will
# not instantiate quantified axioms without a trigger, so it misses quantified inconsistency
# (verified: contradictory `\forall x; g(x)==0` / `==1` did NOT prove a bare \false). The probe
# lemma MUST mention the axiomatic's logic symbols at a concrete point (e.g. a false equation like
# `gcd(a,0) == a+1`, or a self-contradiction `f(<args>) != f(<args>)`), so the axioms instantiate.
#
# Usage: ./framac-consistency-probe.sh FILE.c [-- frama-c flags]
# Exit 0 if OK (probe present and NOT provable); 1 if inconsistent (probe provable) or probe missing.
set -eu
[ -n "${1:-}" ] || { echo "usage: $0 FILE.c [-- frama-c flags]" >&2; exit 2; }
F="$1"; shift; [ "${1:-}" = "--" ] && shift || true; EXTRA="$*"
[ -f "$F" ] || { echo "no such file: $F" >&2; exit 2; }
eval "$(opam env --switch=framac-coq8 --set-switch)" 2>/dev/null || true

# axiomatic in this file or its sibling headers?
has_ax=no
grep -q 'axiomatic' "$F" && has_ax=yes
for h in "$(dirname "$F")"/*.h; do [ -f "$h" ] && grep -q 'axiomatic' "$h" && has_ax=yes; done 2>/dev/null
[ "$has_ax" = yes ] || { echo "CONSISTENCY-PROBE: no axiomatic in scope for $F — N/A"; exit 0; }

# a symbol-referencing probe lemma must exist (name contains consistency|vacuit|probe)
probe_lemma=$(grep -hoE 'lemma[[:space:]]+[A-Za-z0-9_]*([Cc]onsisten|[Vv]acuit|[Pp]robe)[A-Za-z0-9_]*' "$F" "$(dirname "$F")"/*.h 2>/dev/null | awk '{print $2}' | head -1 || true)
if [ -z "$probe_lemma" ]; then
  echo "CONSISTENCY-PROBE FAIL: $F declares an axiomatic but has NO consistency-probe lemma."
  printf '  Author a false lemma that REFERENCES the axiom symbols (a bare false-lemma is\n'
  printf '  insufficient -- SMT will not trigger quantified axioms). e.g.\n'
  printf '    /*@ lemma probe_consistency: f(0) == f(0)+1; */\n'
  exit 1
fi

out=$(eval frama-c -wp -wp-prover alt-ergo,z3 -wp-timeout 15 -wp-prop "$probe_lemma" $EXTRA "\"$F\"" 2>&1 || true)
res=$(echo "$out" | grep -oE 'Proved goals:[ ]*[0-9]+ / [0-9]+' | tail -1)
if echo "$res" | grep -qE '[1-9][0-9]* / '; then
  echo "CONSISTENCY-PROBE FAIL: the probe lemma '$probe_lemma' PROVED ($res) — axiom set INCONSISTENT;"
  echo "  every green from this axiomatic is vacuous."
  exit 1
fi
echo "CONSISTENCY-PROBE OK: probe lemma '$probe_lemma' is NOT provable ($res) — axioms consistent ($F)"
