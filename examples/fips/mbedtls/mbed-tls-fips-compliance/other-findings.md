# Other findings

Everything the campaign found that is not a FIPS violation
(`mbed-tls-found-violations.md`) or a design gap (`design-gaps.md`):

1. library defects with no FIPS requirement attached;
2. observations: true behaviour that is not a defect in the shipped
   configuration;
3. defects in the verification tools;
4. errors in the campaign's own annotations, found and fixed.

Sources: `mbedtls-analysis-found-issues.md` (cycles 1 to 27) and section 6
of `mbedtls.md`.

## 1. Library defects

Each was reproduced on the pristine library, out of source tree. The
campaign recorded them as robustness findings without a requirement. The
"FIPS relevance" lines are this dossier's reading, not the campaign's.

| ID | Function | Defect | Severity | CWE |
|---|---|---|---|---|
| F20-1 | `psa_aead_finish` | NULL dereference on allocation failure | Medium (DoS) | CWE-476 |
| F24-1 | `mbedtls_asn1_write_raw_buffer`, `mbedtls_asn1_write_len_and_tag` | returned length truncated to `int` | LOW | CWE-681/190 |
| F24-2 | `mbedtls_asn1_write_named_bitstring` | out-of-bounds read `buf[-1]` | LOW | CWE-125/190 |
| F25-1 | `mbedtls_pem_write_buffer` | integer overflow in the size check | LOW/INFO | CWE-190 |

F20-1's severity and CWE are this dossier's; the campaign stated none.

### F20-1 — `psa_aead_finish` crashes on allocation failure

**Defect.** `psa_aead_finish` (`library/psa_crypto.c`, around line 5580)
allocates local copies of the ciphertext and tag buffers with
`LOCAL_OUTPUT_ALLOC`. On allocation failure it does `goto exit` with
`tag == NULL`. The exit path then calls
`psa_wipe_tag_output_buffer(tag, status, tag_size, *tag_length)`
unconditionally, which runs `memset(NULL, '!', tag_size)` (line 608). The
sibling `psa_mac_sign_finish` guards the same call with `if (mac != NULL)`.

**Reproduction** (cycle 21). AES-128-GCM multipart encryption with the
ciphertext or tag `calloc` made to fail: the sanitizer build reports
`psa_crypto.c:608:5: runtime error: null pointer passed as argument 1, which
is declared to never be null`; the Release build exits with SIGSEGV (139).
The control run without injected failure returns 0. Configuration: default
(`MBEDTLS_PSA_ASSUME_EXCLUSIVE_BUFFERS` undefined, so the copying macros are
active).

**Formal evidence.** WP proves 58/59 goals; the open one is exactly the
precondition of `psa_wipe_tag_output_buffer`. With an `if (tag != NULL)`
guard the function is 59/59. Oracle-B: 12/13 compliant.

**Effect.** A crash (DoS) instead of `PSA_ERROR_INSUFFICIENT_MEMORY`,
triggered by a large caller-supplied buffer size or an exhausted heap.

**FIPS relevance.** RQ5 (AR2, §7.3): an error ends the process instead of
being reported on the status interface. RQ33 (AR11, §7.12): forced memory
exhaustion is an input-misuse condition.

**Fix.** Guard the wipe with `if (tag != NULL)`.

### F24-1 — ASN.1 writer returns a truncated length

**Defect.** `mbedtls_asn1_write_raw_buffer` and
`mbedtls_asn1_write_len_and_tag` (`library/asn1write.c`) return a `size_t`
length cast to `(int)`, after the data has been copied and `*p` moved.

**Reproduction** (cycle 24, ASan/UBSan build, 2–5 GiB of heap;
`scratch/c24/f24`, output `scratch/c24/f24.out`):

- `f24 trunc31`: a 2³¹-byte element returns `INT_MIN` after copying 2 GiB;
- `f24 spoof108`: 2³² − 108 bytes returns −108,
  `MBEDTLS_ERR_ASN1_BUF_TOO_SMALL`, after the copy, so the one error code
  that otherwise has no side effect has one;
- `f24 trunc32`: 2³² + 5 bytes via `mbedtls_asn1_write_octet_string` returns
  7, success, with a DER header whose length octet says 5 for a
  4,294,967,301-byte payload, a malformed encoding reported as success.

**Effect.** Needs one ASN.1 element of at least 2 GiB and an output buffer
that large. API domain only.

**FIPS relevance.** RQ5 (wrong status), RQ33 (input misuse).

**Fix.** Reject lengths above `INT_MAX` before writing.

### F24-2 — `mbedtls_asn1_write_named_bitstring` reads before the buffer

**Defect.** `byte_len = (bits + 7) / 8` is computed in `size_t` and wraps to
0 when `bits > SIZE_MAX − 7`. Since `bits != 0`, the code then runs
`cur_byte = buf + byte_len - 1; cur_byte_shifted = *cur_byte >> unused_bits;`,
reading `buf[-1]` (`asn1write.c:288`).

**Reproduction.** `mbedtls_asn1_write_named_bitstring(&p, out, buf, SIZE_MAX)`
with `buf = malloc(4)`: AddressSanitizer heap-buffer-overflow READ of size 1,
one byte before the region (`scratch/c24/f24 namedbits`).
`mbedtls_asn1_write_bitstring` with the same `bits` does not fault, but
emits a bogus one-octet BIT STRING.

**Effect.** A one-byte out-of-bounds read. No caller in the library reaches
it: they all pass small constants (key usage, Netscape certificate type). It
is a missing range check on a caller-controlled argument. Not proved with WP
(the function had no contract); ASan evidence only.

**FIPS relevance.** RQ33 (input misuse).

**Fix.** Reject `bits > SIZE_MAX - 7`.

### F25-1 — `mbedtls_pem_write_buffer` size check overflows

**Defect.** The check `use_len + add_len > buf_len` can wrap, with
`use_len = 4*ceil(der_len/3)+1` (from a first `base64_encode(NULL, 0, …)`
call whose return value is ignored) and
`add_len = strlen(header) + strlen(footer) + (use_len-2)/64 + 1`.

**Reproduction.** `der_len = 13622211008277822708`, header
`-----BEGIN X-----\n`, footer `-----END X-----\n`, `buf_len = 8`: the sum
wraps to 3, the `BUFFER_TOO_SMALL` check passes, `calloc(1,
0xfc0fc0fc0fc0fbf1)` fails, and the function returns
`MBEDTLS_ERR_PEM_ALLOC_FAILED` instead of
`MBEDTLS_ERR_BASE64_BUFFER_TOO_SMALL`, without setting `*olen`
(`scratch/c25/f25`; the control `der_len - 3000` returns `BUFFER_TOO_SMALL`
correctly). No memory is touched; ASan is clean.

**Effect.** Wrong error code. Needs `der_len > 1.3 × 10¹⁹`, API domain only.
Probed, not proved: `pem_write_buffer` 66/104 with a bare contract.

**FIPS relevance.** RQ5 (wrong status).

**Fix.** Reject `use_len == SIZE_MAX` and check
`use_len > buf_len - add_len`, or add with overflow detection.

## 2. Observations

### OBS-1 — `mbedtls_hkdf_expand` can leave part of a derived key on error

When an HMAC call fails at iteration 2 or later, the blocks `T(1)` to
`T(i-1)` already copied into the caller's `okm` buffer stay there, and the
function returns an error. WP proves `ensures \result != 0 ==> okm
unchanged` only under the assumption SL-MD-2 that the HMAC calls cannot fail
on a set-up context.

- **Shipped configuration: not reachable.** The built-in hash engines never
  fail once `md_setup` succeeded, and `MBEDTLS_MD_SOME_PSA` and the `*_ALT`
  engines are off.
- **Other configurations: live** under `MBEDTLS_MD_SOME_PSA` (a PSA hash
  driver error) or an `*_ALT` engine.
- **FIPS relevance.** RQ18 (AR8, §7.9): SSPs zeroized on every error path.
  A configuration-dependent residual; a build that enables either option
  should wipe `okm` on error.

### O-4 — stateless hash entry points run before initialization

`psa_hash_setup(PSA_ALG_SHA_256)` returns `PSA_SUCCESS` and
`psa_hash_compute` proceeds before `psa_crypto_init`. The PSA specification
says an uninitialized library returns `PSA_ERROR_BAD_STATE`. Not a
memory-safety defect (no state is touched); a specification leniency.
**FIPS relevance:** RQ30 (state model): a FIPS wrapper must gate these
entries, since nothing in the library does. Reproducers:
`repro/gen_sweep.py` and `sweep.c`.

### CFG-1 — the verified zeroization branch is `explicit_bzero`

In the as-built configuration (glibc ≥ 2.25), `mbedtls_platform_zeroize`
uses `explicit_bzero`, not the volatile-`memset` fallback that Frama-C's own
libc would select. The campaign replayed the real preprocessor outcome, so
the verified branch is the shipped one. `entropy_poll.c` needs
`<sys/random.h>` (`getrandom`) and is blocked as a system call.

### Recorded, not defects

- `mbedtls_asn1_write_int(-1)` encodes `02 02 00 ff` (255). The header
  documents "val must be non-negative"; the function is memory-safe for
  every `int` (proved 69/69 for the static core).
- `mbedtls_asn1_get_mpi` advances `*p` even when
  `mbedtls_mpi_read_binary` fails. By design; it stays within `end`.
- Cycles 25 and 26 hunted base64 decode/encode underflows, look-ahead reads
  and `buf[-1]` patterns, and the ASN.1 parser's length handling, and found
  nothing. A sanitizer run of 22,843,039 ASN.1 parser cases reported nothing.

## 3. Tool defects

| ID | Tool | Defect | Effect on the campaign |
|---|---|---|---|
| **TOOL-1** | Frama-C 32.1 kernel | `struct S { char a[sizeof("x")]; };` crashes at parse: `Failure: Trying to add the same varinfo twice: __fc_lit_string1` (`file.ml:1253`, `register_global`). Only inside struct fields; block-scope uses parse | blocked `psa_crypto_storage.c` and the TLS 1.3 units (`ssl_client.c`, `ssl_tls.c`, `ssl_tls13_*.c`); a source-level workaround (`litsize.py`, opt-in `LITSIZE=1`) lets them parse, but no proof relies on it. **Worth reporting to Frama-C**: the reproducer is one line |
| TOOL-2 | WP | `\freeable` is not implemented, so libc `free()`'s precondition cannot be discharged | one goal per `free` call stays open (`mbedtls_zeroize_and_free` 7/8); zeroize-before-free itself is proved |
| TOOL-3 | WP | an inline `asm` with a variable-length array operand aborts WP (`Non-constant expression (len)`) unless the `asm` has a contract | the `asm` in `mbedtls_platform_zeroize` carries a trusted contract (SL-ASM-1) |
| — | WP, Frama-C libc | `memcmp` requires `\object_pointer` / `!\dangling`, which WP does not implement | 4 unprovable goals per `memcmp` call (cycle 26) |
| — | Why3 prelude | `land` is an uninterpreted parameter with no value/bit bridge | `initialized == 0` after `mbedtls_psa_crypto_free` is unprovable as a number; proved bit by bit with Coq |

## 4. Errors in the campaign's own annotations

The campaign's process caught these; each was fixed, and the affected
proofs were retracted and re-proved. They are recorded because they bound
how far an individual proof can be trusted.

| ID | Cycle | Error | How it was caught | Repair |
|---|---|---|---|---|
| **VAC-1** | 7 → 7b | A ghost registry `md_infos[11]` was declared in `md.h` as a `const` definition without initialiser. In `hkdf.c`, WP assumed it all NULL, so every `md != NULL` path of `mbedtls_hkdf_expand` was proved **vacuously** | a seeded fault (`memcpy(…, num_to_copy + 1)`) stayed green; Oracle-B seeds stayed green | declared `extern` (patch 0019); two rows retracted; re-proved 103/103 with non-vacuity probes (cycle 8) |
| — | 9 → 10 | trusted contract claimed `*key_buffer_length <= key_buffer_size`, false in general | body proof of the driver wrappers | moved to a `requires`; wrapper bodies now proved |
| — | 9 → 10 | a trusted contract's `assigns` omitted state it writes | same | fixed |
| — | 11 | `ecp_group_free` loop annotation evaluated its sets in the wrong state | assigns goals unprovable as written | fixed; 88/94 |
| — | 11 | a stub's failure postcondition was false for an arbitrary caller pointer | soundness audit of every `ensures` against the body | added a `requires` (all callers comply) |
| — | 12 | `psa_start_key_creation` stub footprint evaluated in the entry state; `psa_wipe_key_slot` contract omitted the key-buffer wipe and `free` | an inconsistent proof result in cycle 11 | patch 0025; 17 rows re-proved |
| RES-1 | 1 → 3 | `ctr_drbg_free` sub-range goal open (23/25), suspected layout | the cause was an SMT instantiation limit | closed 29/29 with one Coq goal |

## 5. Campaign hygiene

- The cycle-27 commit swept about 270 scratch files (roughly 220,000 lines)
  from a verifier's working copy into the campaign repository, and they were
  pushed. No result depends on them.
- The Gate-T terminus check fails (`residuals-and-signoff.md`), so the
  campaign is paused, not finished.
