#!/usr/bin/env bash
# Starts Claude Code in tmux inside a container and types a command
# (tests.md 3.5). Source it after lib/lxc.sh and lib/secret.sh.
#
#   harness_start   <container> <project-dir> '<command>'   steps 1-3
#   harness_confirm <container> <name> [timeout-s]          step 4 (K4)
#   harness_stop    <container>
#   harness_running <container>
#   harness_pane    <container>                             current screen
#
# The token comes from secret_push (tests.md 7), never from the command line.
# --dangerously-skip-permissions is used here and only here (tests.md 3.5).
# --bare is never used: it ignores the OAuth token (tests.md 3.3).

HARNESS_SESSION=${HARNESS_SESSION:-autowp}
# The Claude Code input box; override if the UI changes.
# The prompt character is followed by a space or, since Claude Code 2.1.3xx,
# a no-break space (U+00A0), which grep's ' ' does not match.
HARNESS_PROMPT_RE=${HARNESS_PROMPT_RE:-'(^|[│ ])(>|❯)( | )|\? for shortcuts'}

# Writes the launcher that reads the token into the environment and deletes
# the file (tests.md 7.1 step 3).
harness_write_launcher() {
    local c=$1
    autowp_exec_user "$c" 'mkdir -p ~/.local/bin && cat > ~/.local/bin/autowp-launch && chmod 755 ~/.local/bin/autowp-launch' <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ ! -s /run/autowp/token ]; then
    echo "autowp-launch: /run/autowp/token missing" >&2
    exit 1
fi
CLAUDE_CODE_OAUTH_TOKEN=$(cat /run/autowp/token)
export CLAUDE_CODE_OAUTH_TOKEN
rm -f /run/autowp/token
export DISABLE_AUTOUPDATER=1
exec claude --dangerously-skip-permissions
EOF
}

# Folder trust for the exact project path (tests.md 3.3), plus onboarding.
harness_trust() {
    local c=$1 dir=$2
    autowp_exec_user "$c" "python3 - '$dir'" <<'EOF'
import json, os, sys
p = os.path.expanduser("~/.claude.json")
try:
    d = json.load(open(p))
except (OSError, ValueError):
    d = {}
d["hasCompletedOnboarding"] = True
d.setdefault("projects", {}).setdefault(sys.argv[1], {})["hasTrustDialogAccepted"] = True
json.dump(d, open(p, "w"), indent=2)
s = os.path.expanduser("~/.claude/settings.json")
os.makedirs(os.path.dirname(s), exist_ok=True)
try:
    st = json.load(open(s))
except (OSError, ValueError):
    st = {}
st["skipDangerousModePermissionPrompt"] = True
json.dump(st, open(s, "w"), indent=2)
EOF
}

harness_pane() {
    autowp_exec_user "$1" "tmux capture-pane -p -t $HARNESS_SESSION 2>/dev/null"
}

harness_running() {
    autowp_exec_user "$1" "tmux has-session -t $HARNESS_SESSION 2>/dev/null"
}

# harness_start <container> <project-dir> '<command>'
# The token must already be in /run/autowp/token (secret_push).
harness_start() {
    local c=$1 dir=$2 cmd=$3 i
    harness_write_launcher "$c"
    harness_trust "$c" "$dir"
    if harness_running "$c"; then
        echo "ERROR: tmux session $HARNESS_SESSION already running in $c" >&2
        return 1
    fi
    autowp_exec_user "$c" "date -u +%s > ~/.autowp-harness-start; \
        tmux new-session -d -s $HARNESS_SESSION -x 220 -y 50 -c '$dir' ~/.local/bin/autowp-launch"
    # 2. wait for the input prompt, up to 120 s
    for i in $(seq 1 60); do
        if harness_pane "$c" | grep -qE "$HARNESS_PROMPT_RE"; then
            break
        fi
        if ! harness_running "$c"; then
            echo "ERROR: the harness exited before showing its prompt" >&2
            return 1
        fi
        sleep 2
    done
    if ! harness_pane "$c" | grep -qE "$HARNESS_PROMPT_RE"; then
        echo "ERROR: no input prompt after 120 s; screen:" >&2
        harness_pane "$c" | tail -20 >&2
        return 1
    fi
    # 3. type literally, wait for slash-command completion, then Enter
    autowp_exec_user_argv "$c" tmux send-keys -t "$HARNESS_SESSION" -l "$cmd"
    sleep 2
    autowp_exec_user_argv "$c" tmux send-keys -t "$HARNESS_SESSION" Enter
    return 0
}

# Newest transcript under ~/.claude/projects/ (printed path).
harness_transcript() {
    autowp_exec_user "$1" 'ls -t ~/.claude/projects/*/*.jsonl 2>/dev/null | head -n1'
}

# harness_confirm <container> <command-or-skill-name> [timeout]: step 4.
harness_confirm() {
    local c=$1 name=$2 timeout=${3:-300} waited=0 t
    while [ "$waited" -lt "$timeout" ]; do
        t=$(harness_transcript "$c")
        if [ -n "$t" ] && autowp_exec_user "$c" \
            "find '$t' -newer ~/.autowp-harness-start -print -quit | grep -q . \
             && grep -qE '<command-name>/?$name</command-name>|\"skill\": *\"$name\"|/$name ' '$t'"; then
            return 0
        fi
        sleep 10
        waited=$((waited + 10))
    done
    return 1
}

harness_stop() {
    local c=$1
    autowp_exec_user "$c" "tmux send-keys -t $HARNESS_SESSION C-c 2>/dev/null; sleep 1; \
        tmux send-keys -t $HARNESS_SESSION C-c 2>/dev/null; sleep 2; \
        tmux kill-session -t $HARNESS_SESSION 2>/dev/null; true"
}

# --- common campaign steps and checks (tests.md 3.4, 4) ---------------------

# The campaign the checks look at. The defaults are the GRUB campaign of
# smoke-test.sh and acceptance.sh; gzip-test.sh sets its own (tests.md 5.5).
#   CAMPAIGN_PROJECT   project directory under ~ (foobar)
#   CAMPAIGN_SRC       source directory in the project, the XXX of /time-loop (grub)
#   CAMPAIGN_SRC_KIND  repo: the source is its own clone (K1 against its HEAD);
#                      tracked: the source is committed in the project (K1
#                      against the import commit)
#   CAMPAIGN_COMMIT_FILE  file holding the K1 baseline commit
#   CAMPAIGN_WAKES     strict: fewer than two wakes fails C3.5; info: reported only
#   CAMPAIGN_LINT      1: the report check also runs bin/rmf-lint.sh on the report
#   CAMPAIGN_DIR       absolute path of the project in the guest (default
#                      $AUTOWP_HOME/$CAMPAIGN_PROJECT; /project in a workshop)
#   CAMPAIGN_GENERATED 1: the project already exists (generated on the host
#                      for a workshop); the setup does not run auto-wp.py
CAMPAIGN_PROJECT=${CAMPAIGN_PROJECT:-foobar}
CAMPAIGN_SRC=${CAMPAIGN_SRC:-grub}
CAMPAIGN_SRC_KIND=${CAMPAIGN_SRC_KIND:-repo}
CAMPAIGN_COMMIT_FILE=${CAMPAIGN_COMMIT_FILE:-.autowp-grub-commit}
CAMPAIGN_WAKES=${CAMPAIGN_WAKES:-strict}
CAMPAIGN_LINT=${CAMPAIGN_LINT:-0}
CAMPAIGN_DIR=${CAMPAIGN_DIR:-$AUTOWP_HOME/$CAMPAIGN_PROJECT}
CAMPAIGN_GENERATED=${CAMPAIGN_GENERATED:-0}

# The state file of the campaign's time-loop.
campaign_state_file() {
    echo "$CAMPAIGN_DIR/$CAMPAIGN_SRC-analysis-acsl/time-loop.state"
}

# campaign_setup_c <container>: the level 2 steps, bin/fetch-sources.sh as the
# README runs it, and a local bare origin (tests.md 3.4). opam is already
# initialised in the base (provision.sh step 3).
campaign_setup_c() {
    local c=$1
    autowp_exec_user "$c" 'set -e; touch ~/.autowp-t0; sleep 1
        cd ~
        python3 auto-wp/auto-wp.py --c foobar
        cd foobar
        git clone -q https://gitlab.freedesktop.org/gnu-grub/grub.git
        bin/fetch-sources.sh
        git init -q --bare ~/remote.git
        git remote add origin ~/remote.git
        git -C grub rev-parse HEAD > ~/.autowp-grub-commit'
}

# The gzip 1.9 archive of gzip-test.sh (gzip-test.md 2): mirrors tried in
# order, the pinned sha256, and the fingerprint of the key that signed it.
GZIP_MIRRORS="https://mirror.us-midwest-1.nexcess.net/gnu//gzip https://ftp.gnu.org/gnu/gzip https://ftpmirror.gnu.org/gzip https://mirrors.kernel.org/gnu/gzip https://mirror.csclub.uwaterloo.ca/gnu/gzip"
GZIP_SHA256=6dbd6307d88d866bea0d0b39aa14506a6a092eee5bcdc62f0c070ef8ea47e99c
GZIP_SIGNER=155D3FC500C834486D1EEA677FD9FCCB000BEEEE
GNU_KEYRING_URL=https://ftp.gnu.org/gnu/gnu-keyring.gpg

# campaign_setup_c_gzip <container>: gzip-test.md 4. Generates gzip-analyze
# (unless CAMPAIGN_GENERATED=1: then works in $CAMPAIGN_DIR as it is),
# downloads gzip-1.9.zip from the first mirror that answers, checks its sha256
# and its GPG signature (G.0), unzips it, commits it as the K1 baseline, and
# adds a local bare origin. Prints "mirror: <url>"; exits 2 on a check failure.
campaign_setup_c_gzip() {
    local c=$1
    autowp_exec_user "$c" "set -e; touch ~/.autowp-t0; sleep 1
        if [ $CAMPAIGN_GENERATED = 1 ]; then cd '$CAMPAIGN_DIR'
        else cd ~ && python3 auto-wp/auto-wp.py gzip-analyze --c >/dev/null && cd gzip-analyze; fi
        got=
        for m in $GZIP_MIRRORS; do
            if curl -fsSL --max-time 300 -o gzip-1.9.zip \"\$m/gzip-1.9.zip\" &&
               curl -fsSL --max-time 60 -o gzip-1.9.zip.sig \"\$m/gzip-1.9.zip.sig\"; then
                got=\$m; break
            fi
        done
        [ -n \"\$got\" ] || { echo 'no mirror answered' >&2; exit 2; }
        echo \"mirror: \$got\"
        echo '$GZIP_SHA256  gzip-1.9.zip' | sha256sum -c --quiet || { echo 'sha256 mismatch' >&2; exit 2; }
        curl -fsSL --max-time 300 -o ~/gnu-keyring.gpg $GNU_KEYRING_URL
        gpgv --status-fd 1 --keyring ~/gnu-keyring.gpg gzip-1.9.zip.sig gzip-1.9.zip 2>/dev/null \
            | grep -q '^\[GNUPG:\] VALIDSIG $GZIP_SIGNER ' || { echo 'bad or foreign signature' >&2; exit 2; }
        unzip -q gzip-1.9.zip
        rm gzip-1.9.zip gzip-1.9.zip.sig
        [ -f gzip-1.9/configure ] && [ -f gzip-1.9/gzip.c ] || { echo 'unexpected archive layout' >&2; exit 2; }
        bin/fetch-sources.sh >/dev/null
        git add gzip-1.9
        git -c user.name=autowp-test -c user.email=autowp-test@localhost commit -qm 'import gzip-1.9'
        git rev-parse HEAD > ~/.autowp-gzip-commit
        git init -q --bare ~/remote.git
        git remote add origin ~/remote.git"
}

# k1 <container> <repo-dir> <commit> <id>: source untouched.
k1() {
    local c=$1 dir=$2 commit=$3 id=$4
    if autowp_exec_user "$c" "cd '$dir' && [ \"\$(git rev-parse HEAD)\" = '$commit' ] \
        && git diff --quiet HEAD && [ -z \"\$(git status --porcelain --untracked-files=no)\" ]"; then
        pass "$id"
    else
        fail "$id" "$dir changed: $(autowp_exec_user "$c" "cd '$dir' && git status --porcelain --untracked-files=no | head -5 | tr '\n' ' '")"
    fi
}

# k1_tracked <container> <project-dir> <src> <commit> <id>: source untouched,
# for a source committed in the project (gzip-test.sh). Untracked build output
# inside <src> is allowed, as for k1.
k1_tracked() {
    local c=$1 dir=$2 src=$3 commit=$4 id=$5
    if autowp_exec_user "$c" "cd '$dir' && git diff --quiet '$commit' -- '$src' \
        && [ -z \"\$(git status --porcelain --untracked-files=no -- '$src')\" ]"; then
        pass "$id"
    else
        fail "$id" "$src changed since $commit: $(autowp_exec_user "$c" "cd '$dir' && git diff --stat '$commit' -- '$src' | tail -3 | tr '\n' ' '")"
    fi
}

# k3 <container> <id>: informational list of files changed outside the allowlist.
k3() {
    local c=$1 id=$2 out
    out=$(autowp_exec_user "$c" 'find ~ /tmp -xdev -newer ~/.autowp-t0 -type f 2>/dev/null \
        | grep -vE "^'"$AUTOWP_HOME"'/('"$CAMPAIGN_PROJECT"'|toolchain|\.claude|\.claude\.json|\.cache|\.opam|\.elan|\.cargo|\.rustup|\.local/share/creusot|\.local/share/claude|\.local/state/claude|\.config|\.bash_history|\.gitconfig|remote\.git|\.autowp-)|^/tmp/" \
        | head -30' || true)
    info "$id" "outside the allowlist: ${out:-nothing}" 
    info "$id" "writes into ~/toolchain: $(autowp_exec_user "$c" 'find ~/toolchain -xdev -newer ~/.autowp-t0 -type f 2>/dev/null | head -10 | tr "\n" " "')"
}

# state_json <container> <state-file>: best-effort parse of time-loop.state
# (its format is free-form; see the campaigns under use-frama-c). Prints JSON:
# start, deadline (epochs), wakes (epochs), cycles, gate_t_pass, scope,
# verdict_change_cycles. Missing fields are null.
state_json() {
    local c=$1 f=$2
    autowp_exec_user "$c" "python3 - '$f'" <<'PY'
import json, re, sys
from datetime import datetime, timezone
try:
    text = open(sys.argv[1]).read()
except OSError:
    print(json.dumps({"error": "missing"})); sys.exit(0)
def ts(s):
    s = s.strip()
    if re.fullmatch(r"\d{9,11}", s):
        return int(s)
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%MZ"):
        try:
            return int(datetime.strptime(s, fmt).replace(tzinfo=timezone.utc).timestamp())
        except ValueError:
            pass
    return None
TS = r"(\d{4}-\d\d-\d\d[T ]\d\d:\d\d(?::\d\d)?Z?|\b\d{10}\b)"
def field(*names):
    for n in names:
        m = re.search(r"(?im)^\s*%s\s*[=:]\s*%s" % (n, TS), text)
        if m:
            return ts(m.group(1))
    return None
start = field("START_EPOCH", "START_UTC", "start", "campaign start")
deadline = field("DEADLINE_EPOCH", "DEADLINE_UTC", "deadline")
wakes, cycles, changes = [], set(), set()
for line in text.splitlines():
    if re.search(r"(?i)\b(wake|cycle)\b", line):
        for t in re.findall(TS, line):
            v = ts(t)
            if v:
                wakes.append(v)
                break
    m = re.search(r"(?i)\bcycle[ _#-]*(\d+)", line)
    if m:
        cycles.add(int(m.group(1)))
        if re.search(r"(?i)verdict[ -]*(change|delta)", line):
            changes.add(int(m.group(1)))
scope = re.search(r"(?im)^\s*scope\s*[=:]\s*(\S+)", text)
print(json.dumps({
    "start": start, "deadline": deadline, "wakes": sorted(set(wakes)),
    "cycles": sorted(cycles),
    "gate_t_pass": bool(re.search(r"(?i)gate[- ]?t\b.*\bpass", text)),
    "scope": scope.group(1) if scope else None,
    "verdict_change_cycles": sorted(changes),
}))
PY
}

# jq-free JSON field access on the host.
json_get() { python3 -c 'import json,sys; v=json.loads(sys.argv[1]).get(sys.argv[2]); print("" if v is None else (json.dumps(v) if isinstance(v,(list,dict,bool)) else v))' "$1" "$2"; }

# wait_loop_stopped <container> <state-file> <hard-limit-s>: returns when the
# transcript and the state file have both been idle for IDLE_S (default 1800 s,
# longer than the ~20-min watchdog wake-up of time-loop), or at the hard limit.
wait_loop_stopped() {
    local c=$1 f=$2 limit=$3 idle_s=${IDLE_S:-1800} t0 idle
    t0=$(date +%s)
    while :; do
        sleep 300
        if [ $(( $(date +%s) - t0 )) -ge "$limit" ]; then
            info wait "hard limit of $((limit / 3600)) h reached"
            return 1
        fi
        idle=$(autowp_exec_user "$c" "now=\$(date +%s); m=0
            for x in \$(ls -t ~/.claude/projects/*/*.jsonl 2>/dev/null | head -1) '$f'; do
                [ -e \"\$x\" ] && { s=\$(stat -c %Y \"\$x\"); [ \"\$s\" -gt \"\$m\" ] && m=\$s; }
            done; echo \$(( now - m ))")
        [ "$idle" -ge "$idle_s" ] && return 0
    done
}

# campaign_checks_c <container> <hours> <id-prefix> [rate-limited-s] [id-for-C3.7]
# C3.2-C3.9 of tests.md 5.3 (C3.1 is K4, checked when the harness starts;
# C3.10 is report_check_c).
campaign_checks_c() {
    local c=$1 hours=$2 p=$3 st S start deadline wakes ncyc longest last n missing=""
    local F D=$CAMPAIGN_DIR X=$CAMPAIGN_SRC base
    F=$(campaign_state_file)
    base=$(autowp_exec_user "$c" "cat ~/$CAMPAIGN_COMMIT_FILE")
    if [ "$CAMPAIGN_SRC_KIND" = tracked ]; then
        k1_tracked "$c" "$D" "$X" "$base" "${p}2"
    else
        k1 "$c" "$D/$X" "$base" "${p}2"
    fi
    if ! autowp_exec_user "$c" "test -s '$D/$X-analysis-rmf-report.md'"; then
        fail "${p}3" "$X-analysis-rmf-report.md missing or empty"
    elif [ "$CAMPAIGN_LINT" = 1 ] && ! autowp_exec_user "$c" "cd '$D' && bin/rmf-lint.sh $X-analysis-rmf-report.md >/dev/null 2>&1"; then
        fail "${p}3" "bin/rmf-lint.sh fails on $X-analysis-rmf-report.md"
    else
        pass "${p}3"
    fi
    S=$(state_json "$c" "$F")
    if [ "$(json_get "$S" error)" = missing ]; then
        fail "${p}4" "$F does not exist"
        fail "${p}5" "no state file"; fail "${p}6" "no state file"; fail "${5:-${p}7}" "no state file"
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
        elif [ "$n" -eq 1 ]; then fail "${p}5" "the state file records only one wake: the scheduled wake-up did not fire"
        else fail "${p}5" "no wake recorded in the state file"; fi
        # C3.6: every cycle has a commit in ~/remote.git
        ncyc=$(python3 -c 'import json,sys; print(" ".join(map(str, json.loads(sys.argv[1])["cycles"])))' "$S")
        local log
        log=$(autowp_exec_user "$c" 'git -C ~/remote.git log --all --format="%s %b" 2>/dev/null' || true)
        if grep -qiE 'cycle' <<<"$log"; then
            for n in $ncyc; do
                grep -qiE "cycle[ _#-]*0*$n([^0-9]|\$)" <<<"$log" || missing="$missing $n"
            done
            if [ -z "$missing" ]; then pass "${p}6"; else fail "${p}6" "no pushed commit for cycle(s)$missing"; fi
        else
            local ncommits
            ncommits=$(grep -c . <<<"$log" || true)
            if [ "$ncommits" -ge "$(wc -w <<<"$ncyc")" ] && [ "$ncommits" -gt 0 ]; then
                pass "${p}6"; info "${p}6" "commit messages do not name cycles; compared counts ($ncommits >= $(wc -w <<<"$ncyc"))"
            else
                fail "${p}6" "$ncommits commit(s) in ~/remote.git for $(wc -w <<<"$ncyc") cycle(s)"
            fi
        fi
        # C3.7: last wake <= deadline + longest cycle (+ rate-limited time)
        longest=$(python3 -c 'import sys; w=sorted(map(int, sys.argv[1].split())); print(max([b-a for a,b in zip(w,w[1:])] or [0]))' "${wakes:-0}")
        last=$(tr ' ' '\n' <<<"$wakes" | sort -n | tail -1)
        if [ -z "$deadline" ] || [ -z "$last" ]; then
            fail "${5:-${p}7}" "deadline or wakes not found in the state file"
        elif [ "$last" -le $(( deadline + longest + ${4:-0} )) ]; then
            pass "${5:-${p}7}"
        else
            fail "${5:-${p}7}" "last wake $(date -u -d "@$last" +%FT%TZ) is after deadline + longest cycle ($longest s)"
        fi
    fi
    secret_k2 "$c" "${p}8"
    k3 "$c" "${p}9"
}

# report_check_c <container> <id> <interim|final>: C3.10 / C4.5.
report_check_c() {
    local c=$1 id=$2 kind=$3 others D=$CAMPAIGN_DIR X=$CAMPAIGN_SRC inside
    if ! autowp_exec_user "$c" "test -s '$D/$X.md'"; then
        fail "$id" "$D/$X.md missing or empty"; return
    fi
    if ! autowp_exec_user "$c" "grep -qi '$kind' '$D/$X.md'"; then
        fail "$id" "$X.md does not say it is the $kind report"; return
    fi
    if [ "$CAMPAIGN_SRC_KIND" = tracked ]; then
        inside="git status --porcelain --untracked-files=all -- '$X'"
    else
        inside="git -C '$X' status --porcelain --untracked-files=all"
    fi
    others=$(autowp_exec_user "$c" "cd '$D'; find . -maxdepth 1 -name '*.md' -newer ~/.autowp-t0 \
            ! -name '$X.md' ! -name '$X-analysis-*' ! -name README.md; \
        $inside | grep -iE 'report|\.md\$'" || true)
    if [ -n "$others" ]; then fail "$id" "other report files: $(echo "$others" | tr '\n' ' ')"
    else pass "$id"; fi
}
