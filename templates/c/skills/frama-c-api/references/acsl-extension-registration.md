# Adding a new `\context(\foo)` ACSL keyword (the macsl recipe)

How to teach the kernel a new ACSL extension keyword — the substrate under every macsl `\context`
(`\writing`, `\reading`, `\guarded_by`, …) and the WS-mechanism `\context`s still to come
(`\cost`/`\fuel`, `\flow`, `\held`/`\stable`). Pinned to **32.1 (Germanium)**; the extension and logic
APIs below are version-volatile — confirm names against *your* kernel's odoc.

The worked example throughout is `macsl/src/macsl.ml` (the `happy` extension). Four moving parts:
**(1)** register builtin logic symbols so the keyword type-checks, **(2)** register the extension itself
with `Acsl_extension.register_global`, **(3)** a *custom typing context* that substitutes the
meta-variables, **(4)** a parse-dispatch over the surface `Logic_ptree` tree.

## 1. Declare the keyword as a logic builtin — `Logic_builtin`
The typer must already know `\writing`, `\written`, `\held`, … as logic symbols before it sees them in a
predicate, or it rejects them. macsl pre-declares two lists (`kw_preds`, `kw_terms`, macsl.ml L94–105)
and registers each as a **profile-less builtin** (`register_builtins`, L107–119):
```ocaml
let mk is_pred bl_name =
  { bl_name; bl_labels = []; bl_params = []; bl_profile = [];     (* Cil_types.logic_info-ish builtin *)
    bl_type = if is_pred then None else Some (Lvar "dummy") }     (* None = predicate; Some _ = term *)
in
List.iter (fun n -> if not (already n) then Logic_builtin.register (mk true n)) kw_preds
```
Load-bearing details:
- **`bl_profile = []` / `bl_labels = []`** — the symbol is *uninterpreted with no fixed arity*; the real
  arity check happens in the custom typer (step 3). This is what keeps `\held`/`\stable` axiom-free
  (see `axiomatic-emission.md` — the no-smuggled-axiom gate).
- **Idempotency** (`already n = Logic_env.find_all_logic_functions n <> []`, L111): re-registering a
  builtin is a *hard error*, so guard with `Logic_env.find_all_logic_functions`. This is what lets macsl
  coexist with a stock MetAcsl that already declared the same names.
- A **predicate** keyword has `bl_type = None`; a **term/meta-variable** keyword has `bl_type = Some _`.

## 2. Register the extension — `Acsl_extension.register_global`
One call wires the keyword into the ACSL parser (macsl.ml L259–263):
```ocaml
let register_parsing () =
  register_builtins ();
  Acsl_extension.register_global ~plugin:"macsl" "happy" process_meta true
```
Signature (32.1): `register_global : ?plugin:string -> string -> typing_fun -> bool -> unit`, where the
`string` is the **keyword that introduces the annotation** (`happy …;` at global scope), `typing_fun`
is your parse+type dispatch (step 4), and the trailing `bool` is the *is_loop_independent / cacheable*
flag. The `~plugin` label namespaces the keyword so two plugins don't collide — macsl deliberately
owns `happy` and does **not** squat MetAcsl's `meta` (L261–262), so both can load together.

Other registrars in the same module, by where the annotation appears: `register_behavior` (inside a
behavior), `register_code_annot` / `register_code_annot_next_stmt` (statement-level), `register_global`
(global, as here). Pick the one matching where `\context(\foo)` is written.

## 3. The custom typing context — meta-variable substitution
This is the heart of an extension that introduces *its own* keywords inside a predicate. The kernel hands
your typing function a `Logic_typing.typing_context` record; you build a **derived** context that
overrides `type_predicate` and `type_term`, then type the body through it (macsl `type_with_assoc`,
L156–166):
```ocaml
let meta_tc =
  { typing_context with
    type_predicate = meta_type_predicate typing_context;        (* intercept \writing/\held/… *)
    type_term      = meta_type_term termassoc typing_context }  (* intercept \written/\read/… *)
in
let env = Logic_typing.append_here_label meta_tc.pre_state in   (* make Here/Pre/Old/Post visible *)
let env = Logic_typing.append_pre_label env in
let env = Logic_typing.append_old_and_post_labels env in
meta_tc.type_predicate meta_tc env expr
```
- **Predicate override** (`meta_type_predicate`, L125–131): when the head symbol is one of `kw_preds`,
  type the arguments through the *meta* context and rebuild the application with `Logic_const.papp`
  against the builtin `logic_info` looked up by `Logic_env.find_all_logic_functions`. Otherwise delegate
  to `orig_ctxt.type_predicate` — so ordinary ACSL still type-checks normally.
- **Term override** (`meta_type_term termassoc`, L133–154): a meta-variable like `\written` is *not* a
  real term — it is a placeholder *replaced* per instrumentation site. The override looks the symbol up
  in `termassoc` (an association list `(string * replaced_kind)`) and returns the bound term, or calls
  `meta_ctxt.error loc "…"` if the keyword is used in the wrong context (e.g. `\written` inside a
  `\reading` policy). `replaced_kind` is either `RepVariable of term` (no argument: `\written`) or
  `RepApp of (string*term) list` (argument-indexed: `\written(field)`).
- **Delayed typing** (`delay_prop`, L170–181): macsl stores the predicate *untyped* and re-types it once
  per site, because the meta-variables differ per site. It also extends `find_var` so a bare identifier
  resolves against globals/functions (`Globals.Vars.find_from_astinfo`, `Globals.Functions.find_by_name`)
  — i.e. the policy body can name program globals. The `p_property` field is therefore a *closure*
  `Kernel_function.t -> (string*replaced_kind) list -> predicate` (L81).

## 4. Parse dispatch over `Logic_ptree`
The `typing_fun` you registered receives the raw surface tree (`Logic_ptree.lexpr` list). macsl's
`process_meta` (L250–257) dispatches on the leading command, then `process_property` (L204–248)
destructures `\name(..) \targets(..) \context(..) P` positionally:
```ocaml
let p_context = match econtext.lexpr_node with
  | PLvar "\\writing"    -> Writing
  | PLvar "\\guarded_by" -> Guarded_by         (* the new keyword: one match arm *)
  | PLvar "\\stable_check" -> Stable_check
  | _ -> tc.error econtext.lexpr_loc "macsl supports \\context(\\writing | … | \\guarded_by | …)"
```
The typing function must **return an `Ext_terms`/`Ext_preds` payload** (here
`Ext_terms [ Logic_const.tstring ~loc p_name ]`, L245) — the residual the annotation prints back as. The
real policy is squirrelled into a side ref (`gathered`, L87/L243) for the later instrumentation pass; the
parser's job is only to validate and record.

### Adding `\context(\guarded_by)` end-to-end — the checklist
1. Add the predicate keyword(s) it needs to `kw_preds` (macsl added `\held`, `\stable`, L104) — they
   register as profile-less, uninterpreted builtins automatically.
2. Add a constructor to the `context` type (`Guarded_by | Stable_check`, L66).
3. Add a `PLvar "\\guarded_by"` arm to the `\context` match in `process_property` (L218–219).
4. Decide where the obligation is emitted and wire `run_policy` (L545+) to it — `\guarded_by` reuses the
   `writing_visitor` walk and injects `\held(L)` at each write site (L570–572). See
   `ghost-counter-injection.md` / `self-composition-twin.md` for the emission mechanics.

That is the whole loop: **builtin → register_global → custom typer → parse dispatch → emission**. No new
parser grammar, no kernel patch — the extension API does the rest.
