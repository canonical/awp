# Projects, persistent state (`State_builder`), `Datatype`/`Type`

The single most important architectural fact: **all mutable state in Frama-C is *projectified*.** The
AST, every analysis result, and every plugin option belong to a **Project**; you must declare your own
mutable state through **`State_builder`** rather than with bare OCaml `ref`s, or it won't be saved,
restored, copied across projects, or invalidated when its inputs change.

## `Project` — multiple independent worlds
A project bundles one AST + all states. There can be several (e.g. an original program and a
transformed copy). Exact API (verbatim):
```ocaml
type t                                          (* a project handle *)
val create  : string -> t                       (* a fresh, empty project named … *)
val current : unit -> t      val is_current : t -> bool
val set_current : ?on:bool -> ?selection:State_selection.t -> t -> unit
val on   : ?selection:State_selection.t -> t -> ('a -> 'b) -> 'a -> 'b   (* run with t current, then restore *)
val copy : ?selection:State_selection.t -> ?src:t -> t -> unit   (* copy src's (selected) state INTO the arg — returns unit! *)
val clear : ?selection:State_selection.t -> ?project:t -> unit -> unit
val remove : ?project:t -> unit -> unit
val iter_on_projects : (t -> unit) -> unit   val find_all : string -> t list
val get_name : t -> string                   val set_name : t -> string -> unit
module Datatype : Datatype.S_with_collections with type t = t
```
```ocaml
let p = Project.create "transformed" in
Project.copy ~src:(Project.current ()) p;          (* copy current state INTO p (copy returns unit) *)
Project.on p (fun () -> transform ()) ();          (* run with p current, then restore *)
```
**Gotcha:** `Project.copy` does **not** return a new project — you `create` the destination, then
`copy ~src dst` to fill it. Most plugin code just uses the current project implicitly; reach for
`Project.on`/`copy` when doing whole-program transformations (pair with `Visitor.frama_c_copy`, see the
visitor ref).

## `State_builder` — declare projectified, dependency-tracked state
Pick the functor matching your data shape; give it a **`Datatype`** and an **`Info`** (a unique name,
the states it **depends on**, …). The result is auto-saved/restored, per-project, and cleared whenever
a dependency is cleared.
```ocaml
module Seen = State_builder.Hashtbl
  (Cil_datatype.Stmt.Hashtbl)              (* key datatype *)
  (Datatype.String)                         (* value datatype *)
  (struct
     let name = "Hello.Seen"
     let dependencies = [ Ast.self ]        (* invalidated when the AST changes *)
     let size = 97
   end)
(* now: Seen.add stmt "x"; Seen.find stmt; Seen.mem; Seen.iter; Seen.clear () — all projectified *)

module Result = State_builder.Ref (Datatype.Int)
  (struct let name = "Hello.Result"  let dependencies = [ Ast.self ]  let default () = 0 end)
(* Result.get () / Result.set n *)
```
Exact input module types + functor signatures (verbatim):
```ocaml
module type Info = sig  val name : string  val dependencies : State.t list  end
module type Info_with_size = sig  include Info  val size : int  end          (* for Hashtbl *)
module Ref        (Data : Datatype.S) (_ : sig include Info val default : unit -> Data.t end) : …
module Option_ref (Data : Datatype.S) (_ : Info) : …
module List_ref   (Data : Datatype.S) (_ : Info) : …
module Hashtbl    (H : Datatype.Hashtbl) (Data : Datatype.S) (_ : Info_with_size) : …
module Set_ref    (S : Datatype.Set) (_ : Info) : …
(* also Queue, Counter — same Info pattern *)
```
Note **`dependencies : State.t list`** (a list of `State.t`, e.g. **`Ast.self`**, an option's `.self`,
another state's `.self`). The `Hashtbl` output gives `add`/`find`/`mem`/`remove`/`iter`/`fold`/`clear`/
`length`; `Ref` gives `get`/`set`; all **projectified** (saved/restored per project) and cleared when a
dependency is cleared. **`dependencies` is load-bearing:** list every state your computation reads (at
minimum `Ast.self`) or you get stale results after the AST/options change. Memoize an expensive
computation with `State_builder.Memoizer` (or a `Ref`/`Option_ref` + a compute function).

## `Datatype` / `Type` — the typed-value substrate
Project save/restore, `Dynamic`, and the state machinery all need a *runtime description* of each type:
its name, (de)serialization, `equal`/`compare`/`hash`/`copy`/`pretty`, and `mem_project` (does a value
mention a project?). That description is a **`Datatype.S`** (verbatim):
```ocaml
module type S = sig
  type t
  val name : string
  val descr : t Descr.t           val packed_descr : Descr.packed     (* (de)serialization *)
  val reprs : t list                                                  (* sample values *)
  val equal : t -> t -> bool       val compare : t -> t -> int        val hash : t -> int
  val copy : t -> t                val pretty : Format.formatter -> t -> unit
  val mem_project : (project -> bool) -> t -> bool
  val structural_descr : Structural_descr.t    val rehash : t -> t    val varname : t -> string
end
module type S_with_collections = sig          (* S plus ready-made containers: *)
  include S    module Set : Set    module Map : Map    module Hashtbl : Hashtbl
end
```
- **Stdlib/AST types already have instances:** `Datatype.{Unit,Bool,Int,String,Float,Char,Option,List,
  Ref,Queue,Pair,Triple,Array}` and **`Cil_datatype.{Stmt,Varinfo,Exp,Lval,Typ,Location,Kf,…}`**. Build
  containers from them: `Cil_datatype.Stmt.Hashtbl`, `Varinfo.Set`, `Kf.Map`.
- **Roll your own** with **`Datatype.Make`** (input: `type t`, `name`, `reprs`, `mem_project`, + the
  rest — use the `Undefined` / `Serializable_undefined` building blocks for fields you don't implement)
  → `S with type t = X.t`; or **`Datatype.Make_with_collections`** (also needs `equal`+`compare`,
  gives `.Set`/`.Map`/`.Hashtbl`).
- **`Type`** is the lower-level dynamic type registry under `Datatype`; the combinators build `Type.t`s:
  `val pair : 'a Type.t -> 'b Type.t -> ('a*'b) Type.t`, `triple`, and
  **`val func : 'a Type.t -> 'b Type.t -> ('a -> 'b) Type.t`** — `Datatype.(func a b)` is what you pass
  to `Dynamic.register`/`Dynamic.get` (cross-plugin calls — see plugin-anatomy ref).

## State dependencies & selections
- **`Ast.self`** is the AST's state; depend on it from almost everything.
- **`State_selection`** picks a subset of the global state graph (`State_selection.with_dependencies s`,
  `only s`, `empty`, `full`) — used to scope `Project.copy`/`clear` and `-then-on`/`-then`.
- **`State_dependency_graph`** / `State_topological` expose the dependency DAG (rarely needed directly).
- Rule of thumb: if clearing the AST should drop your cached result, list `Ast.self` in
  `dependencies`; if your result depends on a plugin option, add that option's `.self` too.
