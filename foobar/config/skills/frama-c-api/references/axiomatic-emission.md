# Emitting axiomatics & uninterpreted logic symbols (the no-smuggled-axiom way)

How to emit an **uninterpreted logic symbol** or an **axiomatic block** from a plugin — the uninterpreted
hash `H` for WS4, the partial-order `\flow(L)` axioms for WS7, the `\held`/`\stable` predicates for WS1 —
via `Logic_const`/`Logic_env`/`Annotations`, **without** smuggling a behavioural axiom past the downstream
gate. Pinned to **32.1 (Germanium)**. macsl's live example is the `\held`/`\stable` builtins (macsl.ml
L94–119); the WS4/WS7 axiomatics are new and follow the same discipline.

## The load-bearing constraint (state it first, it governs everything)
> **The symbol must stay UNINTERPRETED.** The downstream *no-smuggled-behavioural-axiom* gate (Gate B in
> frama-c-monitoring) runs `Print Assumptions` on the Coq backend and **fails if any axiom beyond a
> definitional one appears**. A *definitional* axiom introduces a fresh symbol and at most fixes its
> *signature/type* or *purely-structural* facts (e.g. a partial order's reflexivity/transitivity that
> any model satisfies). A *behavioural* axiom asserts something *about the program's values* — e.g.
> "`H(x) = H(y) ⇒ x = y`" (injectivity), or "`hash of this buffer = 42`". Emitting the latter lets the
> proof assume the very thing it should establish: the obligation becomes **vacuous**. So: declare the
> symbol, give it a type, and **stop**. Let the obligation constrain it; never axiomatise its behaviour.

This is why macsl's concurrency markers are declared with **no profile and no body** (L98–104): `\held`,
`\stable` are uninterpreted predicates, so the obligation is "lock-held-at-access," nothing stronger — no
axiom about what holding a lock *means* is introduced.

## Level 1 — an uninterpreted symbol via `Logic_builtin` (macsl's way)
The lightest weight, and the one to prefer for WS4's hash `H` and WS1's `\held`/`\stable`: register a
profile-less builtin and let the *custom typer* resolve its application (see
`acsl-extension-registration.md` §1, §3). From macsl `register_builtins` (L107–119):
```ocaml
let mk is_pred bl_name =
  { bl_name; bl_labels = []; bl_params = []; bl_profile = [];     (* no profile = uninterpreted, any arity *)
    bl_type = if is_pred then None else Some (Lvar "dummy") } in  (* None: predicate;  Some t: a function/term *)
Logic_builtin.register (mk false "\\hash")                        (* WS4: an uninterpreted term symbol H *)
```
- `bl_type = Some (Lvar t)` makes it a **logic function** (returns a term, e.g. `H : _ -> integer`);
  `bl_type = None` makes it a **predicate** (`\held`, `\stable`). No `bl_profile`/no body ⇒ uninterpreted.
- Guard with `Logic_env.find_all_logic_functions n <> []` for idempotency (re-registration is a hard
  error, L111).
- **This emits zero axioms** — exactly what passes Gate B. The symbol exists only to be *constrained by
  the obligation*, never *defined*. WS4 "two equal hashes came from equal inputs" must be stated as a
  *hypothesis the caller supplies*, not an axiom you emit.

## Level 2 — a proper axiomatic block via `Annotations.add_global_annotation`
When WS7's `\flow(L)` genuinely needs *structural* axioms (a partial order: reflexive, antisymmetric,
transitive), emit a `Daxiomatic` global annotation. Build the `logic_info`/`predicate_info` with
`Logic_const`, the axioms as named predicates, wrap them in `Cil_types.Daxiomatic`, and register:
```ocaml
(* the uninterpreted relation symbol  flows_to : label -> label -> prop *)
let flows_to = (* Logic_const.make_predicate_info / Cil_const … building a predicate_info with a profile *)
  Logic_const.make_predicate_info ~name:"flows_to" ~profile:[ lvL1; lvL2 ] () in
let refl = (* \forall label L; flows_to(L,L) *) Logic_const.pforall (…) in
let trans = (* \forall L1 L2 L3; flows_to(L1,L2) && flows_to(L2,L3) ==> flows_to(L1,L3) *) … in
let body = [ Dfun_or_pred (flows_to, loc);
             Dlemma ("flows_to_refl",  [], [], refl,  [], loc);   (* axioms = Dlemma in an axiomatic *)
             Dlemma ("flows_to_trans", [], [], trans, [], loc) ] in
let ax = Daxiomatic ("Flow", body, [], loc) in
Annotations.add_global_annotation emitter ax
```
- `Annotations.add_global_annotation : Emitter.t -> global_annotation -> unit` inserts the
  `Cil_types.global_annotation` (here `Daxiomatic (name, decls, attrs, loc)`); the emitter is the
  plugin's `Emitter.create` value (macsl L269), with `Emitter.Global_annot` in its capability list.
- The members: `Dfun_or_pred (logic_info, loc)` *declares* the symbol; each `Dlemma` inside the
  axiomatic acts as an **axiom**.
- **Gate-B discipline applies here too.** Only emit axioms that *any* model satisfies (reflexivity,
  antisymmetry, transitivity of a partial order — structural). The moment a lemma mentions a concrete
  program value or asserts injectivity/collision-resistance of `H`, it is behavioural and the gate must
  reject it. Keep `H` declaration-only (Level 1); keep `\flow` axioms order-structural (Level 2).

## Level 3 — a `\predicate`/`\logic` definition (use sparingly)
A *defined* logic function (`Dfun_or_pred` with a body) is a conservative extension — it cannot make a
false goal provable, so it passes Gate B as a *definitional* axiom (the definitional equality is the only
assumption `Print Assumptions` shows). Use this for genuinely *derived* notions (e.g. `\stable(G) ::=
\at(G,Pre) == \at(G,Here)`), **not** for the WS primitives that must stay opaque (`H`, the `\flow`
relation), since a definition would pin their behaviour and re-open the vacuity hole.

## Verifying you stayed honest
The same check the gate runs — make it part of your own loop:
1. `frama-c -wp -wp-prover coq -wp-session …` then in the goal's Coq, `Print Assumptions <goal>.`
2. The output must list **only** the WP realisation axioms + your *definitional/structural* ones —
   **no** axiom that constrains a program value. If an injectivity/collision/concrete-value axiom shows
   up, you smuggled behaviour: demote it to a *hypothesis* of the obligation (a `requires`/twin
   assumption) instead of an emitted axiom.
3. Pair with a **mutation probe** (frama-c-monitoring's non-vacuity gate): break the code; the obligation
   must go red. If it stays green, an axiom is doing the proving — a Gate-B failure by another name.

Summary table:

| WS | Symbol | Emit as | Axioms allowed |
|----|--------|---------|----------------|
| WS4 | hash `H` | Level-1 uninterpreted term (`Logic_builtin`) | **none** (caller supplies equalities as hyps) |
| WS7 | `\flow(L)` order | Level-2 axiomatic (`Daxiomatic`) | structural only (refl/antisym/trans) |
| WS1 | `\held`/`\stable` | Level-1 uninterpreted predicates (macsl L104) | **none** |
