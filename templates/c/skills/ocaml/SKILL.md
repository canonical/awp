---
name: ocaml
description: >-
  Write, read, debug, and build OCaml 5.x code — grounded in the official OCaml
  5.4 manual (ocaml.org/manual/5.4). Covers the core language (let/let rec,
  Hindley-Milner type inference and parametric polymorphism, tuples/lists/arrays/
  records/variants/option/result, exhaustive pattern matching, immutability and
  ref/mutable/arrays, the value restriction), error handling (exceptions vs
  option/Result), the module system (structures, signatures, .ml/.mli, abstract
  types, FUNCTORS like Map.Make/Set.Make, first-class modules), language
  extensions (labeled/optional args, polymorphic variants, GADTs, extensible
  variants, private types, attributes [@...]/extension nodes [%...]/ppx, EFFECT
  HANDLERS), the 5.x concurrency story (Domain parallelism, Effect, Atomic/Mutex/
  Condition, the memory model), the toolchain (dune, opam, ocamlc/ocamlopt,
  ocaml/utop REPL, ocamlfind, ocamllex/ocamlyacc/menhir, ocamldoc, ocamldebug,
  C FFI), the standard library (Stdlib, List/Array/String/Map/Set/Hashtbl/Seq/
  Printf/FORMAT, Unix, Str), and idioms/pitfalls (|> and @@, float ops +. *., =
  vs ==, polymorphic compare, .mli abstraction, warnings). Use whenever the user
  writes or edits .ml/.mli files, asks about an OCaml type error, a functor, a
  dune/opam setup, GADTs, effect handlers, or how an OCaml feature works. The
  matched reference is the 5.4 manual; read the relevant references/ file before
  going deep on modules, extensions, concurrency, or the toolchain.
---

# OCaml (5.4)

OCaml is a statically-typed functional language with full type inference, algebraic
data types, a powerful module system (functors), and both bytecode (`ocamlc`) and
optimizing native (`ocamlopt`) compilers. Source is `.ml` (implementation) + optional
`.mli` (interface); a REPL is `ocaml`/`utop`; real projects use **dune** + **opam**.
This skill mirrors the 5.4 manual — read the matching `references/` file before going
deep. (For Coq/Rocq proofs use the `rocq` skill; for Frama-C/ACSL the `frama-c` skill —
Frama-C and its plugins, e.g. MetAcsl, are themselves OCaml and lean heavily on functors.)

## 1. The core language (manual Part I §1)
```ocaml
let x = 42                      (* immutable binding, type int inferred *)
let rec fact n = if n <= 1 then 1 else n * fact (n - 1)   (* let rec for recursion *)
let add x y = x + y             (* curried: int -> int -> int *)
let inc = add 1                 (* partial application *)
```
- **Type inference (Hindley–Milner)**: you rarely annotate; the compiler infers principal types.
  Annotate to document or to fix an error: `let f (x : int) : int = x`.
- **Parametric polymorphism**: `let id x = x` has type `'a -> 'a`; `List.length : 'a list -> int`.
- **Everything is an expression**; `;` sequences `unit`-typed expressions; `let … in …` is local.
- **`unit`** (`()`) is the no-information value (side-effecting functions return it).
- **Floats are separate**: `+. -. *. /.` for `float`, `+ - * /` for `int`. No implicit int↔float;
  use `float_of_int` / `int_of_float`. `1 + 2.0` is a *type error*, not a coercion.

### Data types
```ocaml
type point = { x : int; y : int }                 (* record (product) *)
type shape = Circle of float | Rect of int * int  (* variant (sum / ADT) *)
type 'a tree = Leaf | Node of 'a tree * 'a * 'a tree   (* parametric + recursive *)
```
Built-ins: `int float char string bool unit`, tuples `(a, b)`, lists `[1;2;3]` (immutable,
singly-linked), arrays `[|1;2;3|]` (mutable, O(1) index), `'a option = None | Some of 'a`,
`('a,'b) result = Ok of 'a | Error of 'b`, `'a Seq.t` (lazy sequences).

### Pattern matching (the heart of OCaml)
```ocaml
let area = function
  | Circle r        -> 3.14 *. r *. r
  | Rect (w, h)     -> float_of_int (w * h)

let rec sum = function
  | []        -> 0
  | x :: rest -> x + sum rest          (* :: deconstructs head/tail *)

match opt with
| Some v when v > 0 -> v               (* `when` guard *)
| Some _ | None     -> 0               (* or-pattern *)
```
The compiler checks **exhaustiveness** (a non-exhaustive match is warning 8 — treat it as an
error) and **redundancy**. Match on the data, don't test-and-project.

### Mutability (opt-in)
```ocaml
let r = ref 0 in r := !r + 1;           (* references: ref / ! / := *)
type counter = { mutable n : int }       (* mutable record field *)
let a = Array.make 3 0 in a.(0) <- 5     (* arrays *)
```
Default is immutable. **The value restriction**: a `let` whose RHS is not a syntactic value isn't
generalized to a polymorphic type (e.g. `let r = ref []` is weakly polymorphic `'_weak list ref`).

## 2. Error handling (§ exceptions vs values)
- **Values for expected errors**: return `'a option` (`None`/`Some`) or `('a,'e) result`
  (`Ok`/`Error`). Prefer these for recoverable, in-band conditions.
- **Exceptions for exceptional/programming errors**: `exception E of string`; `raise E`;
  `try expr with E msg -> …`. Stdlib helpers: `failwith "…"` (raises `Failure`),
  `invalid_arg "…"` (`Invalid_argument`), `assert cond`. Use `Fun.protect ~finally` for cleanup,
  and `match … with exception E -> …` to pattern-match exceptions inline.
- Don't catch `_` broadly (you'll swallow `Out_of_memory`/`Stack_overflow`/`Assert_failure`).

## 3. The module system (§2 + Part II) — read `references/modules-and-functors.md`
- A **structure** `module M = struct …end` groups types/values; a **signature**
  `module type S = sig …end` is its interface. **A `.ml` file *is* a structure; its `.mli` *is*
  the signature** — the `.mli` is the unit's abstraction boundary (hide types → make them abstract).
- **Functors** are modules parameterized by modules — the standard way to get reusable, type-safe
  generic code: `module IntMap = Map.Make (Int)`. (Frama-C's whole architecture is functorial.)
- First-class modules (`(module M : S)`), recursive modules, and `include`/`open` are in the reference.

## 4. Objects (§3) — rarely used
OCaml has a full object layer (classes, row-polymorphic object types `< m : int; .. >`), but most
code uses modules/records/variants instead. Reach for objects only for genuinely open/extensible
record-of-closures needs. See the manual §3; not expanded here.

## 5. Language extensions (§4–7, §12) — read `references/language-extensions.md`
Labeled/optional arguments (`~x`, `?x`), **polymorphic variants** (`` `Tag ``), **GADTs**
(type-indexed, refine types per branch), extensible/`exception`-like variants, private types,
locally abstract types `(type a)`, **attributes** `[@inline]`/`[@@deriving …]`/`[@@@warning …]`
and **extension nodes** `[%…]` consumed by **ppx** preprocessors, and **effect handlers** (5.x).

## 6. Concurrency & parallelism (5.x: §9, §10) — read `references/concurrency-and-effects-5x.md`
OCaml 5 added **multicore**: **`Domain`** = true parallelism (one domain ≈ one core);
**`Effect`** = effect handlers (resumable, for schedulers/async/generators); `Atomic`, `Mutex`,
`Condition`, `Semaphore`; the `threads` library = concurrency (the old global lock is gone). The
**memory model** guarantees **DRF-SC** (race-free code is sequentially consistent) and preserves memory
safety even under races (no C/C++-style UB), but racy code is non-deterministic — use `Atomic`/mutexes
for shared mutable state, and `Atomic` operations are *sequentially consistent*. This is the major 5.x story.

## 7. The toolchain (Part III) — read `references/toolchain.md`
- **opam** — package manager + compiler *switches* (`opam switch`, `opam install`, `eval $(opam env)`).
- **dune** — the build system: a `dune-project` + per-dir `dune` files; `dune build`, `dune exec`,
  `dune test`, `dune utop`. The default for any real project.
- **Compilers**: `ocamlc` (bytecode), `ocamlopt` (native), `ocaml`/`utop` (REPL), `ocamlfind`
  (findlib), `ocamllex`/`ocamlyacc`/**menhir** (lexer/parser gen), `ocamldoc` (docs), `ocamldebug`
  (time-travel debugger, bytecode), Flambda (optimizer). C FFI in §22.

## 8. The standard library & shipped libraries (Part IV) — read `references/libraries.md`
`Stdlib` is auto-opened (`List Array String Bytes Char Hashtbl Map Set Buffer Printf Format Option
Result Seq Either Fun In_channel Out_channel …`). Key idioms:
- **`Printf`/`Format`** — `Printf.printf "%d\n"`; **`Format`** is the pretty-printer (boxes,
  `Format.fprintf fmt "@[%a@]" pp x`) used everywhere in compilers/Frama-C for structured output.
- **`Map.Make`/`Set.Make`/`Hashtbl`** — functor-built balanced maps/sets vs imperative hash tables.
- **`Seq`** — lazy iterators; **`Buffer`** — efficient string building. External: **`Unix`** (syscalls),
  **`Str`** (regex; non-reentrant — prefer the `re` opam lib for new code).

## 9. Idioms, pitfalls, conventions
- **Pipelines**: `x |> f |> g` (apply left-to-right); `f @@ x` = `f x` (avoids parens).
- **Equality**: `=` is *structural* (deep), `==` is *physical* (pointer). Use `=`; never `==` except
  for identity/perf. Polymorphic `=`/`compare`/`Stdlib.compare` work on most types but **raise on
  functions** and are slow/footgunny on abstract types — prefer type-specific `Int.equal`, `String.compare`, etc.
- **Floats**: don't mix int/float ops; `=` on floats is exact-bit equality (`nan <> nan`).
- **`open` sparingly** — prefer `Module.f` or local `let open M in …` / `M.(…)`; broad `open` hurts
  readability and shadows.
- **Abstraction via `.mli`** — expose the minimal signature; make types `abstract` to enforce invariants.
- **Warnings are signal** — build with warnings-as-errors in dev (dune `:standard` profile);
  non-exhaustive match (8), unused (26/27), partial application of `;`-discarded non-unit.
- **Ignore explicitly**: `ignore (f x)` or `let _ = …`; a non-`unit` value before `;` warns.
- **Tail recursion**: deep recursion on lists can stack-overflow; use accumulators or `List`'s
  tail-recursive variants; 5.x has Tail-Modulo-Cons (`[@tail_mod_cons]`, manual §26).

## 10. Doc & style conventions
- **ocamldoc comments** are `(** … *)` *before* a declaration; `(* … *)` are ordinary comments.
  Tags: `@param`, `@return`, `@raise`, `@since`, `@deprecated`. The `.mli` is where doc lives.
- Naming: `snake_case` for values/types, `Capitalized` for modules/constructors/variants,
  `'a` type vars. A type and its main module often share a name (`Foo.t`, the "`t` convention").

## Reference files
- `references/modules-and-functors.md` — structures, signatures, `.ml`/`.mli`, abstract types,
  functors (`Map.Make` pattern), first-class/recursive modules, `include`/`open`.
- `references/language-extensions.md` — labeled/optional args, polymorphic variants, GADTs,
  extensible variants, private types, attributes/extension nodes/ppx, `[@@deriving]`.
- `references/concurrency-and-effects-5x.md` — Domain, Effect handlers, Atomic/Mutex/Condition,
  the memory model, the threads library (the OCaml-5 multicore story).
- `references/toolchain.md` — manual Part III + community build tools: opam, dune, the compilers,
  the REPL directives, ocamllex/menhir, ocamldoc, debugging/profiling, the C interface/FFI.
- `references/libraries.md` — manual Part IV (§28–35): core vs standard library, the compiler-libs
  front-end (+ instability caveat), `unix`, `str` (vs `re`), `runtime_events`, `threads`, `dynlink`.
- Upstream: the **OCaml 5.4 manual** — https://ocaml.org/manual/5.4/ (the authority; this skill
  summarizes it — verify version-specific details there, especially §9–10 and §12).
