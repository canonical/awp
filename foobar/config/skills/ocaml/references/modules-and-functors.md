# OCaml modules & functors (manual §2, Part II §11–12)

The module system is OCaml's tool for abstraction, namespacing, and *type-safe generic code*. It is
a small typed language **over** the core language.

## Structures and signatures
```ocaml
module Stack = struct
  type 'a t = 'a list
  let empty = []
  let push x s = x :: s
  let pop = function [] -> None | x :: s -> Some (x, s)
end

module type STACK = sig
  type 'a t                         (* ABSTRACT: clients can't see it's a list *)
  val empty : 'a t
  val push  : 'a -> 'a t -> 'a t
  val pop   : 'a t -> ('a * 'a t) option
end

module S : STACK = Stack            (* seal Stack behind STACK -> 'a t is now opaque *)
```
- A **structure** (`struct … end`) is a value; a **signature** (`sig … end`) is its type.
- Sealing with `: STACK` **hides** everything not in the signature and makes `type 'a t` *abstract*,
  so clients can only build/inspect stacks through the listed functions — the invariant is enforced
  by the type system.

## `.ml` / `.mli` files ARE modules / signatures
A file `stack.ml` defines module `Stack`; an adjacent `stack.mli` is its signature. **The `.mli` is
the abstraction boundary** — anything not in it is private to the unit, and a type written as
`type t` (no `=`) in the `.mli` becomes abstract. Writing `.mli` files is the primary way to control
the API surface; omit one and *everything* is exported. (`dune` compiles `foo.ml`(+`foo.mli`) into
module `Foo`.)

## Functors — modules parameterized by modules
The reason OCaml needs no ad-hoc generics/templates: a **functor** takes a module and returns a module
(the manual: functors are *"functions from modules to modules"*).
```ocaml
module type ORDERED = sig type t val compare : t -> t -> int end

module MakeSet (E : ORDERED) = struct
  type elt = E.t
  type t = elt list                 (* sorted, say *)
  let mem x s = List.exists (fun y -> E.compare x y = 0) s
  (* … insert/remove using E.compare … *)
end

module IntSet = MakeSet (Int)       (* Int : ORDERED (it has t=int, compare) *)
```
This is exactly the **stdlib pattern**:
```ocaml
module SMap = Map.Make (String)     (* String : Map.OrderedType *)
module ISet = Set.Make (Int)
let m = SMap.(empty |> add "a" 1 |> add "b" 2)
```
`Map.Make`/`Set.Make`/`Hashtbl.Make` are functors over a key/element module providing `compare`
(or `equal`+`hash`). **Frama-C, MetAcsl, and most large OCaml** are built this way — a kernel
exposes functors (state, datatypes, plugin registration) that plugins instantiate.

### Sharing constraints (`with type`)
A functor result often has abstract types you need to *connect* to the argument:
```ocaml
module MakeSet (E : ORDERED) : sig type elt val mem : elt -> t … end
  with type elt = E.t              (* expose elt = E.t so callers can use E's values *)
```
`with type t = …` (and `with module M = …`) is the manual's **`with type` construct** that "enriches a
signature with extra type equalities" (the classic *sharing constraint*) — essential to keep functor
outputs usable. There is also **destructive substitution `with type t := …`** (and `with module M := …`),
which *removes* the type field while substituting it everywhere — used to erase a now-redundant
abstract type from a signature rather than just equate it.

## First-class modules (a §12 language-extension, not the §2 tutorial)
Pack a module into a value to choose implementations at runtime:
```ocaml
let pick (module M : STACK) = M.empty           (* (module M : S) is a value of type (module S) *)
let s = (module Stack : STACK)                  (* pack *)
module M = (val s : STACK)                       (* unpack *)
```
Useful for plugin tables, dependency injection. Heavier than functors; reach for them when the
choice is genuinely dynamic.

## `include`, `open`, recursive modules
- **`include M`** *splices* M's contents into the current structure/signature (re-export + extend) —
  how you build a module that "is an M plus more". Different from `open`.
- **`open M`** brings M's names into scope (prefer local `let open M in …` or `M.(…)`; broad top-level
  `open` shadows and hurts readability).
- **`module rec`** — mutually recursive modules (need explicit signatures); used for mutually
  recursive types across module boundaries.

## Practical rules
- Put the public API in a `.mli`; make types abstract unless clients must pattern-match them.
- Use functors for *type-indexed* reuse (containers keyed by a type); first-class modules for *runtime*
  choice; plain records-of-functions for the simplest "strategy" needs.
- The **`t` convention**: a module about a type names it `t` (`Foo.t`), giving `Foo.compare : t -> t -> int`,
  `Foo.equal`, `Foo.pp`. Stdlib modules `Int`, `String`, `Option`, … all follow it (and so satisfy the
  `Map.Make`/`Set.Make` argument signatures out of the box).
