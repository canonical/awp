# A negative capability claim about Frama-C is an EVIDENCE claim — ground it before asserting

## The pattern (two instances, same root cause)
Twice in this project a confident **negative capability claim** about the tool was asserted from
memory/assumption and turned out **false**:

1. **"The system-property meta-property tool is a silent no-op on Frama-C 32.1."** Actually it works;
   the symptom was an invocation-order mistake (file after `-then-last`; `-print` without `-then-last`).
   Retracted by running the plugin's own test (milestone M0). The canonical tool is now **macsl**, which
   removes the footgun by instrumenting in place (`-macsl -wp`, no `-then-last`); see
   `../references/macsl-recipe.md`.
2. **"main.c's socket/string layer (`strtok`/`snprintf`/sockets) is outside WP's reach."** Actually
   Frama-C's ACSL libc specifies all of them — `strcmp`/`strncpy`/`strchr`/`strtok`/`strlen`
   (`string.h`, with logic `strcmp`/`strlen` and a ghost `__fc_strtok_ptr`), `read`/`write`/`close`
   (`unistd.h`), `socket`/`bind`/`listen`/`accept` (`sys/socket.h`) — and the variadic
   `snprintf`/`sscanf` go through the **Variadic** plugin. A clean proof is effort (loop invariants +
   coarse `assigns`/`\from` specs), not impossibility.

Both are *coherent-and-wrong*: a fluent, plausible limitation stated without checking the installed
system — exactly what the squeeze-loop discipline exists to catch, but applied to a **negative** claim
rather than a green.

## The rule (now in `frama-c` SKILL "Grounding rule" and `frama-c-monitoring` SKILL §scope-map)
A claim that the tool **cannot** do something — "WP can't prove X", "out of WP's reach",
"unspecified", "no-op", "BLOCKED", "out of scope" — is a claim **about the installed tool** and
carries the same evidentiary burden as a positive result. Before asserting it:
- `grep` the symbol in **`$(frama-c -print-share-path)/libc`** (the ACSL stdlib is included by
  default; `-no-framac-stdlib` disables it);
- check `-wp-detect`, the plugin's own `tests/`, or run a **one-file probe**;
- if you have not checked, say **"I have not verified this"** — do not assert the limitation.

## Why it matters
A false *negative* claim is more corrosive than a false green: it silently shrinks the verified
surface ("we can't, so we won't"), routes real, provable risks into the residual-risk register
unexamined, and is never caught by the non-vacuity gate (which only audits greens). Treat
out-of-scope / BLOCKED determinations as findings that must be **grounded and cited**, never assumed.
