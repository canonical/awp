# What verifies a kernel stub? — the canonical definition

This is the standalone, checkable definition the campaign measures a Step-5 artifact
against. It is the kernel/ACSL analog of `pycsl-stdlib-coverage`'s
`what-is-a-formal-test.md`. The workflow that produces these artifacts is Step 5 of
`../SKILL.md`; this file is what one is measured by.

A **client harness** is a small C driver in `linux/linux-acsl/harness/` that proves an
API's promise holds **for all** inputs by exercising the API's **observable
CONSEQUENCE through its public header** — and that a *bad* caller is **caught**. It is
the loop-closer: the mechanism by which a section's `Property` (the source of truth) is
propagated onto its ACSL contracts and *proved*.

## The five-rule checklist

An artifact accepts a kernel stub **only if all five hold**. Miss one and it is
something else (see "What it is NOT").

1. **FOR-ALL (universal quantification).** Every client input is symbolic, constrained
   by `requires`; never a concrete literal. WP discharges the postcondition over the
   whole precondition domain at once. *A concrete-valued driver is a unit test in ACSL
   syntax — it proves nothing new.*

2. **CONSEQUENCE (observe the effect, not the call).** The harness is a scenario:
   **set up a state → OPERATE via the API → assert a downstream SAFETY property.** The
   assertion is on the observed consequence — *not* a re-statement of the stub's own
   `ensures`. Re-asserting an op's own postcondition through a bare call
   (`r = rmdir(d); //@ assert r==0 || r==-1;`) is **VACUOUS** — true by construction,
   proving nothing about what the op did.
   - Mutating/resource op → round-trip: alloc → use → free with `refcount`/balance back
     to baseline; `copy_from_user` → checked → safe use of the kbuf.
   - Read-only/query op → observe against a KNOWN state you built.

3. **CALLS THE API (never inline the model).** `#include` the **public** header from
   `linux/linux-acsl/include/` and call the public function; observe *through* it.
   Never touch the model internals — the ghost variables directly, a private `__`
   helper, raw region bytes — and never inline the operation's logic. THE TELL of a
   simulated harness: *if writing it required reading the ACSL contract body or the
   ghost-state declaration, you are simulating, not testing.*

4. **NON-VACUITY (the mutation probe).** The seeded **bad** caller (Step 1 — the
   violation the `Property` must catch) must make WP **FAIL**. A contract a bad caller
   *passes* is too weak and certifies a fiction; tighten it until the bad caller is
   rejected and the good caller still proves. This is `frama-c-monitoring`'s
   non-vacuity gate, applied per stub. A green good-harness with a green bad-harness is
   the worst outcome — it looks verified and proves nothing.

5. **FIDELITY (agrees with `linux-7.1.1/`).** The contract matches the real kernel body
   on every input the harness exercises — the `// cite:` anchor to the header/source
   line is present and correct. A harness that proves a *property the real API does not
   have* (e.g. assuming `__copy_from_user` zero-pads — it does not; only
   `copy_from_user` does) is faithful-to-a-fiction. The model agent reads the body; the
   harness agent reads only the English — fidelity is gated by their agreement.

Two postcondition **strengths** (state which you proved): **totality/safety** ("the API
sequence never faults / never violates a precondition on any input") vs **functional
content** ("the API produces/guarantees the right value/relation on any input"). Don't
conflate them — "the lock discipline never faults" is not "the code is race-free", and
"the alloc never returns an unfresh pointer" is not "the buffer holds the right bytes".

## The canonical good shape (§3 trust boundary)

```c
#include <linux/uaccess.h>          /* the PUBLIC header — rule 3 */
extern char kbuf[4096];
/*@ requires 0 < len <= 4096;       // len is SYMBOLIC — rule 1
  @ requires \valid(((char*)ubuf)+(0..len-1));
  @ requires \separated(kbuf+(0..len-1), ((char*)ubuf)+(0..len-1));
  @ */
int read_handler(const void *ubuf, unsigned long len) {
    if (copy_from_user(kbuf, ubuf, len))   // OPERATE via the API
        return -14; /* -EFAULT */
    //@ assert \forall integer i; 0<=i<len ==> \valid(&kbuf[i]);  // CONSEQUENCE — rule 2
    return kbuf[0];                          // safe use of tainted data, proven for ALL len
}
```
The **bad** caller (rule 4, must FAIL): drop the `if (copy_from_user(...))` check and
read `kbuf[len-1]`, or use the *return value* as the next length — WP must reject it.

## What it is NOT

- **A return-code echo.** `//@ assert r == 0 || r == -1;` after a bare call. Vacuous
  (rule 2); at best a totality check, never functional verification.
- **A concrete unit test.** `read_handler(buf, 16)` with a literal — fails rule 1.
- **A simulation.** Writing/clearing the ghost `refcount[]` by hand and re-asserting it,
  or inlining the `container_of` arithmetic — fails rule 3; proves a tautology about the
  author's re-implementation.
- **A verified spec-subject with no driver** (the subtle one). An ACSL-annotated stub
  whose *own* contract is well-formed and whose (if any) body satisfies it, but with **no
  harness that calls it and observes a downstream consequence** — fails rules 2 & 3. It
  is a contract proof of the stub, not an acceptance of it. Do not count a section done
  on stub contracts alone.
- **A vacuous green** (rule 4 missed). The good harness proves AND the bad harness also
  proves — the contract is too weak. Looks verified; verifies nothing.
- **Faithful-to-a-fiction** (rule 5 missed). Green against a contract that the real
  `linux-7.1.1/` body contradicts.

## Why the author separation matters (the convergence principle)

The **harness agent** and the **model agent** must be different agents. The harness
agent is given only the public header signature + the `Property`/kernel-doc English —
**never the ACSL contract body or the ghost-state internals** — so it *physically
cannot* simulate (rule 3) and writes its consequence assertion from the English, not
from the (possibly wrong) contract. WP then discharges it via the contract or not. See
`../SKILL.md` "The agent loop" and `pycsl-stdlib-coverage`'s identical model/test-agent
split.

## Gate
A harness counts only when it is **green AND non-vacuous** (good harness discharges,
bad harness fails) **AND fidelity-anchored** (the `// cite:` matches `linux-7.1.1/`).
Run `frama-c -wp -wp-rte` on the good harness, confirm the bad harness does **not**
discharge, and confirm no `Admitted`/lemma-as-axiom/`\trusted` was used to land either.
