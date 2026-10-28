# WP `-wp-model +cast`: malloc-frame relation dropped across a call through a cast pointer

**Trigger** — `mbedtls_ssl_ticket_parse` (mbedtls 4.1.0, `library/ssl_ticket.c`) and
`mbedtls_net_recv` (`library/net_sockets.c`) — both use mbedtls's BIO/callback convention
(`void *ctx` cast to the concrete struct). mbedtls run, report §9/§10. Confirmed against `L`:
ssl_ticket reaches **37/55**, net_recv **16/22**, with the residuals stable across timeouts.

**Observed** — under `-wp-model +cast` (which is *required* for the `void*`→struct casts, since
the default Typed model rejects them outright), a call `f(…)` whose effect/footprint is over a
**cast pointer** `*((T*)ptr)` emits a VC in which the post-call allocation/malloc map appears
**only in the conclusion, with no hypothesis linking it to the pre-call map**. The goal is then
*false as generated* and unprovable by SMT or Coq without an unsound assumption. Signature:
- ~13–18 goals tagged `assigns_*_part*` / `call_*_requires` / `ensures`, each marked
  `(Stronger)`; Qed simplifies (78–377 ms) but the residual obligation over the cast-pointer
  footprint cannot close.
- **Stable proved-count at 25 s and 120 s** → structural, not slow-SMT.
- `-wp-model Caveat` *does* prove these (54/54) — **but vacuously here**: a mutation probe
  (weakening the `if (len < TICKET_MIN_LEN)` guard to `if (len < 2)`) still proves under Caveat,
  so Caveat is unsound for this code; `+cast` is the honest model and was kept.
- A minimal `void*`-cast repro proves at small scale, so the defect is scale/context-triggered
  (it appears once the surrounding function/type environment is large).

This is a **WP defect**, not a spec gap (the assigns footprints are correct; the calls' callee
preconditions are met) and not closable by Coq (the goal is unsatisfiable as emitted).

**Desired** — `+cast` should carry the pre→post allocation-map relation across a call through a
cast pointer (emit the framing hypothesis that the malloc map is unchanged except at the
declared `assigns` locations), so `assigns` / callee-`requires` goals on `void*`-callback code
are dischargeable. Or document the limitation with a *sound* workaround (Caveat is not one — it
is vacuous on guarded parsers, as shown).

**Minimal example**
```c
struct S { int fd; unsigned char buf[64]; };
/*@ requires \valid((struct S*)ctx);
    assigns ((struct S*)ctx)->buf[0..63];          // footprint via a cast pointer
*/
void fill(void *ctx) {
  extern int read(int, void*, unsigned long);       // has a libc assigns contract
  read(((struct S*)ctx)->fd, ((struct S*)ctx)->buf, 64);
}
```
Under `-wp-model +cast` the `assigns` goal (and `read`'s `buf_has_room` precondition) time out /
fail at scale, despite being trivially true; under `Caveat` they "prove" but the model is
vacuous on guarded code.

**Guidance link** — serves the mission `U` "prove RTE-robustness of the untrusted-input
parsers": this gap caps the entire **BIO/callback API surface** — `net_recv`, `ssl_ticket_parse`,
and any function reached through a `void*` context pointer. The buffer-parsing core is provable;
the call/assigns frame around it is not. Recorded in memory as `[[wp-cast-frame-defect]]`.

---

**Update 2026-06-21 (EBIOS-gap-closure pass).** Two further data points under `+cast`:
- `net_recv` improved **16/22 → 22/24** by giving the static callees `check_fd` /
  `net_would_block` minimal SOUND contracts (both then verified). The 2 remaining residuals are
  the *same* `+cast` model limit but with an explicit WP reason: **"Cast with incompatible
  pointers types (source: sint8* / uint8*→sint8*)"** — the `read(fd, buf, len)` macro casts
  `unsigned char* buf` → `char*` for `recv`, and `+cast` cannot carry the result-bound /
  assigns frame across that `char*`/`uint8*` reinterpretation.
- A *second manifestation*: `mbedtls_x509_crl_parse_der` (153/154) and
  `mbedtls_x509_csr_parse_der_internal` (219/220) each leave exactly one residual,
  `call_memset_requires_valid_s` — the validity of a `memset` destination (a fresh stack struct
  `&sig_params`) times out under `+cast` at scale (z3 60s does not close it), while the *same
  units fail many MORE goals under the Typed model* (so `+cast` is still the correct model). Same
  `+cast`-at-scale family, distinct surface (libc `memset` destination validity rather than a
  cross-call cast-pointer footprint). Not hand-proved.
