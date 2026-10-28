# The CIL AST (`Cil_types`) and the Visitor framework

Frama-C analyzes a **normalized** C AST called **CIL** — not the surface syntax. The front-end
(`Cabs` → `Cabs2cil`) lowers C into a sequenced, fully-typed form: every expression is side-effect-free,
calls/assignments are `instr`s, loops are a single `Loop`, etc. You work on this CIL AST.

## Getting the AST
```ocaml
let f : Cil_types.file = Ast.get ()        (* the whole program; computes it if needed *)
Globals.Functions.iter (fun kf -> …)        (* iterate functions *)
let kf = Globals.Functions.find_by_name "main"
Globals.Vars.iter (fun vi init -> …)        (* global variables *)
```
`Ast.compute ()` forces the AST; `Ast.self` is its state (depend on it; see state ref).

## `Cil_types` — the core AST (the types you match on)
Verbatim from the API (`loc` = a source-position pair; see the version note after the block):
```ocaml
type file   = { mutable fileName : Filepath.t; mutable globals : global list;
                mutable globinit : fundec option; mutable globinitcalled : bool }
and global  = GType of typeinfo * loc | GCompTag of compinfo * loc | GCompTagDecl of compinfo * loc
            | GEnumTag of enuminfo * loc | GEnumTagDecl of enuminfo * loc
            | GVarDecl of varinfo * loc | GFunDecl of funspec * varinfo * loc
            | GVar of varinfo * initinfo * loc | GFun of fundec * loc
            | GAsm of string * loc | GPragma of attribute * loc | GText of string
            | GAnnot of global_annotation * loc
and fundec  = { mutable svar : varinfo; mutable sformals : varinfo list;
                mutable slocals : varinfo list; mutable sbody : block;
                mutable sallstmts : stmt list; mutable sspec : funspec; mutable smaxid : int; … }
and varinfo = { mutable vname : string; vorig_name : string; mutable vtype : typ;
                mutable vattr : attributes; mutable vstorage : storage; mutable vglob : bool;
                mutable vdefined : bool; mutable vformal : bool; mutable vdecl : loc;
                mutable vid : int; mutable vaddrof : bool; vtemp : bool; mutable vghost : bool;
                mutable vlogic_var_assoc : logic_var option; … }      (* the UNIQUE decl; compare vid *)
and stmt    = { mutable labels : label list; mutable skind : stmtkind; mutable sid : int;
                mutable succs : stmt list; mutable preds : stmt list;
                mutable ghost : bool; mutable sattr : attributes }
and stmtkind = Instr of instr | Return of exp option * loc | Goto of stmt ref * loc
             | Break of loc | Continue of loc | If of exp * block * block * loc
             | Switch of exp * block * stmt list * loc
             | Loop of code_annotation list * block * loc * stmt option * stmt option
             | Block of block
             | UnspecifiedSequence of (stmt * lval list * lval list * lval list * stmt ref list) list
             | Throw of (exp * typ) option * loc | TryCatch of block * (catch_binder * block) list * loc
             | TryFinally of block * block * loc | TryExcept of block * instr list * exp * block * loc
and instr   = Set of lval * exp * loc | Call of lval option * exp * exp list * loc
            | Local_init of varinfo * local_init * loc
            | Asm of attributes * string list * extended_asm option * loc
            | Skip of loc | Code_annot of code_annotation * loc
and exp     = { eid : int; enode : exp_node; eloc : loc }        (* expressions are PURE *)
and exp_node = Const of constant | Lval of lval | SizeOf of typ | SizeOfE of exp
             | AlignOf of typ * standard_or_gcc | AlignOfE of exp * standard_or_gcc
             | UnOp of unop * exp * typ | BinOp of binop * exp * exp * typ
             | CastE of typ * exp | AddrOf of lval | StartOf of lval     (* NB: no SizeOfStr/Info *)
and lval    = lhost * offset    and lhost = Var of varinfo | Mem of exp
and offset  = NoOffset | Field of fieldinfo * offset | Index of exp * offset
```
Key invariants: a `varinfo` is the **unique** identity of a declaration (compare by `vid`, never
structurally); a `stmt` has a unique `sid` and pre-computed `succs`/`preds` (the CFG); every `exp` is
**side-effect-free** (effects live in `instr`s).

**⚠ Version difference (this is the caveat made concrete).** The block above is verbatim from
`frama-c.com/api/`, which tracks a **newer** Frama-C than this repo's **32.1 (Germanium)**. Confirmed
diffs to check against *your* kernel's odoc:
- **`typ`** — the web API has refactored it into a **record** `type typ = { tnode : typ_node; … }` with
  a flat `type typ_node = TVoid | TInt of ikind | TFloat of fkind | TPtr of typ | TArray of typ * exp
  option | TFun of typ * (string*typ*attributes) list option * bool | TNamed of typeinfo | TComp of
  compinfo | TEnum of enuminfo | TBuiltin_va_list`. In **32.1** `typ` is *flat with per-constructor
  attributes*: `TVoid of attributes | TInt of ikind * attributes | TPtr of typ * attributes | …`.
- **locations** render as `Fileloc.t` in the web API; in 32.1 the field type is `location =
  Filepath.position * Filepath.position` (= `Cil_datatype.Location.t`).
The constructor *names* of `global`/`stmtkind`/`instr`/`exp_node`/`lhost`/`offset` are stable across
both — only `typ` and the location field type differ.

## `Cil`, `Cil_const`, `Cil_datatype`, `Cil_builder`
- **`Cil`** — the manipulation API: builders (`Cil.mkStmt`, `Cil.mkBlock`, `Cil.mkBinOp`,
  `Cil.var vi`, `Cil.integer ~loc n`, `Cil.zero`), queries (`Cil.typeOf exp`, `Cil.typeOfLval`,
  `Cil.isPointerType`, `Cil.constFold`), and `Cil.dummyStmt`. The default location is `Cil_datatype.Location.unknown`.
- **`Cil_const`** — constructors for constants / standard types.
- **`Cil_datatype`** — `Datatype.S` instances for every AST type (`Cil_datatype.Stmt`,
  `Varinfo`, `Exp`, `Lval`, `Typ`, `Location`, `Kf`, …) → use their `.equal/.compare/.hash/.pretty`
  and build `Cil_datatype.Stmt.Hashtbl`/`Set`/`Map`. **Never** structurally `=` AST nodes — use these.
- **`Cil_builder`** — a higher-level, typed DSL for *constructing* CIL (newer; for code generation).
- **`Printer`** — pretty-printers: `Printer.pp_stmt`, `pp_exp`, `pp_lval`, `pp_typ`, `pp_varinfo`,
  `pp_location` — use with `%a` (`Self.result "%a" Printer.pp_stmt s`).

## `Kernel_function` & `Globals` (verbatim)
```ocaml
(* Kernel_function (type t = Cil_types.kernel_function): *)
val get_name : t -> string   val get_id : t -> int   val get_vi : t -> varinfo
val get_type : t -> typ   val get_return_type : t -> typ   val get_location : t -> location
val get_global : t -> global   val get_formals : t -> varinfo list   val get_locals : t -> varinfo list
exception No_Definition
val get_definition : t -> fundec        (* raises No_Definition if it is only a declaration *)
val is_definition : t -> bool   val has_definition : t -> bool
val find_first_stmt : t -> stmt   val find_return : t -> stmt    (* NB: find_return, not get_return_stmt *)
val find_englobing_kf : stmt -> t       (* the function containing a statement *)
```
**There is no `Kernel_function.get_spec`** — read the contract via `Annotations.funspec kf`.
```ocaml
(* Globals — top-level (verbatim): *)
exception No_such_entry_point of string
val entry_point : unit -> kernel_function * bool          (* the program's main *)
(* submodules: Vars, Functions, FileIndex, Syntactic_search, Types — conventional sigs: *)
Globals.Functions.iter : (kernel_function -> unit) -> unit          (* + fold *)
Globals.Functions.get : varinfo -> kernel_function
Globals.Functions.find_by_name : string -> kernel_function          (* raises Not_found *)
Globals.Vars.iter : (varinfo -> initinfo -> unit) -> unit           (* + find : varinfo -> initinfo *)
```

## The Visitor framework (`Visitor`, `visitAction` from `Cil`)
Subclass the Frama-C visitor (project-aware — it tracks the source/target project) and override the
node methods; each returns a **`visitAction`** (defined in `Cil`, verbatim):
```ocaml
type 'a visitAction =
  | SkipChildren                              (* keep node, don't descend *)
  | DoChildren                                (* keep node, descend (the usual default) *)
  | DoChildrenPost of ('a -> 'a)             (* descend, then post-process the rebuilt node *)
  | JustCopy                                  (* copy mode: copy node, descend *)
  | JustCopyPost of ('a -> 'a)
  | ChangeTo of 'a                            (* replace node, do NOT descend *)
  | ChangeToPost of 'a * ('a -> 'a)
  | ChangeDoChildrenPost of 'a * ('a -> 'a)   (* replace, descend into the replacement, then post *)
```
**Frama-C visitor classes (`Visitor`):** class type **`frama_c_visitor`**; ready-made:
`frama_c_inplace : frama_c_visitor` (mutate the current project), `frama_c_copy : Project.t ->
frama_c_visitor` (build into a fresh project), `frama_c_refresh : Project.t -> frama_c_visitor` (copy +
fresh ids), `generic_frama_c_visitor : Visitor_behavior.t -> frama_c_visitor` (abstracts inplace/copy).
```ocaml
class my_visitor = object (self)
  inherit Visitor.frama_c_inplace
  method! vstmt_aux s =                        (* override the _aux variant (see rule below); `!` = override *)
    (match s.skind with If _ -> Self.result "if at %a" Printer.pp_location (Cil_datatype.Stmt.loc s)
                      | _ -> ());
    Cil.DoChildren
  method! vexpr _e = Cil.DoChildren
  method! vlval _lv = Cil.DoChildren
end
let () = Visitor.visitFramacFileSameGlobals (new my_visitor :> Visitor.frama_c_visitor) (Ast.get ())
```
- **Override the `_aux` methods, NOT their plain forms.** The `Visitor` docs are explicit: the
  Frama-C-specific *auxiliary* methods may be redefined, but the base `Cil.cilVisitor` methods "must
  retain their values as defined here" (they do annotation bookkeeping). So override **`vstmt_aux`**,
  **`vglob_aux`**, **`vfunc`** — not `vstmt`/`vglob`. Other overridable methods (from `Cil.cilVisitor`):
  `vfile`, `vinst`, `vexpr`, `vlval`, `voffs`, `vinitoffs`, `vvrbl` (var use) / `vvdec` (var decl),
  `vtype`, `vattr`, `vinit`, and the ACSL ones `vspec`, `vbehavior`, `vcode_annot`, `vpredicate`,
  `vterm`, `vlogic_type`.
- **Entry functions (`Visitor`)** — exact signatures:
  ```ocaml
  val visitFramacFile            : frama_c_visitor -> file -> unit       (* globals may change *)
  val visitFramacFileSameGlobals : frama_c_visitor -> file -> unit       (* global *list* preserved *)
  val visitFramacFileCopy        : frama_c_visitor -> file -> file
  val visitFramacGlobal          : frama_c_visitor -> global -> global list
  val visitFramacKf              : frama_c_visitor -> Kernel_function.t -> Kernel_function.t
  val visitFramacFunction        : frama_c_visitor -> fundec -> fundec
  val visitFramacStmt            : frama_c_visitor -> stmt -> stmt
  val visitFramacExpr            : frama_c_visitor -> exp -> exp
  val visitFramacLval            : frama_c_visitor -> lval -> lval
  val visitFramacCodeAnnotation  : frama_c_visitor -> code_annotation -> code_annotation
  val visitFramacPredicate       : frama_c_visitor -> predicate -> predicate
  val visitFramacTerm            : frama_c_visitor -> term -> term
  ```
- **In-place vs copy:** `frama_c_inplace` mutates the current AST; `frama_c_copy project` produces the
  transformed AST in a *new* project (the sound way to transform while keeping the original);
  `Visitor_behavior` controls the copy's sharing/renaming/id policy.
- After a structural change you may need `Ast.mark_as_changed` (and to rebuild the CFG).
