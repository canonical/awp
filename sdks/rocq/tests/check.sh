#!/usr/bin/env bash
# Runs inside a workshop that has the rocq SDK (run.sh calls it as
# the workshop user, through a login shell). Copies cases/ to a work
# directory, builds and checks every case, and prints PASS:/FAIL: per check
# and a SUMMARY: line. Exit 0 only if every check passed.
#
#   check.sh [WORKDIR]          (default: <this directory>/work)
#
# Logs of every step stay in WORKDIR/logs/.
set -uo pipefail
T=$(cd "$(dirname "$0")" && pwd)
W=${1:-$T/work}
ROCQ_VERSION=${ROCQ_VERSION:-9.2}
TMO=${TMO:-1200}            # seconds allowed to one build step

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1: ${2:-}"; }
# The last lines of a log, on one line, for a FAIL message.
tl() { tail -"${2:-4}" "$1" 2>/dev/null | tr '\n' ' '; }
# A log flattened to one line, so that a regex can span several lines.
flat() { tr '\n' ' ' < "$1"; }
# Runs a command in a directory, output to a log; returns its status.
step() { local dir=$1 log=$2; shift 2; (cd "$dir" && timeout "$TMO" "$@") > "$log" 2>&1; }

rm -rf "$W"; mkdir -p "$W/logs"
cp -r "$T/cases/." "$W/"
L=$W/logs
echo "--- work directory $W"

# --- 1. The environment ------------------------------------------------------
out=$L/env.log
{
    coqc --version; rocq --version
    echo "coqc=$(command -v coqc)"; echo "rocq=$(command -v rocq)"
    echo "where=$(coqc -where)"
    for t in coqtop coqdep coqchk rocqchk coqdoc coq_makefile dune ocamlfind ocamlopt ocamlc rg; do
        p=$(command -v "$t") && echo "tool $t=$p" || echo "MISSING $t"
    done
    echo "ROCQ_PYTHON_BIN=${ROCQ_PYTHON_BIN:-unset}"
    "${ROCQ_PYTHON_BIN:-/nonexistent}" --version
    echo "dune $(dune --version)"; echo "ocamlfind $(ocamlfind ocamlopt -version)"
    coqc -config | grep -E '^(COQLIB|ROCQLIB|COQ_NATIVE_COMPILER_DEFAULT)='
} > "$out" 2>&1
if grep -q "The Rocq Prover, version $ROCQ_VERSION" "$out" \
    && [ "$(grep -c "version $ROCQ_VERSION" "$out")" -ge 2 ] \
    && grep -q "^coqc=/opt/rocq/opam/rocq/bin/coqc$" "$out" \
    && grep -q "^where=/opt/rocq/opam/rocq/lib/coq$" "$out" \
    && ! grep -q "^MISSING" "$out" && grep -q "^Python 3" "$out"; then
    pass "env.tools"
else
    fail "env.tools" "$(grep -E 'MISSING|version|coqc=|where=|Python|PYTHON' "$out" | tr '\n' ' ')"
fi
grep -E "^(dune|ocamlfind|COQ_NATIVE)" "$out" | sed 's/^/INFO: /'
# The switch is read-only for the user: nothing gets opam-installed into it.
if [ ! -w /opt/rocq/opam/rocq/lib/coq/user-contrib ] && [ ! -w /opt/rocq/opam/rocq/bin ]; then
    pass "env.read-only-switch"
else
    fail "env.read-only-switch" "the SDK's switch is writable by $(id -un)"
fi

# --- 2. Every bundled library loads -------------------------------------------
# One Require per .vo shipped (Corelib, Stdlib, Ltac2), then Print Libraries
# must list them all.
mkdir -p "$W/libs"
CL=$(coqc -where)
{ (cd "$CL/theories" && find . -name '*.vo' | sed 's|^\./|Corelib/|')
  (cd "$CL/user-contrib" && find . -name '*.vo' | sed 's|^\./||'); } \
    | sed 's|\.vo$||; s|/|.|g' | sort > "$W/libs/modules.txt"
n=$(wc -l < "$W/libs/modules.txt")
{ awk '{print "Require " $0 "."}' "$W/libs/modules.txt"; echo "Print Libraries."; } > "$W/libs/All.v"
if step "$W/libs" "$L/libs.log" coqc -w none All.v; then
    loaded=$(grep -cE '^  (Corelib|Stdlib|Ltac2)\.' "$L/libs.log")
    if [ "$loaded" -ge "$n" ] && [ "$n" -gt 600 ]; then
        pass "libs.load-all ($n modules: $(cut -d. -f1 "$W/libs/modules.txt" | sort | uniq -c | awk '{printf "%s %s ", $2, $1}'))"
    else
        fail "libs.load-all" "$loaded of $n modules loaded"
    fi
else
    fail "libs.load-all" "$(tl "$L/libs.log")"
fi
for lib in Stdlib.ssr.ssreflect Stdlib.micromega.Lia Stdlib.funind.Recdef \
           Stdlib.extraction.Extraction Stdlib.Reals.Reals Ltac2.Ltac2; do
    grep -qx "$lib" "$W/libs/modules.txt" || fail "libs.has-$lib" "not shipped"
done

# --- 3. Multi-file project (cases/make, _RocqProject, -R theories AutoWP) -----
# Build tools a Rocq user needs besides Rocq: make for `rocq makefile`
# projects, the assembler and C compiler for ocamlopt (extracted code,
# dune executables, plugins).
missing_bt=""
for t in make as cc; do command -v "$t" >/dev/null || missing_bt="$missing_bt $t"; done
if [ -z "$missing_bt" ]; then pass "env.build-tools (make as cc)"
else fail "env.build-tools" "not on PATH:$missing_bt"; fi

# 3a. Compiled file by file in `rocq dep -sort` order with `rocq compile`:
# the proofs are checked even without make.
R=$W/make
vfiles=$(cd "$R" && echo theories/*.v)
# shellcheck disable=SC2086
if step "$R" "$L/rocq-dep.log" rocq dep -R theories AutoWP -sort $vfiles; then
    order=$(cat "$L/rocq-dep.log")
    : > "$L/rocq-compile.log"; ok=1
    for f in $order; do
        echo "### rocq compile $f" >> "$L/rocq-compile.log"
        (cd "$R" && timeout "$TMO" rocq compile -R theories AutoWP "$f") >> "$L/rocq-compile.log" 2>&1 \
            || { ok=0; echo "### FAILED $f" >> "$L/rocq-compile.log"; break; }
    done
    if [ "$ok" = 1 ] && [ -f "$R/theories/Audit.vo" ]; then
        pass "project.rocq-compile ($(wc -w <<<"$order") files in rocq dep order)"
    else
        fail "project.rocq-compile" "$(tl "$L/rocq-compile.log" 8)"
    fi
else
    fail "project.rocq-compile" "rocq dep: $(tl "$L/rocq-dep.log")"
fi
# Audit.v: Print Assumptions of every main theorem, all closed.
want=$(grep -c "^Print Assumptions" "$R/theories/Audit.v")
got=$(grep -c "^Closed under the global context" "$L/rocq-compile.log")
if [ "$got" -eq "$want" ] && ! grep -q "^Axioms:" "$L/rocq-compile.log"; then
    pass "project.print-assumptions ($got theorems closed under the global context)"
else
    fail "project.print-assumptions" "$got of $want closed; $(grep -A3 '^Axioms:' "$L/rocq-compile.log" | tr '\n' ' ')"
fi
if grep -nE '\b(Admitted|admit|Axiom|Parameter|Abort)\b' "$R"/theories/*.v > "$L/project-grep.log"; then
    fail "project.no-admitted" "$(tl "$L/project-grep.log")"
else
    pass "project.no-admitted"
fi
# The independent checker re-checks the compiled proofs.
if step "$R" "$L/project-rocqchk.log" rocqchk -silent -o -R theories AutoWP \
        AutoWP.Trees AutoWP.Compiler AutoWP.Sort AutoWP.Recursion \
    && grep -q "Axioms: <none>" "$L/project-rocqchk.log"; then
    pass "project.rocqchk (Trees Compiler Sort Recursion, no axiom)"
else
    fail "project.rocqchk" "$(tl "$L/project-rocqchk.log" 12)"
fi
# Why3's way of running Coq: coqtop -batch -l (the file becomes module Top).
if step "$R" "$L/project-coqtop.log" coqtop -batch -R theories AutoWP -l theories/Sort.v; then
    pass "project.coqtop-batch"
else
    fail "project.coqtop-batch" "$(tl "$L/project-coqtop.log")"
fi
if mkdir -p "$R/html" && step "$R" "$L/project-coqdoc.log" rocq doc -R theories AutoWP -d html $vfiles \
    && [ -f "$R/html/AutoWP.Sort.html" ]; then
    pass "project.coqdoc"
else
    fail "project.coqdoc" "$(tl "$L/project-coqdoc.log")"
fi

# 3b. The same sources built the usual way: rocq makefile + make, and
# coq_makefile from _CoqProject.
M=$W/make-mk
mkdir -p "$M"; cp -r "$T/cases/make/." "$M/"
if step "$M" "$L/make-makefile.log" rocq makefile -f _RocqProject -o Makefile \
    && step "$M" "$L/make-build.log" make -j"$(nproc)" \
    && [ -f "$M/theories/Audit.vo" ] \
    && [ "$(grep -c "^Closed under the global context" "$L/make-build.log")" -eq "$want" ]; then
    pass "make.build (rocq makefile + make)"
else
    fail "make.build" "$(tl "$L/make-build.log" 8) $(tl "$L/make-makefile.log")"
fi
C=$W/coqproject
mkdir -p "$C"; cp -r "$T/cases/make/theories" "$T/cases/make/_CoqProject" "$C/"
if step "$C" "$L/coqproject-makefile.log" coq_makefile -f _CoqProject -o Makefile.coq \
    && step "$C" "$L/coqproject-build.log" make -f Makefile.coq -j"$(nproc)" \
    && [ -f "$C/theories/Audit.vo" ]; then
    pass "make.coq_makefile (_CoqProject)"
else
    fail "make.coq_makefile" "$(tl "$L/coqproject-build.log" 6) $(tl "$L/coqproject-makefile.log")"
fi

# --- 4. Extraction to OCaml (from 3a), compiled and run ----------------------
X=$R/ocaml
if [ -f "$X/verified.ml" ] && [ -f "$X/verified.mli" ]; then
    pass "extract.generate (verified.ml: $(grep -cE '^(let|and) ' "$X/verified.ml") definitions)"
    if step "$X" "$L/extract-ocamlc.log" ocamlfind ocamlc -package str verified.mli verified.ml main.ml -o main.byte \
        && step "$X" "$L/extract-run-byte.log" ./main.byte \
        && diff "$L/extract-run-byte.log" "$X/expected.txt" > "$L/extract-diff-byte.log"; then
        pass "extract.ocamlc-run ($(tr '\n' ';' < "$L/extract-run-byte.log"))"
    else
        fail "extract.ocamlc-run" "$(tl "$L/extract-ocamlc.log") $(cat "$L/extract-diff-byte.log" 2>/dev/null | tr '\n' ' ')"
    fi
    if step "$X" "$L/extract-ocamlopt.log" ocamlfind ocamlopt -package str verified.mli verified.ml main.ml -o main.native \
        && step "$X" "$L/extract-run.log" ./main.native \
        && diff -q "$L/extract-run.log" "$X/expected.txt" >/dev/null; then
        pass "extract.ocamlopt-run"
    else
        fail "extract.ocamlopt-run" "$(tl "$L/extract-ocamlopt.log") $(tl "$L/extract-run.log")"
    fi
else
    fail "extract.generate" "no extracted verified.ml(i) in $X"
fi

# --- 5. dune: rocq.theory (two theories), rocq.extraction, executables -------
D=$W/dune
if step "$D" "$L/dune-theories.log" dune build --display short @theories/all @client/all \
    && [ -f "$D/_build/default/theories/Nat2.vo" ] && [ -f "$D/_build/default/client/Uses.vo" ]; then
    pass "dune.rocq-theory (dune $(dune --version), two theories)"
else
    fail "dune.rocq-theory" "$(tl "$L/dune-theories.log" 8)"
fi
if grep -q "Closed under the global context" "$L/dune-theories.log"; then
    pass "dune.print-assumptions"
else
    fail "dune.print-assumptions" "$(tl "$L/dune-theories.log")"
fi
if step "$D" "$L/dune-byte-build.log" dune build ./bin/main.bc \
    && step "$D" "$L/dune-byte.log" ./_build/default/bin/main.bc \
    && grep -qx "sum upto 100 = 5050" "$L/dune-byte.log"; then
    pass "dune.rocq-extraction-byte (rocq.extraction + bytecode executable)"
else
    fail "dune.rocq-extraction-byte" "$(tl "$L/dune-byte-build.log") $(tl "$L/dune-byte.log")"
fi
if step "$D" "$L/dune-exe-build.log" dune build ./bin/main.exe \
    && step "$D" "$L/dune-exe.log" ./_build/default/bin/main.exe \
    && grep -qx "sum upto 100 = 5050" "$L/dune-exe.log"; then
    pass "dune.rocq-extraction-native"
else
    fail "dune.rocq-extraction-native" "$(grep -m2 -E 'not found|Error' "$L/dune-exe-build.log" | tr '\n' ' ') $(tl "$L/dune-exe.log" 2)"
fi
# The deprecated Coq build language must still work with this dune.
if step "$W/dune-coq" "$L/dune-coq.log" dune build \
    && [ -f "$W/dune-coq/_build/default/theories/Legacy.vo" ]; then
    pass "dune.coq-theory (deprecated (using coq 0.10))"
else
    fail "dune.coq-theory" "$(tl "$L/dune-coq.log" 6)"
fi

# --- 6. Negative cases: each must fail with Rocq's expected message ------------
# First line of each file: (* EXPECT-FAIL: <ERE> *) or (* EXPECT-OK: <ERE> *).
# EXPECT-FAIL: coqc exits non-zero and its output (flattened to one line)
# matches the ERE. EXPECT-OK: coqc exits 0 and the output matches. An
# anomaly, an uncaught exception or a timeout never counts as a pass.
N=$W/negative
for f in "$N"/*.v; do
    name=$(basename "$f" .v)
    head1=$(head -1 "$f")
    kind=$(sed -nE 's/^\(\* EXPECT-(FAIL|OK): .*\*\)$/\1/p' <<<"$head1")
    re=$(sed -nE 's/^\(\* EXPECT-(FAIL|OK): (.*) \*\)$/\2/p' <<<"$head1")
    log=$L/negative-$name.log
    [ -n "$kind" ] && [ -n "$re" ] || { fail "negative.$name" "no EXPECT header"; continue; }
    step "$N" "$log" coqc -R . Neg "$name.v"; rc=$?
    if grep -qiE "anomaly|uncaught exception|Stack overflow" "$log" || [ "$rc" -ge 124 ]; then
        fail "negative.$name" "crash or timeout (rc=$rc): $(tl "$log")"
    elif [ "$kind" = FAIL ] && [ "$rc" -ne 0 ] && grep -q "^Error:" "$log" && flat "$log" | grep -qE "$re"; then
        pass "negative.$name (rejected: $(flat "$log" | grep -oE "$re" | head -1 | cut -c1-90))"
    elif [ "$kind" = OK ] && [ "$rc" -eq 0 ] && flat "$log" | grep -qE "$re" \
        && ! grep -q "Closed under the global context" "$log"; then
        pass "negative.$name (audit reveals: $(grep -A1 '^Axioms:' "$log" | grep -v '^Axioms:' | cut -d' ' -f1 | grep -v '^--' | tr '\n' ' '))"
    else
        fail "negative.$name" "rc=$rc, want $kind /$re/: $(tl "$log" 6)"
    fi
done

echo "SUMMARY: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
