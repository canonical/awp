#!/usr/bin/env bash
# Level 3, Rust (tests.md 6.3): the cargo-creusot workspace pitfall,
# cases A-H of auto-wp.md 4.3.6, in a copy of autowp-rust-base/ready.
# Needs no Claude token. Re-run it after a Creusot upgrade.
#
#   tests/rust/workspace-test.sh       KEEP=1 keeps the container
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib/lxc.sh
. "$HERE/../lib/lxc.sh"

# Expected results (auto-wp.md 4.3.6):
#   case|why3find.json written to|parent .gitignore|cargo creusot in p/
EXPECTED="A|overlay|none|proved
B|parent|created|fail-parse
C|parent|created|fail-notfound
D|parent|created|proved
E|parent|created|fail-notfound
F|parent|created|proved
G|parent|created|fail-notfound
H|parent|unchanged|proved"

autowp_require_lxc
autowp_install_trap
autowp_ensure_pool
autowp_ensure_network

C=autowp-rust-l3ws-$(autowp_timestamp)
autowp_copy_snapshot autowp-rust-base ready "$C"
autowp_wait_ready "$C"
autowp_egress_check "$C"

# The guest part: one line per case on stdout, logs kept in ~/ws-test/<case>/.
guest=$(cat <<'GUEST'
set -u
. ~/.cargo/env 2>/dev/null || true
SB=~/ws-test
DATA=${CREUSOT_DATA_HOME:-$HOME/.local/share/creusot}
rm -rf "$SB"; mkdir -p "$SB"
PKG='[package]\nname = "q"\nversion = "0.1.0"\nedition = "2021"\n'
WS='[workspace]\nmembers = []\n'
sha() { [ -f "$1" ] && sha256sum "$1" | cut -d' ' -f1 || echo none; }
run() {  # id parent(NONE|EMPTY|WS|PKG) pre-existing-gitignore(0/1) add-workspace(0/1) copy(0/1)
  local id=$1 parent=$2 gi=$3 ws=$4 cp=$5 d="$SB/$1" before after loc gstate verdict
  mkdir -p "$d"
  case "$parent" in
    EMPTY) : > "$d/Cargo.toml" ;;
    WS)    printf '%b' "$WS" > "$d/Cargo.toml" ;;
    PKG)   printf '%b' "$PKG" > "$d/Cargo.toml"; mkdir -p "$d/src"; : > "$d/src/lib.rs" ;;
  esac
  [ "$gi" = 1 ] && printf 'target/\n# pre-existing\n' > "$d/.gitignore"
  before=$(sha "$d/.gitignore")
  (cd "$d" && cargo creusot new p) > "$d/new.log" 2>&1 || echo "new failed" >> "$d/new.log"
  if [ -f "$d/why3find.json" ]; then loc=parent
  elif [ -f "$d/p/why3find.json" ]; then loc=overlay
  else loc=nowhere; fi
  after=$(sha "$d/.gitignore")
  if [ "$parent" = NONE ] && [ "$before" = none ] && [ "$after" = none ]; then gstate=none
  elif [ "$before" = none ] && [ "$after" != none ]; then gstate=created
  elif [ "$before" = none ]; then gstate=none
  elif [ "$before" = "$after" ]; then gstate=unchanged
  else gstate=changed; fi
  [ "$ws" = 1 ] && printf '\n[workspace]\n' >> "$d/p/Cargo.toml"
  [ "$cp" = 1 ] && [ ! -f "$d/p/why3find.json" ] && cp "$DATA/why3find.json" "$d/p/why3find.json"
  if (cd "$d/p" && cargo creusot) > "$d/prove.log" 2>&1; then verdict=proved
  elif grep -qiE 'failed to parse manifest' "$d/prove.log"; then verdict=fail-parse
  elif grep -qiE 'why3find\.json.*not found|not found.*why3find\.json' "$d/prove.log"; then verdict=fail-notfound
  else verdict="fail-other($(grep -iE 'error' "$d/prove.log" | head -1 | cut -c1-100 | tr '|' '/'))"; fi
  echo "$id|$loc|$gstate|$verdict"
}
run A NONE  0 0 0
run B EMPTY 0 0 0
run C EMPTY 0 1 0
run D EMPTY 0 1 1
run E WS    0 1 0
run F WS    0 1 1
run G PKG   0 0 0
run H PKG   1 1 1
GUEST
)

info versions "$(autowp_exec_user "$C" '. ~/.cargo/env; cargo creusot version 2>&1 | head -3' | tr '\n' ' ')"
actual=$(autowp_exec_user "$C" "$guest")
printf '%s\n' "$actual" | sed 's/^/    | /'
mkdir -p "$AUTOWP_OUT"
lxc exec "$C" -- tar -C /home/ubuntu -cf - ws-test \
    | tar -C "$AUTOWP_OUT" -xf - --transform "s,^ws-test,rust-ws-$(autowp_timestamp)," 2>/dev/null || true

# --- R3.1 -----------------------------------------------------------------
r31=0
while IFS='|' read -r id loc g verdict; do
    line=$(grep "^$id|" <<<"$actual" || true)
    IFS='|' read -r _ aloc _ averdict <<<"$line"
    if [ "$aloc|$averdict" != "$loc|$verdict" ]; then
        fail "R3.1-$id" "expected why3find.json in $loc and '$verdict', got '${aloc:-?}' and '${averdict:-?}'"
        r31=1
    fi
done <<<"$EXPECTED"
[ "$r31" = 0 ] && pass R3.1

# --- R3.2 -----------------------------------------------------------------
if grep -q '|changed|' <<<"$actual"; then
    fail R3.2 "an existing parent .gitignore was changed: $(grep '|changed|' <<<"$actual" | cut -d'|' -f1 | tr '\n' ' ')"
elif ! grep -q '^H|[^|]*|unchanged|' <<<"$actual"; then
    fail R3.2 "case H did not report its pre-existing .gitignore as unchanged"
else
    pass R3.2
fi
# .gitignore creation next to the parent manifest (informational detail of the table)
while IFS='|' read -r id _ g _; do
    a=$(grep "^$id|" <<<"$actual" | cut -d'|' -f3)
    [ "$a" = "$g" ] || info "gitignore-$id" "expected '$g', got '$a'"
done <<<"$EXPECTED"

# --- R3.3 -----------------------------------------------------------------
if [ "$actual" = "$EXPECTED" ]; then
    pass R3.3
else
    fail R3.3 "results differ from auto-wp.md 4.3.6; update 4.3.5/4.3.6 and the bug report. New table:"
    echo "    case|why3find.json written to|parent .gitignore|cargo creusot in p/"
    printf '%s\n' "$actual" | sed 's/^/    /'
fi

autowp_summary
