# Getting a real compile context — build tools, and five ways to a compile database

**Scope / barrier:** everything between "here is a C codebase" and "every
in-scope TU has its *real* `-D/-I/-include/--target` context". This file is
the **method**; `learned-prober.md` holds the per-target recipes that came out
of using it. Phase 0 of `SKILL.md` runs this.

It exists because of a specific recurring failure: **one blocked path reported
as a blocked target.** The build oracle (§1.0) is mandatory precisely so that
"the flags cannot be derived here" has to be *proved*, and it is not proved by
the first tool failing.

---

## 1. The rule

> A missing tool, a failing `bear`, a build that stops half way, a target
> whose native toolchain does not exist on this OS — **none of these is a
> class-A ceiling.** Each is a step with at least one documented alternative
> below. Label the target blocked only after the alternatives are tried, and
> record *which* were tried.

`no-ceiling.md` applies in full here: a fluent, plausible limitation asserted
without the probe that would refute it is the thing this project has relabelled
five times. The probe for "no compile database is possible" costs one `ls` over
the build tree (§4.2).

**Before anything else:** if this target has been onboarded before, its
`<target>-analysis-*/onboarding.md` is the answer. Read it first. It records
the profile, the substitutions, the counts and the remaining blockers, and it
is cheaper than every section below.

## 2. Install what is missing — and in the right place

A build that needs `csh`, `mig`, `bison`, a newer `clang`, or a generator you
do not have is a **provisioning** step, not a blocker. Where to install
depends on where you are running, and the difference matters because two of
the three are wiped by routine operations.

### 2.1 In a Workshop (the generated project's default)

`sudo -n` works and `apt-get` is available, so an ad-hoc install succeeds:

```sh
sudo apt-get update && sudo apt-get install -y csh bison flex
```

**But it is ephemeral.** `workshop refresh` and `workshop restore` rebuild the
container outside `/project` and the SDK mounts, so anything installed by hand
is gone — along with the harness login. The durable path is the project's own
SDK hook:

```sh
#  .workshop/autowp-packages/hooks/setup-base   (runs as root at launch/refresh)
apt-get install byobu tmux curl \
    autoconf automake autopoint gettext bison flex libtool \
    csh                                    # <- add what the target's build needs
```

then, from the project directory on the host, `workshop refresh`.

Rules that follow from how Workshop works:
- **Edit the hook for anything the build needs**, then refresh. Treat an
  ad-hoc `sudo apt-get` as a probe ("does this unblock the build?"), and move
  it into the hook once it does.
- **Never `workshop refresh` while a campaign is running** — it discards the
  harness login and the in-container git remote.
- `/usr/local/bin` is not writable by the `workshop` user; use `sudo install`,
  or a user-local prefix under `$HOME`.
- The SDK tree (`/opt/frama-c-sdk`) is **read-only**. Build nothing into it.
  A tool you compile yourself belongs under the project
  (`build_<target>-analysis/tools/bin/`), which is also how it survives a
  refresh — `/project` is a mount, not part of the image.

### 2.2 In an LXD container (`bin/launch_lxc.sh`, way C)

Same as §2.1 for apt, but there is no SDK hook: the container is provisioned
by the script. Add packages to `bin/launch_lxc.sh` so a re-launch reproduces
them, and keep self-built tools under the mounted project for the same reason.

### 2.3 On the host, with no container

Install with the system package manager if you own the machine; otherwise keep
everything user-local and reversible:

- apt/dnf/brew for system packages, **only with the user's agreement** — this
  is their machine, not a disposable container.
- opam for the OCaml side (`opam switch remove` reverses it, no `sudo`).
- self-built tools into `$HOME/.local/bin` or the project, never `/usr/local`.

Record every host-level install in the onboarding package, because the next
run cannot see what you did and the user has to be able to undo it.

### 2.4 MCP servers are already registered

The SDKs ship MCP servers (`framac`, `rocq`, `creusot`, `lean-lsp`) and the
project's `setup-project` hook registers each mounted one with the harness at
launch, so `framac`/`rocq` are available without a manual `mcp add`. Check with
`opencode mcp list` (or `claude mcp list`). Two things to know:

- The names are the ones the **specs and the consuming skills** use. A server
  registered under another name is invisible to the skill that would use it —
  `frama-c-monitoring` §4b probes "the registered `framac` MCP" — and neither
  CLI has an `mcp remove`, so a wrong name has to be cleared by editing
  `~/.config/opencode/opencode.json` by hand.
- An MCP read is **a faster path to the same data, never a source of truth**
  (`frama-c-monitoring` §4b). Banking still comes from the batch run's report.

`AUTOWP_MCP_REGISTER=0` before a launch skips registration.

### 2.5 What to record either way

The onboarding package must name every tool the build needed and where it came
from. A build that only works because of an undocumented install is not
reproducible, and the faithfulness argument depends on reproducibility.

## 3. Five ways to a compile database, in order of preference

The goal is never "a `compile_commands.json`". It is **the real per-TU flag
set**. The file is one representation of it.

### 3.1 The buildsystem emits it

```sh
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON …     # CMake, Ninja
west build                                      # Zephyr
meson setup builddir                            # Meson (writes it natively)
```

Cheapest and exact. Try first.

### 3.2 `bear` (or `intercept-build`) around the build

```sh
bear -- make -k -j"$(nproc)"
```

Works for plain make. **Expect it to fail on a kernel-style build**: its
`LD_PRELOAD`/ptrace intercept does not survive every re-exec, recursive make,
or tool wrapper. A `bear` run that produces no database for the phase you care
about is **not** a verdict on the target — go to §3.3.

### 3.3 The compiler's own per-TU records — `clang -MJ`

Any clang invocation can be asked to drop a JSON compile record next to its
object:

```sh
# as a build-wide injection
make CFLAGS="-MJ \$@.json" …
# or, if the build already does it (xnu does), just harvest them
find "$BUILD" -name '*.o.json' | wc -l
```

Merge them into one database, and **keep a per-entry flag for whether the
compile actually succeeded** (`"built": true|false`, §5). This is the path
that works when the intercept-based tools do not, because it comes from the
compiler itself rather than from watching the process tree.

GCC has no `-MJ`; use §3.4 there.

### 3.4 Parse a dry run

```sh
make -Bnk | tee build-dryrun.txt     # every command the build *would* run
```

Then turn each compile line into an entry. Less reliable than §3.3 — recursive
make loses directories, and `$(shell …)` side effects do not happen — so
validate a sample against the parse oracle before trusting the whole set.
`compiledb` automates this shape.

### 3.5 Reconstruct from the buildsystem's own variables

Last resort, and the one to be most honest about: read `MakeInc.def`, the
generated `conf/` options, the `-include` list, and assemble the flag set. The
result is **only** acceptable if the parse oracle passes on a sample *and* the
derivation is recorded file-by-file. Hand-synthesising flags without that is
exactly what §1.0's build oracle forbids.

## 4. When the target's native toolchain is not on this OS

A foreign target — an Apple kernel on Linux, a vendor BSP, a cross-compiled
firmware — is a **tool substitution problem**, not an impossibility. The method:

### 4.1 Substitute the tools, never the inputs

Replace each unavailable *tool* with something that produces the same effect on
preprocessing, and change **no header, struct, enum, macro or flag** in a
source unit. Keep a table of what was replaced and what each substitution
changes — that table *is* the faithfulness argument:

| unavailable | substitute | effect on TU preprocessing |
|---|---|---|
| vendor compiler driver | upstream clang with the same `--target=` triple | none: the target triple sets `__APPLE__`/`__MACH__`/LP64 etc. identically |
| SDK locator (`xcrun`, `*-config`) | a shim that answers the paths | none; it only resolves tool paths |
| an IDL/stub generator (`mig`, `rpcgen`, `iig`) | the vendor's own OSS source, built for this host | generated from the in-tree `.defs` by the real generator |
| signing, install wrappers | `/bin/true`, a `cp`+`chmod` wrapper | none |
| host-info probes (`sysctl`, `sw_vers`) | make variables | none (job counts, version strings) |
| a host-tool compiler | a `hostcc` wrapper with an aggregated header | host tools only; never on a kernel include path |

Two rules make this sound:
- **A substitution that changes a predefined macro, a type width, or a feature
  test is not a substitution** — it is a modified target. `-Wno-error` is fine
  (diagnostics only); hand-defining `__has_feature` to steer a header down a
  different branch is not.
- The pristine source tree stays read-only. Build in a copy, and keep the
  copy's build-system edits in a single reviewable diff.

### 4.2 A partial build is a usable build

The link stage almost never matters for onboarding: it needs the target's
linker and signing tools, and Frama-C never links. **Stop caring at the point
where every in-scope TU has been compiled, or at least preprocessed.**

So the probe for "can this target be onboarded here" is not "does it build" —
it is:

```sh
find "$BUILD" -name '*.o.json' | wc -l      # how many real compile records exist
find "$BUILD" -name '*.o'      | wc -l      # how many compiles actually succeeded
ls "$BUILD"/*/EXPORT_HDRS 2>/dev/null       # were generated headers produced
```

A tree with records and generated headers is onboardable even if `make`
exited non-zero.

## 5. Three oracles, not one — `built: false` is not `unusable`

Conflating these is how a large parseable surface gets reported as a wall:

| oracle | question | failure means |
|---|---|---|
| **context-real** | do this TU's flags come from the real build? | the context is synthesised — §1.0 violation, fix it |
| **compile-success** | did the host toolchain compile this TU? | a weaker faithfulness signal for *this* unit; record it |
| **parse-success** | can Frama-C parse the preprocessed TU? | a frontend gap — patch it (§6) or route it |

A unit whose record says `"built": false` — the host compiler choked on a
vendor-only builtin, say — **still has a real preprocessing context**. It can
be preprocessed with its own real flags and parsed. Give those units their own
sweep rather than dropping them.

Evidence that this is worth doing, from the xnu campaign: of 539 `built:false`
records, **329 parsed** once the frontend was patched. Dropping them would have
discarded about half the eventual surface.

## 6. The frontend is the usual real blocker — and it is patchable

Once the context is real, what remains is whether Frama-C's C frontend accepts
the dialect. That is where a genuine class-A lives, and also where the
project's leverage is: `frama-c-patches/` exists for exactly this, and
§0 item 2 makes the patched binary mandatory.

Measure it with the parse oracle before and after, and keep both numbers. The
xnu campaign's own figures:

| | PARSE-OK | PARSE-FAIL |
|---|---|---|
| stock Frama-C 32.1, built units | 30 | 357 |
| patched (`0001`–`0021`), built units | **316** | 75 |
| patched, the `built:false` set | **329** | 690 |

A 30-unit surface and a 316-unit surface support completely different campaign
plans. **Do not scope Gate A against an unpatched sweep.**

Dialect features worth expecting, each a patch rather than a wall: C23 /
clang fixed-underlying-type enums (`enum : uint8_t`), clang Blocks
(`void (^)(void)`), `_Atomic` layout, GNU `auto_type`, `__attribute__`
overloadable, `__int128`, VLA address-of, vendor type builtins.

## 7. The failure this file is here to prevent

An agent onboarding xnu read the onboarding tooling, found that
`bin/framac-onboard.sh` wants a `compile_commands.json`, found that `bear` could
not produce one for the kernel phase, and recorded:

> `compile_commands.json` (infeasible for XNU on Linux → exit 3, the known
> class-A wall)

Every clause of that was checkable and wrong. The same codebase had already
been built on Linux in the previous campaign: 929 compile records, 390
objects, generated headers for all nine subsystems, a documented
substitution table, and 813 verdicts produced from it. `bear` had indeed
failed — and §3.3 was the answer, already in use, already written down in the
target's own `onboarding.md`.

The cost of the misdiagnosis was a cycle aimed at a wall that was not there.
The cost of the check would have been one `ls`.
