# Monitor discipline: for an imported extern contract, ensures-weakening is sound but requires-weakening is NOT

**Cycle-224** (`context_equal`, imports the witnessed `ebitmap_equal`). The verifier described its
imported extern as bearing "a faithful SUBSET" of the witnessed callee contract and "claiming strictly
less." That framing is only half right, and the half it gets wrong is the soundness-critical half.

**The asymmetry (the catch):** a callee contract is `(requires R, ensures E, assigns A)`.
- **Weakening ENSURES** (claiming a weaker post, e.g. dropping one `ensures`) is SOUND — the caller
  simply assumes less; the real function still satisfies it.
- **Weakening REQUIRES** (claiming a weaker pre) is UNSOUND in general — it asserts the callee is
  safe/correct in MORE states than were proven. The witnessed `ebitmap_equal` was proven under
  `\valid_read(e) && valid_enodes(e->node)`; the import required only `\valid_read(e)`. In states
  satisfying `\valid_read` but not `valid_enodes` (invalid node chain) the real function has UB, so it
  does NOT provably satisfy the weaker-precondition contract — using it smuggles an unproven robustness
  claim. "Faithful subset" conflates the two directions: a subset of *ensures* is sound; a weaker
  *requires* is not a subset in the sound direction.

**Why it was still recordable as WITNESSED here (the discriminator):** two independent facts rescued it,
and BOTH must be checked before accepting:
1. **The security semantics are robust to the callee result.** `mls_context_equal`'s `&&`-chain means
   result-true forces every sens/user/role/type conjunct true regardless of what `ebitmap_equal`
   returns. No proven ensures rests on the callee's set-semantics — the extern is load-bearing ONLY for
   `assigns \nothing` (frame) and `result ∈ {0,1}`, both byte-faithful to the witnessed callee. Test:
   would the ensures still prove if the callee were replaced by `return nondet_bool()`? Here yes.
2. **The weaker precondition is a faithful over-approximation MODULO a real structural invariant** — the
   same shape as the long-accepted `strcmp` extern (requires local `\valid_read(str)`; the deeper
   valid-nul-terminated-string validity is the deployment invariant). A valid SELinux context carries
   valid `cat` ebitmaps (`valid_enodes`), so the composition is sound in reality; the unit just doesn't
   thread that invariant through its envelope.

**How to apply:** when a unit imports a witnessed sibling's contract as an extern, byte-compare BOTH
directions against the sibling's *proven* contract — not just the ensures. If the extern's `requires` is
WEAKER than proven, do not accept "faithful subset": (a) confirm no proven ensures depends on the callee
result (robustness test above), AND (b) confirm the weakened precondition is a faithful
over-approximation modulo a named real structural invariant (like `strcmp`/valid-string). If both hold,
record WITNESSED but STATE the correction explicitly in the row. If either fails, it is a smuggled
robustness precondition — REJECT / require the extern `requires` be strengthened to the proven precond
and the caller envelope to establish it. See [[classA-storebloat-proving-twin]] for the sibling
class-A-vs-C monitor discipline.
