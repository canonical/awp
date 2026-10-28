# OCaml language extensions (manual §4–7, §12)

## Labeled & optional arguments (§4)
```ocaml
let sub ~from ~len s = String.sub s from len        (* labeled: call sub ~from:0 ~len:3 s *)
let create ?(size = 16) name = …                    (* optional with default *)
create "x";  create ~size:64 "y"                     (* ?size omitted -> default *)
```
- `~x` labels an argument (order-independent at call sites; `~x` alone = `~x:x` punning).
- `?x` is optional, type `'a option` inside (`?(x = d)` supplies a default). Pass explicitly with
  `?x:(Some v)` or `~x:v` via the label. **Erasure criterion (manual §4, verbatim):** *"The criterion
  for deciding whether an optional argument has been omitted is the non-labeled application of an
  argument appearing after this optional argument in the function type."* I.e. an optional arg is
  defaulted only when a **later argument is applied positionally (unlabeled)**; if the optional arg is
  last (or only followed by labeled args), it is **not** erased — the call returns a function, not the
  result (the "optional argument cannot be erased" situation).

## Polymorphic variants (§5)
Structural, *open* variants — tags exist without a prior `type` declaration:
```ocaml
let f = function `Int n -> n | `Str s -> String.length s    (* [> `Int of int | `Str of string ] *)
```
- Backtick tags `` `Tag ``; types are sets: `` [> `A | `B ] `` = **lower bound** (open — "at least"
  these, more tags may be *defined*), `` [< `A | `B ] `` = **upper bound** (closable — "at most" these,
  may *allow less*), `` [ `A | `B ] `` = an **exact** type. (Manual: the `>`/`<` "show that they may
  still be refined, either by defining more tags or by allowing less.") Good for extensible/ad-hoc
  unions and avoiding constructor-name clashes; cost: fuzzier
  inference and worse error messages. Prefer ordinary variants unless you need the openness.

## Polymorphism limits & GADTs (§6–7)
- **Value restriction** (§6): only syntactic values get generalized; `ref []` is weakly polymorphic
  (`'_weak`) until used at one type. Eta-expand or annotate to recover polymorphism.
- **GADTs** (§7) — constructors that *refine the result type*, enabling type-safe interpreters,
  well-typed ASTs, and existentials:
```ocaml
type _ expr =
  | Int  : int -> int expr
  | Bool : bool -> bool expr
  | Add  : int expr * int expr -> int expr
  | If   : bool expr * 'a expr * 'a expr -> 'a expr

let rec eval : type a. a expr -> a = function   (* `type a.` = locally abstract, needed for GADTs *)
  | Int n        -> n
  | Bool b       -> b
  | Add (x, y)   -> eval x + eval y
  | If (c, t, e) -> if eval c then eval t else eval e
```
Matching a constructor recovers a **type equation** (local constraint): matching `Int n : int expr`
teaches `a = int` in that branch (the manual: "constraints associated to each constructor can be
recovered through pattern-matching" when the scrutinee has a **locally abstract type**). Use the
explicit **`let rec f : type a. a t -> …`** annotation: without it OCaml infers a *monomorphic* type
for the recursive function, an **existential** GADT variable then "flows to the type of the recursive
function, and thus escapes its scope" — so the `type a.` form (polymorphic recursion + locally
abstract type) is **required**, not stylistic.

## Other extensions (§12)
- **Extensible variants**: `type t = ..` then `type t += C of int` — add constructors later;
  `exception` is the canonical instance (`exn` is an open type).
- **Private types**: `type t = private int` (or `private` rows/variants) — clients can read/coerce
  but not *construct*, enforcing smart-constructor invariants.
- **Recursive modules**, **first-class modules**, **locally abstract types** `(type a)` — see
  `modules-and-functors.md`.
- **Attributes & extension nodes** (the ppx surface):
  - `[@attr]` (on expressions), `[@@attr]` (on items), `[@@@attr]` (standalone). Built-ins:
    `[@inline]`, `[@tail_mod_cons]`, `[@warning "-8"]`, `[@@deriving …]`, `[@@ocaml.doc "…"]`.
  - `[%ext payload]` / `[%%ext …]` are **extension nodes** rewritten by **ppx** preprocessors at
    compile time (dune: `(preprocess (pps ppx_foo))`). Ubiquitous ones: **`ppx_deriving`/`ppx_deriving_yojson`**
    (`[@@deriving show, eq, ord, yojson]` auto-generates `pp`/`equal`/`compare`/JSON), **`ppx_expect`**
    (inline `let%expect_test`), **`ppx_let`** (`let%bind`/monadic syntax), **`ppx_sexp_conv`**.
  - A ppx is a compile-time AST→AST rewriter; `ocaml -dsource` / `dune` show the expansion.

## Effect handlers (§12, the 5.x feature)
Resumable effects — perform an effect, a handler decides whether/how to resume. The basis for
schedulers, async I/O, generators, and dependency injection *without* monads. See
`concurrency-and-effects-5x.md` for the `Effect`/`Effect.Deep` API and a worked example.
