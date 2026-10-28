# The ACSL standard library — what Frama-C already specifies

Frama-C ships an **ACSL-annotated libc** and includes it by default. Before stubbing a libc call, or
calling any code "out of WP's reach", **check here first**. Excerpts below are grounded in the
`framac-coq8` install (Frama-C 32.1); paths/specs may shift between versions — re-grep yours.

## Where it is / how to look
```sh
LIBC="$(frama-c -print-share-path)/libc"
grep -n 'strtok'  "$LIBC/string.h"          # the contract precedes the `extern` declaration
sed -n '280,295p'  "$LIBC/string.h"          # read the full /*@ ... */ block
```
It is on by default; `-no-framac-stdlib` turns it off (then you supply your own headers/stubs).

## What is specified (representative, not exhaustive)

### `string.h` — contracts + ACSL logic functions
- `strlen`, `strcmp` are exposed as **ACSL logic functions** (usable inside your own specs), and the C
  functions are tied to them:
  ```c
  /*@ assigns \result \from indirect:s1[0..strlen(s1)], indirect:s2[0..strlen(s2)];
      ensures acsl_c_equiv: \result == strcmp(s1,s2); */
  extern int strcmp (const char *s1, const char *s2);
  ```
- `strchr` (bounded result into the string), `strncpy`, `strstr`, `memcpy`/`memmove`/`memset`, … all
  carry `assigns`/`\from` footprints.
- `strtok` is modelled **stateful** with a ghost cursor:
  ```c
  //@ ghost __FC_INTERN char *__fc_strtok_ptr;
  /*@ requires separation: \separated(delim+(0..strlen(delim)), s+(0..strlen(s)));
      assigns __fc_strtok_ptr[0..] \from __fc_strtok_ptr[0..], …;
      assigns \result \from s, __fc_strtok_ptr, indirect:s[0..], …; */
  ```

### `unistd.h` — IO with named behaviors
```c
/*@ behavior partial_or_error:
      assumes nondet: !Frama_C_entropy_source;
      ensures result_error_or_read_length: -1 <= \result < count;
      ensures initialization:buf: \initialized(((char*)buf)+(0..\result-1));
    disjoint behaviors; complete behaviors; */
extern ssize_t read(int fd, void *buf, size_t count);
```
`write`, `close` likewise.

### `sys/socket.h` — sockets are specified
```c
/*@ assigns \result \from indirect:domain, indirect:type, indirect:protocol,
                          indirect:__fc_socket_counter;
    assigns __fc_socket_counter \from …;
    ensures result_error_or_valid_new_sockfd:
            0 <= \result < __FC_MAX_OPEN_SOCKETS || \result == -1; */
extern int socket(int domain, int type, int protocol);
```
`bind`, `listen`, `accept`, `setsockopt` similarly. **`socket`/syscall ≠ "out of reach".**

### `stdio.h` variadics — via the Variadic plugin, not a static contract
The header states verbatim: *"Direct specifications for variadic functions are unsupported; use the
Variadic module instead."* So `snprintf`/`sprintf`/`sscanf`/`printf`/`fprintf` have **no `/*@ … */`
block**; the **Variadic plugin** (on by default) rewrites each call to a specialized, specified
function. They are still analyzable — just through that transformation, and with coarse specs.

## What this does (and does not) buy you
- **Buys:** WP can be *run* on libc-heavy code (string parsing, IO, sockets) — calls are modelled by
  these contracts, not havoc. RTE goals around them are real.
- **Does not buy (automatically):** deep functional facts. The specs are mostly `assigns`/`\from` +
  bounded `\result`, **not** full input→output semantics (e.g. `snprintf` does not pin its formatted
  bytes; `read` only bounds `\result` and initializes the buffer prefix). Proving a property *through*
  a string-search loop still needs **your** `loop invariant`s and any sharpened callee contracts. So
  "libc-heavy ⇒ unprovable" is wrong; the honest cost is **invariants + coarse specs = effort**.

## The rule
A *negative* capability claim ("unspecified", "out of WP's reach", "BLOCKED") is an **evidence claim**.
Grep this libc, check `-wp-detect` / a plugin's own `tests/`, or run a one-file probe before asserting
it. If unchecked, say so — do not assert. (See the `frama-c` SKILL "Grounding rule" and the
`frama-c-monitoring` getting-better note `20260620-1300-negative-capability-claims-must-be-grounded`.)
