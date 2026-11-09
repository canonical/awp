#!/usr/bin/env bash
# Level 3, C: a FIPS campaign on Mbed TLS through the interactive harness —
# the `--driver fips` counterpart of gzip-test.sh (fips-skill-spec.md 8: "a
# FIPS smoke test needs a module target"; this script is that target being
# chosen: a real cryptographic library, per fips-sl's "a library target is the
# cleaner default").
#
#   tests/c/mbed-tls-test.sh               in a copy of autowp-c-base/ready (LXD)
#   WORKSHOP=1 tests/c/mbed-tls-test.sh    in the generated project's workshop:
#                                          the toolchain comes from the
#                                          frama-c-sdk SDK, not the base
#   KEEP=0                                 deletes the container (or the
#                                          workshop and its project) at exit;
#                                          the default keeps them, so the
#                                          FIPS documents survive the run
#
# Workshop mode: WORKSHOP_BASE, WORKSHOP_TRY, WORKSHOP_DIR (tests/lib/workshop.sh).
#
# SETUP_ONLY=1 stops after the setup checks (M.0, and W.1-W.4 in workshop
# mode): no token needed, no harness session, minutes instead of hours.
#
# Environment:
#   MBEDTLS_TAG    the Mbed TLS release to clone (default mbedtls-3.6.7, an
#                  annotated tag; its commit is pinned below by SHA)
#   MBEDTLS_SHA    the commit the tag must resolve to (verified before the run)
#   FIPS_LEVEL     the target FIPS 140-3 security level for --level (default 4)
#   MBEDTLS_HOURS  the campaign budget (default 96)
#   ACCEPT_TOKEN_EXPIRY=1  accept an unknown token lifetime
#
# The defaults make this a full-scale run: FIPS 140-3 level 4 for 96 hours —
# the cost profile of acceptance.sh (the host session shares its usage limits
# for days). For a cheap smoke, pass FIPS_LEVEL=2 MBEDTLS_HOURS=2. The
# credential must outlive the run: secret_check_expiry refuses a token that
# would expire first (record its lifetime in the .created file, tests.md 7.1).
# Needs the fips driver (auto-wp.py --driver/--level, /fips, bin/fips-lint.sh
# and the time-loop driver table): until all four exist the script prints SKIP
# and exits 0, like smoke-test.sh does for creusot-launch. Needs the harness
# credential (tests.md 7, AUTOWP_TOKEN_FILE). Clones the pinned tag (M.0)
# before the credential is moved in, waits for the loop to stop, at most
# MBEDTLS_HOURS + 2 hours, then runs M.1-M.11 (and W.1-W.4 in workshop mode).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# This test's artifacts (the FIPS documents in the project) outlive the run by
# default: KEEP=1 keeps the container, or the workshop and its project
# directory; KEEP=0 restores delete-on-exit (the libs' own default).
KEEP=${KEEP:-1}
# shellcheck source=../lib/lxc.sh
. "$HERE/../lib/lxc.sh"
# shellcheck source=../lib/secret.sh
. "$HERE/../lib/secret.sh"

# --- the fips driver must exist; SKIP until it does --------------------------
PENDING=""
grep -q -- '--driver' <(python3 "$AUTOWP_REPO/auto-wp.py" --help 2>/dev/null) \
    || PENDING="$PENDING auto-wp.py --driver/--level"
[ -f "$AUTOWP_REPO/templates/c/commands/fips.md" ] || PENDING="$PENDING commands/fips.md"
[ -f "$AUTOWP_REPO/templates/c/tools/bin/fips-lint.sh" ] || PENDING="$PENDING bin/fips-lint.sh"
grep -q 'config/auto-wp.json' "$AUTOWP_REPO/templates/c/skills/time-loop/SKILL.md" \
    || PENDING="$PENDING the time-loop driver table"
if [ -n "$PENDING" ]; then
    echo "SKIP: the fips driver is not implemented yet:$PENDING (fips-skill-spec.md 6-7)"
    exit 0
fi

WORKSHOP=${WORKSHOP:-0}
CAMPAIGN_PROJECT=mbedtls-analyze
if [ "$WORKSHOP" = 1 ]; then
    # shellcheck source=../lib/workshop.sh
    . "$HERE/../lib/workshop.sh"
    ws_init "$CAMPAIGN_PROJECT"
fi
CAMPAIGN_SRC=mbedtls
CAMPAIGN_SRC_KIND=repo
CAMPAIGN_COMMIT_FILE=.autowp-mbedtls-commit
CAMPAIGN_WAKES=info
# shellcheck source=../lib/harness.sh
. "$HERE/../lib/harness.sh"

MBEDTLS_TAG=${MBEDTLS_TAG:-mbedtls-3.6.7}
MBEDTLS_SHA=${MBEDTLS_SHA:-068ff080b369adfac81509f9b57b2afabaf82dc5}
FIPS_LEVEL=${FIPS_LEVEL:-4}
HOURS=${MBEDTLS_HOURS:-96}
HARD_LIMIT=$(( (HOURS + 2) * 3600 ))
CMD="/time-loop $CAMPAIGN_SRC $HOURS"

# M.0: clone the pinned tag, verify its commit, add the local bare origin.
# Mirrors campaign_setup_c (grub) and campaign_setup_c_gzip (the checks of
# G.0): nothing else runs if it fails.
campaign_setup_c_mbedtls() {
    local c=$1
    autowp_exec_user "$c" "set -e; touch ~/.autowp-t0; sleep 1
        if [ $CAMPAIGN_GENERATED = 1 ]; then cd '$CAMPAIGN_DIR'
        else cd ~ && python3 auto-wp/auto-wp.py --c --driver fips --level $FIPS_LEVEL --harness '$HARNESS' mbedtls-analyze >/dev/null && cd mbedtls-analyze; fi
        git clone -q --branch '$MBEDTLS_TAG' https://github.com/Mbed-TLS/mbedtls.git mbedtls
        test \"\$(git -C mbedtls rev-parse HEAD)\" = '$MBEDTLS_SHA' \\
            || { echo 'mbedtls pin mismatch: pinned $MBEDTLS_SHA, got' \$(git -C mbedtls rev-parse HEAD) >&2; exit 2; }
        git init -q --bare ~/remote.git
        git remote add origin ~/remote.git
        git -C mbedtls rev-parse HEAD > ~/.autowp-mbedtls-commit"
}

# M.3: the study exists and its own machine gate accepts it — the fips
# counterpart of campaign_checks_c's C3.3 (rmf-report + rmf-lint).
fips_report_check() {
    local c=$1 id=$2 report="$CAMPAIGN_DIR/$CAMPAIGN_SRC-analysis-fips-report.md"
    if ! autowp_exec_user "$c" "test -s '$report'"; then
        fail "$id" "$CAMPAIGN_SRC-analysis-fips-report.md missing or empty"
    elif ! autowp_exec_user "$c" \
            "cd '$CAMPAIGN_DIR' && bin/fips-lint.sh $CAMPAIGN_SRC-analysis-fips-report.md >/dev/null 2>&1"; then
        fail "$id" "bin/fips-lint.sh fails on $CAMPAIGN_SRC-analysis-fips-report.md"
    else
        pass "$id"
    fi
}

# campaign_checks_c_fips: campaign_checks_c (tests.md 5.3, C3.2-C3.9) with the
# fips report and linter of M.3. Mirrors it locally; promote to harness.sh if a
# second fips campaign test appears.
campaign_checks_c_fips() {
    local c=$1 hours=$2 p=$3 st S start deadline wakes ncyc longest last
    local D=$CAMPAIGN_DIR X=$CAMPAIGN_SRC base
    base=$(autowp_exec_user "$c" "cat ~/$CAMPAIGN_COMMIT_FILE")
    k1 "$c" "$D/$X" "$base" "${p}2"
    fips_report_check "$c" "${p}3"
    S=$(state_json "$c" "$D/$X-analysis-acsl/time-loop.state")
    if [ "$(json_get "$S" error)" = missing ]; then
        fail "${p}4" "time-loop.state does not exist"
        fail "${p}5" "no state file"; fail "${p}6" "no state file"; fail "${p}7" "no state file"
    else
        start=$(json_get "$S" start); deadline=$(json_get "$S" deadline)
        if [ -z "$start" ] || [ -z "$deadline" ]; then
            fail "${p}4" "start/deadline not found in the state file (format not recognised)"
        elif [ $(( deadline - start - hours * 3600 )) -gt 300 ] || [ $(( start + hours * 3600 - deadline )) -gt 300 ]; then
            fail "${p}4" "deadline - start = $(( deadline - start )) s, expected $(( hours * 3600 )) s +- 300"
        else
            pass "${p}4"
        fi
        wakes=$(python3 -c 'import json,sys; print(" ".join(map(str, json.loads(sys.argv[1])["wakes"])))' "$S")
        n=$(wc -w <<<"$wakes")
        if [ "$CAMPAIGN_WAKES" = info ]; then info "${p}5" "$n wake(s) recorded in the state file"
        elif [ "$n" -ge 2 ]; then pass "${p}5"
        else fail "${p}5" "no wake recorded in the state file"; fi
        ncyc=$(python3 -c 'import json,sys; print(" ".join(map(str, json.loads(sys.argv[1])["cycles"])))' "$S")
        local log missing=""
        log=$(autowp_exec_user "$c" 'git -C ~/remote.git log --all --format="%s %b" 2>/dev/null' || true)
        if grep -qiE 'cycle' <<<"$log"; then
            for n in $ncyc; do
                grep -qiE "cycle[ _#-]*0*$n([^0-9]|\$)" <<<"$log" || missing="$missing $n"
            done
            if [ -z "$missing" ]; then pass "${p}6"
            else
                # Labels lag: a push at the start of cycle N carries cycle
                # N-1's work, so per-cycle label matching under-counts. The
                # loop records every push in the state log ('checkpoint
                # <hash> pushed'); M.6 verifies each recorded hash is
                # actually in ~/remote.git.
                local allh h unverified="" hashes
                allh=$(autowp_exec_user "$c" \
                    'git -C /home/ubuntu/remote.git log --all --format=%h' 2>/dev/null || true)
                hashes=$(autowp_exec_user "$c" \
                    "grep -oE 'checkpoint [0-9a-f]{7,40} pushed' '$D/$X-analysis-acsl/time-loop.state' 2>/dev/null | awk '{print \$2}'" \
                    || true)
                for h in $hashes; do
                    grep -qE "^$h" <<<"$allh" || unverified="$unverified $h"
                done
                if [ -n "$hashes" ] && [ -z "$unverified" ]; then
                    pass "${p}6"
                    info "${p}6" "commit labels lag the state cycles; verified by hash: all $(wc -w <<<"$hashes") 'checkpoint <hash> pushed' entries are in ~/remote.git; label-unmatched state cycle(s):$missing"
                else
                    fail "${p}6" "no pushed commit for cycle(s)$missing; push(es) missing from ~/remote.git:${unverified:- none recorded}"
                fi
            fi
        else
            local ncommits
            ncommits=$(grep -c . <<<"$log" || true)
            if [ "$ncommits" -ge "$(wc -w <<<"$ncyc")" ] && [ "$ncommits" -gt 0 ]; then
                pass "${p}6"; info "${p}6" "commit messages do not name cycles; compared counts ($ncommits >= $(wc -w <<<"$ncyc"))"
            else
                fail "${p}6" "$ncommits commit(s) in ~/remote.git for $(wc -w <<<"$ncyc") cycle(s)"
            fi
        fi
        longest=$(python3 -c 'import sys; w=sorted(map(int, sys.argv[1].split())); print(max([b-a for a,b in zip(w,w[1:])] or [0]))' "${wakes:-0}")
        last=$(tr ' ' '\n' <<<"$wakes" | sort -n | tail -1)
        if [ -z "$deadline" ] || [ -z "$last" ]; then
            fail "${p}7" "deadline or wakes not found in the state file"
        elif [ "$last" -le $(( deadline + longest )) ]; then
            pass "${p}7"
        else
            fail "${p}7" "last wake $(date -u -d "@$last" +%FT%TZ) is after deadline + longest cycle ($longest s)"
        fi
    fi
    secret_k2 "$c" "${p}8"
    k3 "$c" "${p}9"
}

# m11 <container> <id>: at least one unit with PROVED goals, plus the counts of
# what the run produced, as INFO. Same oracle as gzip-test.sh's g11 (its
# verdicts.tsv header skip already knows the `vo#` column of the fips join).
m11() {
    local c=$1 id=$2 counts proved
    counts=$(autowp_exec_user "$c" "cd '$CAMPAIGN_DIR' && python3 - '$CAMPAIGN_SRC'" <<'PY'
import os, re, sys
src = sys.argv[1]
ok = re.compile(r"\b(Valid|PROVED|GREEN)\b")
units, proved, goals = set(), set(), 0
for root, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d not in (".git", src, "framac-src", "macsl")]
    for f in files:
        if not f.endswith("verdicts.tsv"):
            continue
        for line in open(os.path.join(root, f), errors="replace"):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            cells = line.rstrip("\n").split("\t")
            if cells[0].strip().lower() in ("unit", "function", "sa#", "vo#"):
                continue
            units.add(cells[0].strip())
            if any(ok.search(x) for x in cells[1:]):
                proved.add(cells[0].strip())
                goals += 1
print(len(units), len(proved), goals)
PY
    ) || counts="0 0 0"
    read -r units proved_units goals <<<"$counts"
    info "$id" "units in verdicts: $units; units with PROVED goals: $proved_units; PROVED rows: $goals"
    proved=$proved_units
    if [ "${proved:-0}" -ge 1 ]; then pass "$id"
    else fail "$id" "no unit has PROVED goals; read the pane transcript before blaming the skills (rate limits, slow onboarding of a large library)"; fi
}

# --- workshop mode ------------------------------------------------------------

# W.3: the toolchain is the SDK's, before the campaign starts.
ws_toolchain() {
    local out
    out=$(autowp_exec_user "$WS" 'frama-c -version; frama-c -wp-detect 2>&1 | grep -ciE "alt-ergo|z3"; echo "switch=$FRAMA_C_SDK_SWITCH src=$FRAMA_C_SDK_SRC"; command -v frama-c' 2>&1) || true
    if grep -q '^32\.1' <<<"$out" && grep -q '^switch=framac-coq8 src=/' <<<"$out" \
        && grep -qx '/opt/frama-c-sdk/bin/frama-c' <<<"$out"; then
        pass W.3
    else
        fail W.3 "frama-c 32.1 from /opt/frama-c-sdk not found: $(tr '\n' ' ' <<<"$out")"
    fi
}

# W.4: after the setup, fetch-sources.sh linked framac-src to the SDK's
# sources instead of downloading them, and framac-onboard.sh accepts the SDK.
ws_sdk_reuse() {
    local out
    out=$(autowp_exec_user "$WS" "cd '$CAMPAIGN_DIR' && readlink framac-src; bin/framac-onboard.sh '$CAMPAIGN_SRC' --sample 1 2>&1 | grep -m1 -E \"opam switch '[^']*':\"" 2>&1) || true
    if grep -qx '/opt/frama-c-sdk/src/frama-c-32\.1' <<<"$out" && grep -q 'present *PASS *(frama-c-sdk SDK' <<<"$out"; then
        pass W.4
    else
        fail W.4 "framac-src not linked to the SDK, or framac-onboard.sh does not accept it: $(tr '\n' ' ' <<<"$out")"
    fi
}

# --- setup ---------------------------------------------------------------------

SETUP_ONLY=${SETUP_ONLY:-0}
[ "$SETUP_ONLY" = 1 ] || { secret_check_file && secret_check_expiry "$HOURS"; } || exit 1
if [ "$WORKSHOP" = 1 ]; then
    C=$WS
    ws_generate c frama-c-sdk --driver fips --level "$FIPS_LEVEL" \
        || { autowp_summary; exit 1; }
    ws_adapt git               # mbedtls comes from a git clone; the workshop
                               # base may not ship git
    ws_launch || { autowp_summary; exit 1; }
    ws_toolchain
    ws_egress
    [ "$SETUP_ONLY" = 1 ] || ws_install_harness
else
    if [ "${CHECK_ONLY:-0}" = 1 ]; then
        # Run the end-of-run checks against an existing (kept) container —
        # e.g. after the test driver was interrupted while the campaign in
        # the container kept going. CT names the container.
        C=${CT:?CHECK_ONLY=1 needs CT=<container name>}
        note "CHECK_ONLY=1: running the M-checks against $C"
    else
        autowp_require_lxc
        autowp_install_trap
        autowp_ensure_pool
        autowp_ensure_network
        C=autowp-c-mbedtls-$(autowp_timestamp)
        autowp_copy_snapshot autowp-c-base ready "$C"
        autowp_wait_ready "$C"
        autowp_egress_check "$C"
        autowp_push_project "$C"
    fi
fi

# M.0: clone the pinned tag, verify the commit. Nothing else runs if it fails.
if [ "${CHECK_ONLY:-0}" = 1 ]; then
    note "CHECK_ONLY=1: skipping M.0 (the project is already in $C)"
else
if setup=$(campaign_setup_c_mbedtls "$C" 2>&1); then
    pass M.0
    info M.0 "mbedtls at $MBEDTLS_TAG ($MBEDTLS_SHA); target FIPS 140-3 level $FIPS_LEVEL"
else
    fail M.0 "$(tail -3 <<<"$setup" | tr '\n' ' ')"
    autowp_summary
    exit 2
fi
fi
[ "$WORKSHOP" = 1 ] && ws_sdk_reuse
if [ "$SETUP_ONLY" = 1 ]; then
    info setup "SETUP_ONLY=1: stopping before the campaign"
    autowp_summary
    exit
fi
if [ "${CHECK_ONLY:-0}" = 1 ]; then
    campaign_checks_c_fips "$C" "$HOURS" M.
    report_check_c "$C" M.10 interim
    m11 "$C" M.11
    autowp_summary
    exit 0
fi

# --- the campaign ----------------------------------------------------------------

secret_push "$C"
if ! harness_start "$C" "$CAMPAIGN_DIR" "$CMD"; then
    fail M.1 "harness did not start"
    autowp_summary
    exit 1
fi
if harness_confirm "$C" time-loop 300; then pass M.1; else fail M.1 "time-loop not loaded within 5 minutes (K4)"; fi

wait_loop_stopped "$C" "$(campaign_state_file)" "$HARD_LIMIT" || true
harness_pane "$C" | tail -15 | sed 's/^/    | /'
harness_stop "$C"

campaign_checks_c_fips "$C" "$HOURS" M.
report_check_c "$C" M.10 interim
m11 "$C" M.11

autowp_summary
