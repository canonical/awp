# Synthesizing the self-composition twin (noninterference, and cost-channel NI)

How to synthesize a **relational twin function** that calls the target twice and asserts a relation
between the two runs — the substrate for noninterference (2-safety) and, with a ghost counter (see
`ghost-counter-injection.md`), WS5 cost-channel NI. Pinned to **32.1 (Germanium)**. The worked example is
macsl's `emit_selfcomp` (macsl.ml L362–426, the "H-I2" twin); this file generalises it so the cost-NI
work can reuse the same skeleton.

## Why self-composition (the 2-safety problem)
Noninterference — "the public output does not depend on the secret input" — is a **hyperproperty over two
executions**, which WP (a one-trace prover) cannot state directly. The standard encoding is
*self-composition*: build a fresh function `f__selfcomp` that runs `f` twice with **public inputs shared**
and **secret inputs distinct**, then assert the two public outputs are equal. That single-trace assert
over the twin is provable by ordinary WP, modularly from `f`'s contract: if the result depends on a
secret, the assert is unprovable — a leak. macsl notes this is "the one genuinely relational property"
(L360–361).

## In-place vs. copy: which builder
macsl's twin is **synthesised, not copied** — it builds a brand-new tiny driver whose body is two `Call`s
to the *existing* `kf` plus an assert, then appends it as a new global. This is the right tool when the
twin only needs to *call* the target (modular reasoning carries the body). Use `Visitor.frama_c_copy
project` (which clones the AST into a fresh project, `cil-and-visitor.md`) only when you must **duplicate
and rename the body inline** — e.g. to inline-compose two renamed copies in one function (full
self-composition without relying on a callee contract). The synthesised-driver pattern below is cheaper
and is what macsl ships.

## The synthesised driver, step by step (from `emit_selfcomp`)
```ocaml
let driver = Cil.emptyFunction (fname ^ "__selfcomp") in          (* fresh fundec *)
Cil.setReturnType driver Cil_const.voidType;
(* split formals: public shared, secret -> _a / _b copies *)
let slots = List.map (fun vi ->
    if is_secret vi then
      let a = Cil.makeFormalVar driver (vi.vname ^ "_a") vi.vtype in
      let b = Cil.makeFormalVar driver (vi.vname ^ "_b") vi.vtype in `Sec (a, b)
    else `Pub (Cil.makeFormalVar driver vi.vname vi.vtype)) formals in
let args first = List.map (function `Pub p -> Cil.evar p
                                  | `Sec (a,b) -> Cil.evar (if first then a else b)) slots in
let ra = Cil.makeLocalVar driver "ra" rettype in
let rb = Cil.makeLocalVar driver "rb" rettype in
let callee = Var (Kernel_function.get_vi kf) in                   (* 32.1: Call callee is an lhost *)
let call first r = Cil.mkStmtOneInstr (Call (Some (Var r, NoOffset), callee, args first, loc)) in
let ret = Cil.mkStmt (Return (None, loc)) in
driver.sbody <- Cil.mkBlock [ call true ra; call false rb; ret ];
Cfg.clearCFGinfo ~clear_id:false driver; Cfg.cfgFun driver;        (* (re)build the CFG *)
Globals.Functions.replace_by_definition (Cil.empty_funspec ()) driver loc;
let dkf = Globals.Functions.get driver.svar in
let f = Ast.get () in f.globals <- f.globals @ [ GFun (driver, loc) ]; Ast.mark_as_grown ();
```
The five load-bearing API facts (all 32.1-specific):
1. **`Cil.emptyFunction name`** seeds a `fundec`; `Cil.makeFormalVar` / `Cil.makeLocalVar` register
   vars in `sformals` / `slocals`. `Cil.setReturnType` sets the signature's return type.
2. **The callee of a `Call` is an `lhost` (`Var vi`), not an `exp`, in 32.1** (L401–402). This is a
   common version trap — older kernels took an `exp`.
3. **Register the new function** with `Globals.Functions.replace_by_definition spec fundec loc`, then
   fetch its `kernel_function` with `Globals.Functions.get driver.svar`.
4. **Splice it into the AST**: append `GFun (driver, loc)` to `f.globals` and call **`Ast.mark_as_grown
   ()`** (the "AST grew a global" signal — distinct from `mark_as_changed`).
5. **Rebuild the CFG** of the synthesised body (`Cfg.clearCFGinfo ~clear_id:false` then `Cfg.cfgFun`)
   or WP/Eva will choke on a driver with no `succs`/`preds`.

Guard first (L366–370): noninterference needs ≥1 formal and a non-void result (`Ast_types.is_void`),
else skip with a warning. Warn on any `p_secret` name that matches no formal (L373–378).

## The relational obligation
macsl asserts the two captured results equal (L416–424):
```ocaml
let tra = Logic_const.tvar (Cil.cvar_to_lvar ra) in
let trb = Logic_const.tvar (Cil.cvar_to_lvar rb) in
let pred = Logic_const.prel (Req, tra, trb) in                    (* ra == rb *)
let annot = Logic_const.(new_code_annotation (AAssert ([], toplevel_predicate ~kind:Assert pred'))) in
Annotations.add_code_annot emitter ~kf:dkf ret annot;             (* on the driver's return stmt *)
```
`Cil.cvar_to_lvar` lifts a C `varinfo` to the logic `logic_var` so it can appear in a term; `prel` takes
a **tuple** `(Req, tra, trb)`. The assert is attached to the driver's `Return` statement via
`Annotations.add_code_annot` with the plugin emitter.

## Generalising for cost-channel NI (WS5) — reuse, don't rewrite
The twin skeleton is relation-agnostic; only the *observable* and the *relation* change:
- **Add a ghost counter to the target** before synthesising the twin (see `ghost-counter-injection.md`):
  inject `__macsl_fuel` into `kf`, `++` at each counted site. After the two calls, the twin holds two
  realised counts.
- **Capture each run's counter.** Either give the target an out-parameter / global ghost counter the
  driver reads, or have the counter be a global reset before each call and snapshotted into a driver
  local `ca` / `cb` right after each `call`.
- **Swap the relation**: instead of `ra == rb`, assert `ca == cb` (timing/step indistinguishability) —
  or conjoin both `pand ((ra==rb),(ca==cb))` for value- *and* cost-channel NI in one obligation.
- Everything else — the public/secret formal split, the synthesised-driver registration, CFG rebuild,
  `mark_as_grown`, the emitter — is **identical to `emit_selfcomp`**. That is the point of factoring it:
  the WS5 mechanism is "`emit_selfcomp` + a ghost counter + a different `prel`."

Keep the relation a plain (in)equality over ghost/return state — no axiomatic predicate — so the
obligation stays definitional and passes the no-smuggled-axiom gate (`axiomatic-emission.md`).
