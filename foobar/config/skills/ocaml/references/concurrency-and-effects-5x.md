# OCaml 5.x concurrency, parallelism & effects (manual §9–10, §12)

OCaml 5 replaced the single-threaded runtime with a **multicore** one: real shared-memory parallelism
(`Domain`), effect handlers (`Effect`), and a defined **memory model**. This is the headline change
from 4.x. The old global runtime lock is gone.

## Two different axes — don't conflate them
- **Parallelism** = running on multiple cores at once → **`Domain`** (≈ one OS thread pinned to a core).
- **Concurrency** = interleaving tasks on (possibly) one core → the **`threads`** library, or
  user-level scheduling built on **effect handlers**. Concurrency ≠ parallelism.

## Domains — true parallelism (§9)
```ocaml
let d = Domain.spawn (fun () -> heavy_compute ())   (* runs in parallel *)
let r = Domain.join d                                (* wait + get result *)
```
- Spawn ~one domain per core (`Domain.recommended_domain_count ()`); domains are heavyweight — use a
  small pool, not one per task. Libraries: **`domainslib`** (parallel task pools, `parallel_for`).
- Shared mutable state across domains needs synchronization (below); pure/immutable data is free to share.

## Synchronization
- **`Atomic`** — lock-free atomic refs: `Atomic.make`, `get`, `set`, `exchange`, `compare_and_set`,
  `fetch_and_add`. The right tool for counters/flags shared across domains.
- **`Mutex`** (`create`/`lock`/`unlock`/`protect`), **`Condition`** (`wait`/`signal`/`broadcast`),
  **`Semaphore`** — classic locks for compound critical sections.
- Rule: **every shared mutable location is either immutable-after-publish, atomic, or mutex-protected.**

## The memory model (§10, "The hard bits") — exact 5.4 guarantees
**Locations.** `Atomic` cells are *atomic* locations; **"reference cells, array fields and mutable
record fields are non-atomic memory locations"** ("immutable objects are non-atomic locations with an
initialising write but no further updates").
**Data race (exact definition).** Two actions *conflict* if they "access the same non-atomic location,
at least one is a write and neither is an initialising write." A program *has a data race* if some
execution trace has two conflicting actions with **no happens-before** relation between them.
**The two guarantees:**
- **DRF-SC** — *"A program without data races will only exhibit sequentially consistent behaviours."*
  So if every shared mutable location is atomic- or mutex-protected, you may reason about execution as
  a plain interleaving.
- **LDRF-SC** (programs *with* races) — *"the data race free parts of the program remain sequentially
  consistent … those parts that are disjoint from the parts with data races are amenable to sequential
  reasoning"*, and *"even for programs with data races, memory safety is preserved"* (no crashes /
  no garbage values, unlike C/C++ UB). But the racy parts are genuinely non-deterministic — safety is
  **local**, not a licence to race.
- **Atomics are sequentially consistent** (NOT merely release/acquire — the manual gives no
  release/acquire knobs; atomic ordering is total per location): *"If x is a write to an atomic
  location and y is a subsequent read or write to that memory location … then x precedes y in
  happens-before order."* **happens-before** (irreflexive, transitive) is built from program order
  within a domain, atomic accesses, `Domain.spawn`/`join`, and `Mutex` unlock→lock.
**Publication.** To hand a structure to another domain, publish its pointer through an `Atomic` (or a
mutex) — that establishes happens-before so the reader sees a fully-initialised object.
**Tearing / "non-compliant operations" (§6).** A few ops may *tear* under a race ("the field may end
up with bits from either of the writes"): `Array.blit` on float arrays, float fields on 32-bit
architectures, and mixed-mode `Bytes` accesses. Memory safety still holds, but avoid racing on these.

## Effect handlers (the 5.x feature) — resumable effects
An *effect* is declared by extending `Effect.t`; `perform` invokes it; the nearest *handler* receives
it with a **continuation** of the suspended computation and decides whether/how to resume. This gives
schedulers, async I/O, generators, and backtracking in **direct style**, without monads.

**5.4 handler syntax** — the documented deep form uses an **`effect` pattern** in `try … with`:
```ocaml
type _ Effect.t += Xchg : int -> int Effect.t       (* "takes an int parameter, returns an int" *)

let comp () = perform (Xchg 0) + perform (Xchg 1)

let run () =
  try comp () with
  | effect (Xchg n), k -> continue k (n + 1)         (* k = the captured continuation *)
```

**The explicit API** (`Effect.Deep`, for the record/first-class form):
```ocaml
type _ Effect.t += Get : int Effect.t

let run () = Effect.Deep.match_with (fun () -> 1 + perform Get) ()
  { retc = (fun v -> v)                              (* 'a -> 'b   : normal return  *)
  ; exnc = raise                                     (* exn -> 'b  : uncaught exn   *)
  ; effc = (fun (type c) (eff : c Effect.t) ->       (* 'c. 'c t -> (('c,'b) continuation -> 'b) option *)
      match eff with
      | Get -> Some (fun (k : (c,_) Effect.Deep.continuation) -> Effect.Deep.continue k 41)
      | _   -> None) }                               (* None  => forward to an outer handler *)
```

**Exact stdlib signatures** (`Effect`, `Effect.Deep`):
```ocaml
type 'a Effect.t = ..
val perform : 'a Effect.t -> 'a
exception Unhandled : 'a Effect.t -> exn
exception Continuation_already_resumed
(* Effect.Deep: *)
type ('a, 'b) continuation
val continue                   : ('a,'b) continuation -> 'a  -> 'b
val discontinue                : ('a,'b) continuation -> exn -> 'b
val discontinue_with_backtrace : ('a,'b) continuation -> exn -> Printexc.raw_backtrace -> 'b
type ('a,'b) handler = { retc : 'a -> 'b;  exnc : exn -> 'b;
                         effc : 'c. 'c Effect.t -> (('c,'b) continuation -> 'b) option }
val match_with : ('c -> 'a) -> 'c -> ('a,'b) handler -> 'b
type 'a effect_handler = { effc : 'b. 'b Effect.t -> (('b,'a) continuation -> 'a) option }
val try_with   : ('b -> 'a) -> 'b -> 'a effect_handler -> 'a
```

**Key rules (verbatim from §effects):**
- **One-shot only.** *"OCaml does not support multi-shot continuations."* *"Every captured continuation
  must be resumed either with a `continue` or `discontinue` exactly once."* Resuming again raises
  **`Continuation_already_resumed`**; simply dropping `k` aborts that computation.
- **No effect safety / no type tracking.** *"effect handlers in OCaml do not provide effect safety;
  the compiler does not statically ensure that all the effects performed by the program are handled."*
  An effect with no matching handler raises **`Effect.Unhandled`** *"at the point of the corresponding
  `perform`"* — so document which effects a function may perform.
- **Deep vs Shallow.** `Effect.Deep` keeps the handler installed across resumes (the common case);
  `Effect.Shallow` (`continue_with` / `fiber`) returns a bare fiber you re-handle at each step.
- Application code normally uses **Eio** (the effects-based I/O/concurrency stack) or `domainslib`;
  reach for raw `Effect` to *build* such an abstraction, not in everyday code.

## The threads library (§34)
`Thread.create`, plus `Mutex`/`Condition`. Threads give concurrency and, in OCaml 5, can run in
parallel only insofar as they sit on different domains; for CPU-parallel work prefer `Domain`/domainslib.
`Thread` is mostly for blocking-I/O concurrency and legacy code.

## Practical guidance
- CPU-bound parallel work → `Domain` + `domainslib` (a fixed pool sized to cores).
- I/O-bound concurrency → **Eio** (effects-based) or `Thread` + blocking calls.
- Shared state → `Atomic` for scalars, `Mutex.protect` for sections; publish via atomics.
- Reach for raw `Effect` only to *build* a scheduler/abstraction; otherwise use a library that wraps it.
- **ThreadSanitizer** (manual §27): `--enable-tsan` builds detect data races at runtime — use it on
  any nontrivial parallel code.
