# Injecting a ghost counter (the substrate under `\cost`/`\fuel`/`\resource`)

How to insert a **ghost step/branch/allocation counter** into a function with the visitor, increment it
at each event site, and assert a bound — the engineering substrate for WS5/WS6 (`\cost`, `\fuel`,
`\resource`). Pinned to **32.1 (Germanium)**. This builds directly on the in-place instrumentation macsl
already does (`writing_visitor`, macsl.ml L437–457) and the `Annotations`/`Logic_const` emission it uses
(`instantiate`, L280–296); the *new* part is a mutable ghost variable threaded through the body.

## Why a ghost variable (not a logic counter)
A `\fuel`/`\cost` bound is a *quantitative* claim over the execution. The robust encoding is a real ghost
C variable that WP tracks like any other state: you `++` it at each branch/call, and the bound is an
ordinary `assert`/`ensures` over that variable. Ghost code is invisible to the program semantics (WP
treats it as spec-only) but visible to the proof. The alternative — a pure-logic counter — would need an
axiomatic definition and risks smuggling a behavioural axiom (see `axiomatic-emission.md`); the ghost
variable keeps the obligation definitional.

## Creating the ghost counter
A function-local ghost variable, initialised to 0 at entry:
```ocaml
let mk_ghost_counter (fd : Cil_types.fundec) loc =
  let vi = Cil.makeLocalVar fd "__macsl_fuel" (Cil.intType) in   (* a normal local… *)
  vi.vghost <- true;                                              (* …flagged ghost (Cil_types.varinfo) *)
  let init = Cil.mkStmtOneInstr ~ghost:true
               (Set (Cil.var vi, Cil.zero ~loc, loc)) in          (* __macsl_fuel = 0; *)
  vi, init
```
- `Cil.makeLocalVar` registers the var in `fd.slocals` for you; set `vi.vghost <- true` so it is ghost.
  (For a *global* counter use `Cil.makeGlobalVar` + `Globals.Vars.add`, and mark the `GVar` ghost.)
- `Cil.intType` / `Cil.zero` / `Cil.var` / `Cil.mkStmtOneInstr` are the standard `Cil` builders (see
  `cil-and-visitor.md`). Pass `~ghost:true` so the instruction is ghost.
- Prepend `init` to the body once, before walking (e.g. `fd.sbody.bstmts <- init :: fd.sbody.bstmts`).

## Injecting the increment at each site — the visitor
Mirror macsl's `writing_visitor`: an in-place visitor over the chosen function, overriding `vstmt_aux`,
that injects a ghost `counter++` at the events you are counting. The cleanest insertion is
`ChangeDoChildrenPost`, replacing a statement with a 2-statement block `{ counter++; <stmt> }`:
```ocaml
class fuel_visitor counter = object (self)
  inherit Visitor.frama_c_inplace
  method private incr loc =
    let v = Cil.var counter in
    Cil.mkStmtOneInstr ~ghost:true
      (Set (v, Cil.increm (Cil.evar ~loc counter) 1, loc))       (* __macsl_fuel = __macsl_fuel + 1; *)
  method! vstmt_aux stmt =
    match stmt.skind with
    | Instr (Call (_,_,_,loc)) ->                                 (* count calls (WS5 cost) … *)
      let blk = Cil.mkBlock [ self#incr loc; { stmt with sid = -1 } ] in
      Cil.ChangeDoChildrenPost (Cil.mkStmt (Block blk), fun s -> s)
    | If (_,_,_,loc) | Loop (_,_,loc,_,_) ->                      (* …or count branches/iterations *)
      let blk = Cil.mkBlock [ self#incr loc; { stmt with sid = -1 } ] in
      Cil.ChangeDoChildrenPost (Cil.mkStmt (Block blk), fun s -> s)
    | _ -> Cil.DoChildren
end
```
Notes:
- **Where to count** is the cost model: `Call` sites for a *call/allocation* budget (`\resource`),
  `If`/`Loop`/`Switch` for a *branch/step* budget (`\fuel`), or every `Instr` for a raw step count
  (`\cost`). For an allocation budget, match `Call` whose callee is `malloc`/`calloc` via the callee
  `lhost` (a `Var vi` with `vi.vname`), exactly as macsl reads the callee in L402.
- `Cil.increm e n` builds `e + n`; or use `Cil.mkBinOp ~loc PlusA (Cil.evar counter) (Cil.one ~loc)`.
- Inside a `Loop`, injecting at the loop *statement* counts iterations only if the increment lands in the
  loop body — prefer injecting on the body's statements (descend) rather than on the `Loop` node, or pair
  the bound with a `loop invariant counter <= …`.
- Run it like macsl's `visit_all` (L539–543): `Visitor.visitFramacFunction (v :> Visitor.frama_c_visitor)
  (Kernel_function.get_definition kf)`. In-place mutation means a following `-wp` sees the result
  (macsl's whole reason for `Ast.apply_after_computed`, L621–623). After structural change call
  `Ast.mark_as_changed ()` and rebuild the CFG (`Cfg.clearCFGinfo ~clear_id:false fd; Cfg.cfgFun fd`, as
  in macsl's self-comp twin L408–409).

## Asserting the bound — `Annotations` + `Logic_const`
Reuse macsl's exact emission idiom (`instantiate`, L280–296 / `emit_ensures`, L298–314). Build the
predicate `counter <= N` with `Logic_const`, wrap it as a code annotation or an ensures, and add it with
the plugin `Emitter`:
```ocaml
let bound_pred counter n loc =
  let tc = Logic_const.tvar (Cil.cvar_to_lvar counter) in        (* the ghost var as a term *)
  Logic_const.prel ~loc (Rle, tc, Logic_const.tinteger ~loc n)   (* counter <= n  (tuple arg!) *)

(* as a checked postcondition (WP must prove; callers don't assume it) — like emit_ensures *)
let emit_fuel_bound emitter kf counter n =
  let p   = bound_pred counter n Cil_datatype.Location.unknown in
  let ip  = Logic_const.new_predicate ~kind:Check p in            (* Check = prove-only, as macsl L311 *)
  Annotations.add_ensures emitter kf [ (Normal, ip) ]
```
- `Logic_const.prel` (and every builder) takes a **tuple** argument (annotations ref §builders) — a
  classic curry mistake.
- `~kind:Check` makes it a *proof obligation only* (macsl uses `Check` for `\postcond`, L311); a plain
  `new_predicate` would be assumed downstream.
- The `Emitter` is the plugin's (`Emitter.create "macsl" … [ Emitter.Code_annot ]`, L269–270 — add
  `Emitter.Funspec`/`Emitter.Property_status` to the capability list if you emit ensures/statuses).

## The shape of the WS5/WS6 obligation
`\fuel(N)` on `f` ⇒ inject `__macsl_fuel`, `++` at each counted site, attach `ensures Check
__macsl_fuel <= N`. WP discharges it from the body and any loop invariants/variants — a function that can
overrun the budget leaves the goal red. For **cost-channel noninterference** (WS5), the counter is the
observable that must be *equal across the two runs* of the self-composition twin — combine this file with
`self-composition-twin.md` (assert `ra == rb` becomes `counter_a == counter_b`).
