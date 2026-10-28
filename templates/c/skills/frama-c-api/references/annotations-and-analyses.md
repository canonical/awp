# ACSL annotations, properties/status, values, and the analyses

How to read/emit ACSL, record verification verdicts, and query the value/WP analyses from OCaml.
**These APIs are among the most version-volatile in the kernel** (Eva's query API in particular has
been reworked across releases) — treat the shapes below as the model and confirm exact names against
*your* installed Frama-C's odoc.

## Reading & adding annotations — `Annotations`
The module doc is explicit: *"The AST should be computed before calling functions of this module."*
Exact signatures (verbatim; `?kf` is an optimization hint, `Emitter.t` is **required** to add):
```ocaml
(* read *)
val funspec    : ?emitter:Emitter.t -> kernel_function -> funspec
val code_annot : ?emitter:Emitter.t -> ?filter:(code_annotation -> bool) -> stmt -> code_annotation list
val iter_code_annot : (Emitter.t -> code_annotation -> unit) -> stmt -> unit
(* + has_code_annot, behaviors, requires, ensures, assigns *)
(* add (needs an Emitter) *)
val add_assert     : Emitter.t -> ?kf:kernel_function -> stmt -> predicate -> unit
val add_code_annot : Emitter.t -> ?kf:kernel_function -> stmt -> code_annotation -> unit
(* + add_requires, add_ensures, add_assigns, add_behaviors ; and remove_* (same emitter) *)
```
ACSL lives in `Cil_types` too: `code_annotation` (`{ annot_content = AAssert | AInvariant | AStmtSpec
| AAssigns | … }`), `funspec = { spec_behavior : behavior list; … }`, `predicate`, `term`,
`identified_predicate`. Build them with `Logic_const` (next).

## Building ACSL terms/predicates — `Logic_const`, `Logic_typing`
Verbatim signatures — **the builders take a TUPLE argument** (a common mistake is to curry them), with
`?loc` and `?names`:
```ocaml
val tinteger : ?loc:location -> int -> term        val treal : ?loc:location -> float -> term
val tvar : ?loc:location -> logic_var -> term      val term : ?loc:location -> term_node -> logic_type -> term
val tat : ?loc:location -> term * logic_label -> term       val told : ?loc:location -> term -> term
val prel : ?loc:location -> ?names:string list -> relation * term * term -> predicate
val pand : ?loc:location -> ?names:string list -> predicate * predicate -> predicate   (* + por, pimplies, piff *)
val pnot : ?loc:location -> ?names:string list -> predicate -> predicate
val pforall : ?loc:location -> ?names:string list -> quantifiers * predicate -> predicate  (* + pexists *)
val ptrue : predicate    val pfalse : predicate
val pands : ?names:string list -> predicate list -> predicate    (* + pors *)
val new_predicate : ?kind:predicate_kind -> predicate -> identified_predicate
val new_code_annotation : code_annotation_node -> code_annotation
(* relation = Rlt | Rgt | Rle | Rge | Req | Rneq *)
```
Example (0 <= t < n) — one tuple per builder:
```ocaml
open Logic_const
let p  = pand (prel (Rle, tinteger 0, t), prel (Rlt, t, tn))
let ip = new_predicate p
```
`Logic_typing` type-checks surface ACSL (`Logic_ptree`) into typed `predicate`/`term`; `Logic_utils`
has helpers (`Logic_utils.expr_to_term`, …); `Logic_env` holds logic declarations.

## Verdicts — `Property`, `Property_status`, `Emitter`
A **`Property.t`** (a.k.a. "ip") is the atomic verifiable thing (an assert, a requires, an ensures, a
loop invariant, an RTE alarm, …). Every emitter (Eva, WP, your plugin) records a *status* per property;
the kernel **consolidates** them.
Exact API (verbatim) — note **two distinct status types**, *emitted* (what one emitter says) vs the
*consolidated/local* status (the merge):
```ocaml
type emitted_status = True | False_if_reachable | False_and_reachable | Dont_know
val emit : Emitter.t -> hyps:Property.t list -> ?distinct:bool -> Property.t -> emitted_status -> unit
val register : Property.t -> unit       val remove : Property.t -> unit
(* the LOCAL status (what get returns) — not the same as emitted_status: *)
type status = Never_tried
            | Best of emitted_status * emitter_with_properties list
            | Inconsistent of inconsistent
val get : Property.t -> status          (* most precise LOCAL status + its emitters *)
(* the fully consolidated verdict is a SEPARATE submodule: *)
(* Property_status.Consolidation.get : Property.t -> Consolidation.t *)
```
Usage:
```ocaml
let emitter = Emitter.create "Hello" [ Emitter.Property_status ] ~correctness:[] ~tuning:[]
let ip = Property.ip_of_code_annot_single kf stmt code_annot
Property_status.emit emitter ~hyps:[] ip Property_status.True   (* `~hyps` = the assumptions it rests on *)
```
`emit e ~hyps p s` = "the status of `p` is `s`, emitted by `e`, based on hypotheses `hyps`" (`?distinct`
defaults to `false`). `Property.ip_of_*` builds the `Property.t` from annotations; `Property.Functions`/
`Property.iter` enumerate them. This is exactly how WP/Eva report Valid/Unknown — your plugin emits the
same way; the kernel's **`Property_status.Consolidation`** merges all emitters into the final verdict.

## Values & locations — `Locations`, `Cvalue`, `Base`, `Ival`
- **`Locations`** — memory locations & **zones**: `Locations.Zone.t` (a set of memory bits),
  `Location_Bytes`, `Locations.loc_of_varinfo`, `Zone.join`/`is_included`. The currency of
  read/write footprints (assigns, dependencies).
- **`Base`** — a memory base (a variable/allocation); `Cvalue` — the value-analysis value model
  (`Cvalue.V.t`, `Cvalue.Model.t` a memory state); **`Ival`** — integer/float abstractions
  (**flagged "interfaces may change"** — don't hard-depend).

## Running / querying the analyses
- **Eva** (value analysis): `Eva.Analysis.compute ()` runs it; query results through the **`Eva.Results`**
  API (recent kernels), e.g. `Eva.Results.(before stmt |> eval_lval lv)` / `eval_exp` / `before`/`after`
  — *the exact module path and combinators differ by version*; older code uses the deprecated
  `Db.Value.*`. Always gate on `Eva.Analysis.is_computed ()`.
- **WP** — a **separate package `frama-c-wp`** (top module `Wp`), *not* in `Frama_c_kernel`. Its
  **stable surface is 3 modules**: `Wp.VC` ("WP proof-obligation generation & management"), `Wp.VCS`
  ("provers & PO results"), and `Wp_parameters` (the plugin options). Advanced (subject to change):
  `Lang`/`Repr` (terms), `Definitions`, `Conditions`, `Tactical`/`Strategy` (tactics), `Generator`,
  `Register`; ~60+ further modules are "not intended to be used externally." **There is no single
  "run WP" function** — you generate POs via `VC` and inspect results via `VCS`; WP is primarily
  command-line-driven and **emits `Property_status`** per goal. From another plugin, either link
  `frama-c-wp` (version-locked) or run `-wp` and read the statuses.
- **Other plugins** (Slicing, Pdg, Metrics, From, Inout, Impact): each has its own library/`Dynamic`
  entry points; `From`/`Inout` give functional/operational dependencies and read/write footprints as
  `Locations.Zone`s.

## The cross-plugin seam (recap)
You call another analysis either by **linking its library** (tight coupling, version-locked) or via
**`Dynamic.get ~plugin:"Name" "registered_name" Datatype.(func a b)`** (loose; fails at the call if the
name/type changed). Either way, **a Frama-C upgrade can break the call** — the version caveat in
`../SKILL.md` applies most sharply here.
