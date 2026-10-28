# CMSIS BASEPRI intrinsics undeclared under the Zephyr mps2_an385 board build

- **Trigger (unit / gap):** zk37 cycle-03 convergence on `mem_slab.c` / `mempool.c` /
  `stack.c` (any unit whose API wraps its body in `k_spin_lock`/`k_spin_unlock`). The
  `*_assigns_*` self-goals on the inlined `arch_irq_lock` / `arch_irq_unlock` / `k_spin_lock`
  contracts stay undischarged.
- **Observed behaviour:** WP reports the ARMv7-M CMSIS BASEPRI intrinsics
  (`__get_BASEPRI`, `__set_BASEPRI`, `__set_BASEPRI_MAX`) as **undeclared** — the log shows
  "Calling undeclared function …" and "Old style K&R / Neither code nor specification".
  Because the body of `arch_irq_lock`/`arch_irq_unlock` calls these intrinsics, WP cannot
  prove the `assigns \nothing` clause at the inlined definition (it sees an unmodelled call),
  so the `arch_irq_*_assigns_*` / `k_spin_lock_assigns_*` self-goals time out. The contract
  is sound and used correctly at every call site (the campaign reuses
  `shared_kernel_infra_contracts.patch` `assigns \nothing` on the non-SMP spinlock); only the
  definition-site proof of `assigns` fails.
- **Why it is a tooling/onboarding gap, not a spec defect:** the intrinsics are defined in
  `cmsis_gcc.h` (a third-party CMSIS header) as `__attribute__((always_inline))` static
  inlines with inline-asm bodies; under the board's preprocessing path they are not seen by
  the WP front-end as declared functions with bodies/specs. This is distinct from the
  inline-asm-`assigns` TOOLING class (where the asm clobber itself is the obstacle) — here the
  function is not even declared/parsed.
- **Desired behaviour:** either (a) WP/Frama-C parses the CMSIS `cmsis_gcc.h` static-inline
  intrinsics under the Zephyr build flags (a force-include or a shadow header in
  `zk37-acsl/fc-include/` providing `assigns \nothing` ACSL stubs for the BASEPRI/PRIMASK
  intrinsics, analogous to the existing `fc_sys_init_shim.h` / cbprintf shadow), or (b) the
  onboarding package ships such stubs so the spinlock `assigns` discharges at definition.
- **Minimal example:** any `zk37-acsl/verify.sh mem_slab.c -wp -wp-rte` run — grep the log for
  `__set_BASEPRI` and `arch_irq_lock_assigns`.
- **U clause served:** "specify thoroughly / honor the guidance uniformly" — the spinlock
  `assigns` is the campaign-wide reusable lever (`shared_kernel_infra_contracts.patch`);
  closing its definition-site proof would convert the per-unit `*_assigns_*` self-goals from
  residue to discharged, lifting the proved/total on every IPC/allocator/sync unit.
- ASSUMPTION: classified UNMODELLED-preprocessing (not spec-fixable in-unit) on the evidence
  that the underlying CMSIS intrinsics are reported undeclared under this build config;
  candidate fix is a CMSIS-intrinsic shadow/stub header in the onboarding overlay, owned by
  `frama-c-launch`.
