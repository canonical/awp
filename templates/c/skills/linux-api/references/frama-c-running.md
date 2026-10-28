# Running Frama-C/WP on the overlay, and how this plugs into the SL family

Consult this when invoking Frama-C on a model or harness, laying out the
`linux/linux-acsl/` overlay, or wiring the campaign into `frama-c-launch` /
`frama-c-monitoring` / `framac-sl`.

## The `linux/linux-acsl/` overlay

The deliverable is a **durable overlay**, scaffolded by `frama-c-launch` (its
`<target>-acsl/` convention) and mirroring the real header paths so a unit under
verification `#include`s the *modeled* header instead of the real one:

```text
linux/linux-acsl/
  include/                       # modeled headers, mirroring linux-7.1.1/include/
    linux/
      ghost_state.h              # the shared ghost kernel state (atomic_depth, refcount[], ...)
      slab.h        err.h        # §1 allocators / §8 ERR_PTR
      uaccess.h     string.h     # §3 user boundary / §2 mem-string
      spinlock.h    mutex.h      # §4 locks (ghost)
      kernel.h      overflow.h   # §10 might_sleep / §9 overflow-safe sizing
      list.h        refcount.h   # §7 containers / §6 refcounting
      ...
  harness/                       # Step-5 client harnesses (the loop-closers)
    sec03_user_boundary_good.c   sec03_user_boundary_bad.c
    sec10_sleep_in_atomic_*.c    ...
  notes/                         # per-API fidelity notes, version pin, cite anchors
  setup.sh  verify.sh            # frama-c-launch's run scripts
  sessions/                      # WP session caches
```

**Faithfulness baseline.** Pin the overlay to **`linux-7.1.1`** in `notes/` (the
version the contracts transcribe). `frama-c-launch` owns this pin; never transcribe
semantics from a different tree — a drift is a fidelity defect, caught by the §
fidelity oracle.

## Invocation

```bash
# parse + RTE + WP a model or a harness
frama-c -wp -wp-rte \
  -machdep gcc_x86_64 \
  -cpp-extra-args="-nostdinc \
      -I linux/linux-acsl/include \
      -I linux/linux-7.1.1/include \
      -I linux/linux-7.1.1/arch/x86/include \
      -D__KERNEL__ -DCONFIG_64BIT" \
  -wp-prover alt-ergo,z3 -wp-timeout 20 \
  -wp-session linux/linux-acsl/sessions \
  linux/linux-acsl/harness/sec03_user_boundary_good.c
```

- **`-machdep`** — the kernel analog of pycsl's "wrong CWD": it fixes `sizeof`,
  pointer width, signedness. Pick the target arch's machdep (`gcc_x86_64` for x86-64);
  a wrong machdep proves the wrong machine model. Pin it in `verify.sh`.
- **`-cpp-extra-args`** — the overlay `include/` must come **before** the real tree so
  the modeled headers win. `-nostdinc` keeps host libc out. The real
  `-I`/`-D`/feature-defines come from `frama-c-launch`'s onboarding package
  (`compile_commands.json` or a hand-built set) — do not invent them here; reuse what
  onboarding derived for the unit.
- **`-wp-rte`** — turns on overflow / div-by-zero / mem-access / shift goals; this is
  where the §9 overflow and §2/§3 OOB properties actually get checked.
- **provers/escalation** — Alt-Ergo primary, Z3 fallback (the repo's
  `framac-coq8`/`frama-c -wp-detect` toolchain). Irreducible inductive facts (§7
  reachability, §8 round-trip) escalate to a **cross-validated lemma**, not `Admitted`
  — the SMT→Coq/Rocq ladder and `Print Assumptions` audit are `frama-c-monitoring`'s
  job; never smuggle a behavioural axiom to land a goal.

## Non-vacuity run (Step-5 rule 4)

Run the **good** and **bad** harness for each stub:
```bash
frama-c -wp ... harness/secNN_*_good.c   # MUST fully discharge
frama-c -wp ... harness/secNN_*_bad.c    # MUST leave a goal UNPROVEN
```
A bad harness that discharges means the contract is too weak — tighten it. Record both
verdicts; a stub with no bad-harness has not been calibrated.

## How the campaign plugs into the existing SL family

`linux-api` is the **coverage campaign** (what to model, to what strength, the ledger);
the proving is done by the existing engine. The division of labor:

| Skill | Role for this campaign |
|---|---|
| **`frama-c`** | the ACSL reference — how to write any `requires`/`ensures`/`logic`/ghost correctly. |
| **`frama-c-launch`** | scaffolds `linux/linux-acsl/` (setup.sh/verify.sh/sessions), derives the per-unit `-cpp-extra-args`/`-machdep`, pins the `linux-7.1.1` baseline, proves a smoke unit. Run it ONCE to onboard the kernel target. |
| **`frama-c-monitoring`** | schedules units leaf-first (propagating each proven callee `ensures` as the caller's stub `requires`), instantiates a `framac-sl` sub-loop per unit, and runs its FOUR base-SL gates per unit: faithfulness (strip-ACSL == original), no-smuggled-axiom, **non-vacuity** (our Step-5 rule 4), completeness-vs-gold. This is the campaign engine. |
| **`framac-sl`** | the per-unit loop (coordinator / spec-author / annotator / verifier) that `frama-c-monitoring` drives. The model agent / harness agent of `../SKILL.md` map onto its annotator / verifier with the *added* barrier that the harness agent never sees the ACSL. |
| **`frama-c-internals`** | where a genuine WP memory-model wall (a Step-6 gap — cast/region unsoundness, `assigns` inference) gets fixed. |

**Practically:** to run the whole campaign, hand `frama-c-monitoring` the mission
"verify the `linux/linux-acsl/` overlay against `linux-7.1.1`", feed it this skill's
inventory + MVP ordering + buckets, and let it drive `framac-sl` per unit. To model one
section by hand, follow `../SKILL.md` Steps 1–6 and invoke `frama-c -wp` as above.
