---
name: frama-c-api
description: >-
  Develop Frama-C PLUGINS and analyzers in OCaml against the Frama-C kernel API
  (https://frama-c.com/api/ — the Frama_c_kernel library). This is the
  programmer-facing API, distinct from the `frama-c` skill (writing ACSL) and
  `frama-c-monitoring` (the squeeze loop). Covers: plugin anatomy (the
  Plugin.Register functor, command-line options via Self.False/String/Int/…,
  logging via Self.result/feedback/warning/abort, registering the entry point
  with Db.Main.extend / Boot.Main.extend, the dune setup with frama-c.kernel, and
  Ptests); the CIL C AST (Cil_types: file/global/fundec/stmt/instr/exp/lval/typ/
  varinfo, Cil helpers, Cil_datatype, Cil_const, Ast.get, Globals) and the
  Visitor framework (Visitor.frama_c_inplace/copy, the visitAction constructors
  DoChildren/SkipChildren/ChangeTo/ChangeDoChildrenPost, Printer); the project &
  state model (Project, State_builder functors for persistent projectified state,
  Datatype, Type, state dependencies); ACSL/annotation APIs (Annotations,
  Property, Property_status, Emitter, Logic_const, Logic_typing, Kernel_function);
  values & locations (Locations, Cvalue, Base, Ival) and the analysis plugins
  (Eva, Wp) reached via Dynamic. Use whenever the user writes/reads a Frama-C
  plugin in OCaml, asks about Cil_types/the AST, the visitor, projects/State_builder,
  Annotations/Property, or how to call Eva/WP from OCaml. Load-bearing caveat: the
  plugin API is NOT stable across Frama-C versions — pin to your installed version
  (this repo: 32.1 Germanium); the web API may document a different one. Built on
  OCaml (see the `ocaml` skill — Frama-C is functor-heavy).
---

# Frama-C plugin-development API (the kernel API)

The OCaml API for **writing Frama-C plugins and analyzers** — the programmer's view of the kernel,
documented at **https://frama-c.com/api/** (entry point: the **`Frama_c_kernel`** library, 250+
modules). This is *not* the ACSL-authoring reference (`frama-c` skill) nor the verification loop
(`frama-c-monitoring`): it is how you *build* an analysis in OCaml. Frama-C is heavily functorial OCaml
— read the **`ocaml` skill** (especially modules-and-functors) alongside this.

## ⚠ The load-bearing caveat: the plugin API is NOT stable across versions
Modules carry warnings like *"The interfaces of this module may change between Frama-C versions"*; the
plugin API as a whole shifts release to release (renames, signature changes, deprecations). **Pin your
code to the Frama-C version you build against** — this repo is **32.1 (Germanium)**, but
`frama-c.com/api/` tracks whatever release is current, which may differ. This is the *same* failure
class as `compiler-libs` / `ppxlib` (see the OCaml skill §30) and exactly why a plugin built against
one kernel can fail to load or misbehave on another — pin the plugin to its Frama-C version. Check the
API of *your* installed Frama-C:
`frama-c -print-share-path`, or the odoc under the `frama-c` opam package, not just the website.

## Plugin anatomy (the tutorial path) — read `references/plugin-anatomy.md`
A plugin is a **dune library** that registers itself with the kernel:
```ocaml
module Self = Plugin.Register (struct
  let name = "Hello"  let shortname = "hello"  let help = "a demo plugin"
end)
module Enabled = Self.False (struct let option_name = "-hello" let help = "run the hello plugin" end)

let run () = Self.result "Hello, world!"          (* logging via the plugin's services *)
let () = Db.Main.extend (fun () -> if Enabled.get () then run ())   (* the entry hook *)
```
`Plugin.Register` gives the plugin its **option** constructors (`Self.False/True/Int/String/…`) and
**logging** (`Self.result/feedback/warning/error/debug/abort/fatal`); the entry runs from
`Db.Main.extend` (newer: `Boot.Main.extend`). dune: `(library (name hello) (libraries frama-c.kernel)
(optional))` + a registration; tests with the **ptests** harness via `dune test`. Cross-plugin calls go through
**`Dynamic`** (dynamic typing). Full detail (options, logging levels, dune, Ptests, Dynamic) in the ref.

## The core module map (`Frama_c_kernel`)
| Area | Modules | Reference |
|---|---|---|
| **The C AST** | `Cil_types` (the AST), `Cil` (helpers/builders), `Cil_datatype`, `Cil_const`, `Cil_builder`, `Ast` (`Ast.get`), `Ast_info`, `Printer` | `references/cil-and-visitor.md` |
| **Traversal/transform** | `Visitor`, `Visitor_behavior`, `Filter`, `Inline`, `Cfg`, `Dominators` | `references/cil-and-visitor.md` |
| **Program structure** | `Globals`, `Kernel_function`, `Loop` | `references/cil-and-visitor.md` |
| **Project & state** | `Project`, `State_builder`, `State`, `State_selection`, `State_dependency_graph`, `Datatype`, `Type` | `references/state-project-datatype.md` |
| **Annotations & properties** | `Annotations`, `Property`, `Property_status`, `Emitter`, `Logic_const`, `Logic_typing`, `Logic_utils`, `Logic_ptree`, `Logic_env` | `references/annotations-and-analyses.md` |
| **Values & locations** | `Locations`, `Cvalue`, `Base`, `Ival`, `Offsetmap`, `Lmap` | `references/annotations-and-analyses.md` |
| **Analyses (plugins)** | `Eva`, `Wp`, `Slicing`, `Pdg`, `Metrics`, … (reach via `Dynamic` or their own libs) | `references/annotations-and-analyses.md` |
| **Plumbing** | `Plugin`, `Log`, `Cmdline`, `Kernel`, `Dynamic` | `references/plugin-anatomy.md` |

> **Soundness caveat when you drive WP / emit a `Valid` `Property_status`.** A WP result obtained
> through `-wp-prover coq` is sound only modulo WP's Coq *realization library* `coqwp`
> (`$(frama-c -print-share-path)/wp/coqwp/`), which is **inlined** into each goal and itself ships
> ~57 `Admitted` lemmas — the TCB of the Coq backend. If your plugin records or relies on such
> statuses for "extreme rigor", that library must be audited/hardened (vendoring, classification,
> `Print Assumptions` + `check.sh`): see the **`frama-c`** skill's `references/coqwp-trust-root.md`.

## WS-mechanism substrate (the macsl `\context` engineering recipes)
Four focused references documenting the kernel-API substrate the macsl mechanism work (new
`\context(\foo)` keywords) needs, each grounded in real `macsl/src/macsl.ml` symbols:
- `references/acsl-extension-registration.md` — add a `\context` keyword: `Logic_builtin.register` +
  `Acsl_extension.register_global ~plugin` + a custom typing context + parse dispatch (ex: `\writing`/`\guarded_by`).
- `references/ghost-counter-injection.md` — visitor recipe to inject a ghost step/branch/alloc counter and assert a bound (substrate for WS5/WS6 `\cost`/`\fuel`/`\resource`).
- `references/self-composition-twin.md` — the synthesised relational twin (`emit_selfcomp`) for noninterference, generalised for WS5 cost-channel NI (+ a ghost counter).
- `references/axiomatic-emission.md` — emit uninterpreted symbols / axiomatic blocks (WS4 hash `H`, WS7 `\flow`, WS1 `\held`/`\stable`) that pass the **no-smuggled-behavioural-axiom** gate.

## Mental model (the four things to internalize)
1. **The AST is CIL** (`Cil_types`) — a *normalized* C AST (sequenced, typed); you almost never touch
   the surface `Cabs`. Get it with `Ast.get ()` (it must be *computed* first).
2. **Everything lives in a Project** — the AST, every analysis result, every plugin option is
   *projectified* state. You don't keep global mutable refs; you declare state with `State_builder`
   functors so it is saved/restored/copied per project and has explicit dependencies.
3. **Traversal is the Visitor** — to read or rewrite the AST, subclass the visitor and return a
   `visitAction`; run it with `Visitor.visitFramacFile*`.
4. **Results are Properties with a status** — analyses emit `Property_status` for `Property.t`s via an
   `Emitter`; that's how WP/Eva/your plugin record "this annotation is Valid/Unknown."

## Reference files
- `references/plugin-anatomy.md` — Plugin.Register, options, logging, the entry hook, dune, Ptests, Dynamic.
- `references/cil-and-visitor.md` — `Cil_types` AST, `Cil`/`Cil_datatype`/`Cil_const`, `Ast`/`Globals`/
  `Kernel_function`, the Visitor framework + `visitAction`, `Printer`.
- `references/state-project-datatype.md` — `Project`, `State_builder` (persistent projectified state),
  `Datatype`/`Type`, state dependencies & selections.
- `references/annotations-and-analyses.md` — `Annotations`, `Property`/`Property_status`/`Emitter`,
  `Logic_const`/`Logic_typing` (build ACSL), `Locations`/`Cvalue`, and calling `Eva`/`Wp`.
- WS-mechanism substrate (macsl `\context` recipes): `references/acsl-extension-registration.md`,
  `references/ghost-counter-injection.md`, `references/self-composition-twin.md`,
  `references/axiomatic-emission.md` (see the subsection above).
- Upstream: **https://frama-c.com/api/** (the kernel API; pin to *your* version) + the
  **plug-in development guide** (`frama-c.com/download/frama-c-plugin-development-guide.pdf`).
- Related skills: **`ocaml`** (the language; functors), **`frama-c`** (ACSL authoring), **`rocq`** (Coq).
