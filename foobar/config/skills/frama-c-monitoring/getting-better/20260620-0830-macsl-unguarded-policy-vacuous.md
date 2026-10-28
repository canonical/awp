# macsl/HAPPY: a zero-expansion or unguarded policy gives a VACUOUS green (mandatory negative control)

- **Trigger:** wolfSSL Tier-3 attempt (the verification depth ladder §4b, macsl/HAPPY tier),
  2026-06-20.
- **The durable lesson (tool-agnostic):** a `[macsl] Will process N` + `[wp] Proved goals N/N` line
  **proves nothing on its own**. Two traps produce a green that checked nothing:
  1. **Zero expansion.** A policy that matches no program point (wrong `\targets`/`\context`) expands
     to **zero** assertions; WP then "passes" the bookkeeping goals (`Terminating`/`Unreachable`) only.
     macsl **warns** on zero-expansion — heed it; confirm with `-macsl-list-targets` (non-zero count)
     and `-macsl-print` (a real `/*@ assert <name>: meta: … */` at the expected sites).
  2. **No teeth.** Goals are scheduled but a deliberately-violating site still proves — the policy is
     too weak or mis-scoped. **Mandatory negative control:** a program point that violates the policy
     MUST turn its assertion RED before any green is trusted. (Reds often land as `[Timeout]` — fine
     and machine-independent for a genuinely-false goal.)
- **Admissibility:** only a policy whose negative control goes red is admissible — the Gate-C
  non-vacuity rule for system-property policies. The recipe (syntax, `\context` families, exemptions,
  the **in-place** command line — `-no-autoload-plugins -load-module <macsl.cmxs> -macsl -wp`, no
  `-then-last`) is in `../references/macsl-recipe.md`.
- **What still gates a real Tier-3 result on wolfSSL:** not the tool — the **BLOCKED target code**
  (logic-class risks in cert-validation / TLS-state-machine code, out of WP reach) must be lifted into
  scope first. macsl itself is runnable on this switch and covers all six STRIDE letters.
- **Honesty (the headline):** the non-vacuity / negative-control gate **caught a vacuous green and the
  round refused to report a Tier-3 PROVED** — the discipline working at a new-tooling frontier
  (coherent-and-wrong prevented, not produced).
