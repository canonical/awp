#!/usr/bin/env bash
# framac-mutation-probe.sh — Gate C non-vacuity check for ONE proved unit.
#
# A proof is only worth something if BREAKING the code breaks the proof. We apply
# a few generic mutations to the unit's .c body and re-run WP; the unit's contract
# lives in its (unchanged) header, found via the corpus -I, so the mutated body is
# checked against the real spec. At least one APPLICABLE mutation must reduce the
# proved-goal count, else the spec is vacuous / toothless. This is also the
# consistency backstop for a definitional `axiomatic`: an inconsistent axiomatic
# would prove the mutant too, so a mutant that still fully proves flags vacuity.
#
# Prints: TEETH | VACUOUS | INCONCLUSIVE | NOFILE  (and a one-line detail)
# Usage:  ./framac-mutation-probe.sh <unit-rel.c>   e.g.  Numeric/accumulate.c
set -uo pipefail
rel="$1"
SRC="framac/$rel"
[ -f "$SRC" ] || { echo "NOFILE"; exit 0; }
INCS="-Iframac -Iframac/BinarySearch -Iframac/Heap -Iframac/MinMax -Iframac/Mutating -Iframac/Nonmutating -Iframac/Numeric -Iframac/Sorting -Iframac/Stack -include typedefs.h -include size_type_pair.h -include Stack.h"

# Echo "<proved> <total>" for a given .c, or "ERR" if it does not parse/translate.
wp_counts() {
  local out
  out=$(frama-c -machdep gcc_x86_64 -cpp-extra-args="$INCS" \
         -wp -wp-rte -wp-prover alt-ergo,z3 -wp-timeout 15 "$1" 2>&1 \
        | grep -oE 'Proved goals: +[0-9]+ */ *[0-9]+' | head -1)
  [ -n "$out" ] && echo "$out" | grep -oE '[0-9]+' | paste -sd' ' || echo "ERR"
}

# Generic mutations as (pattern, replacement) pairs. CRITICAL: a mutation must hit
# EXECUTABLE CODE, never an ACSL comment — these files put loop invariants / asserts
# (/*@..*/ and //@..) right before the code, so a naive "first occurrence" would
# mutate the SPEC and the proof would still pass (a false VACUOUS, e.g. search.c).
# apply_outside_acsl edits the first occurrence that is NOT inside an ACSL span.
muts=(' + | - ' '++|--' ' <= | < ' ' < | <= ' ' == | != ' ' - | + ')

# apply_outside_acsl <file> <pat> <rep> : in-place first-occurrence sub outside ACSL.
apply_outside_acsl() {
  perl -0777 -i -e '
    my ($pat,$rep)=($ENV{MP_PAT},$ENV{MP_REP});
    my $f = do { local $/; <> };
    # split keeping ACSL spans as their own segments
    my @seg = split m{(/\*\@.*?\*/|//\@[^\n]*)}s, $f;
    my $done=0;
    for my $i (0..$#seg){
      next if $seg[$i] =~ m{^/\*\@} || $seg[$i] =~ m{^//\@};   # ACSL: skip
      if(!$done){ $done=1 if $seg[$i] =~ s/\Q$pat\E/$rep/; }    # first code hit only
    }
    print join("",@seg);
  ' "$1"
}

applied=0; broke=0; detail=""
tmp=$(mktemp --suffix=.c)
trap 'rm -f "$tmp"' EXIT
for m in "${muts[@]}"; do
  pat="${m%%|*}"; rep="${m##*|}"
  cp "$SRC" "$tmp"
  MP_PAT="$pat" MP_REP="$rep" apply_outside_acsl "$tmp"
  cmp -s "$SRC" "$tmp" && continue        # mutation did not change executable code
  applied=$((applied+1))
  c=$(wp_counts "$tmp")
  [ "$c" = "ERR" ] && continue            # mutant did not parse -> not a useful probe
  set -- $c; p="$1"; t="$2"
  if [ "${p:-0}" -lt "${t:-0}" ]; then broke=$((broke+1)); detail="mutation [$pat ->$rep] -> $p/$t"; break; fi
done

if   [ "$broke"   -gt 0 ]; then echo "TEETH        $detail"
elif [ "$applied" -gt 0 ]; then echo "VACUOUS      $applied mutation(s) applied, none broke a goal"
else                            echo "INCONCLUSIVE no generic mutation applied (inspect manually)"
fi
