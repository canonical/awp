# Frama-C plugin anatomy — registration, options, logging, build, tests

A plugin is an OCaml **dune library** that registers itself with the kernel at load time. (Signatures
below are idiomatic for recent Frama-C; **verify against your installed version's API** — names like
`Db.Main` vs `Boot.Main` and the Eva query API shift between releases.)

## Registration — `Plugin.Register`
```ocaml
module Self = Plugin.Register (struct
  let name = "Hello"           (* long name, shown in help *)
  let shortname = "hello"      (* prefix for this plugin's options/debug keys *)
  let help = "an example plug-in"
end)
```
`Self` now carries this plugin's **option functors** and **logging**. Convention: bind it as `Self`
(or `P`) and route everything through it.

## Command-line options
Each option is a *module* produced by a functor on `Self`:
```ocaml
module Enabled = Self.False (struct          (* a boolean flag, default false -> -hello / -no-hello *)
  let option_name = "-hello"  let help = "run the hello analysis" end)
module Output = Self.String (struct
  let option_name = "-hello-output"  let default = ""  let arg_name = "file"  let help = "…" end)
module Depth = Self.Int (struct
  let option_name = "-hello-depth"  let default = 1  let arg_name = "n"  let help = "…" end)
```
Read with `Enabled.get ()`, `Output.get ()`, …; set/observe with `.set`, `.is_set`, `.add_hook_on_update`.
Each functor returns a `Parameter_sig.{Bool,Int,String,…}` module. **The full set of option functors
(verbatim from `Plugin.General_services`):** `Bool` / `False` / `True`, `Int` / `Zero`, `String` /
`Empty_string`, `Float`, `Filepath`, `String_set` / `String_list` / `Filepath_list`,
`Kernel_function_set` / `Fundec_set`. Input signatures: `False`/`True` need `{ option_name; help }`;
`Int` needs `{ option_name; default; arg_name; help }`; `String` needs `{ option_name; default;
arg_name; help }` (string `default`). `Parameter_customize` (called *before* the functor) tweaks an
option (group, dependencies, `set_negative_option_name`, `argument_may_be_fragment`).

## Logging (never use `Printf`/`stdout` directly)
The plugin's services are `Format`-style and go through the kernel's message machinery:
```ocaml
Self.result  "found %d things" n      (* normal output (gated by verbosity) *)
Self.feedback "starting pass"          (* progress *)
Self.warning "suspicious: %a" Printer.pp_stmt s
Self.error / Self.abort "fatal: %s" msg   (* abort raises and stops the plugin *)
Self.debug ~level:2 "…"   Self.debug ~dkey "…"   (* ~dkey = a registered debug category *)
```
Exact types (from `Log.Messages`, where `'a pretty_printer = ('a, Format.formatter, unit) format -> 'a`):
```ocaml
val result   : ?level:int -> ?dkey:category -> 'a pretty_printer    (* analysis results, default level 1 *)
val feedback : ?ontty:Log.ontty -> ?level:int -> ?dkey:category -> 'a pretty_printer
val debug    : ?level:int -> ?dkey:category -> 'a pretty_printer
val warning  : ?wkey:warn_category -> 'a pretty_printer             (* hypotheses/restrictions *)
val error    : 'a pretty_printer        val failure : 'a pretty_printer   (* user / internal errors *)
val abort    : ('a,'b) pretty_aborter   (* user error -> raises AbortError, stops the plugin *)
val fatal    : ('a,'b) pretty_aborter   (* internal error -> raises AbortFatal *)
val register_category : ?help:string -> ?default:bool -> string -> category
```
Register debug categories with `Self.register_category "phase"`; users enable via `-hello-msg-key`.
Use `~dkey` to scope debug/result output to a category, `~level` for verbosity gating.

## The entry point
Run the plugin from the kernel's main hook (only when enabled):
```ocaml
let run () = if Enabled.get () then Self.result "Hello, world!"
let () = Db.Main.extend run          (* legacy; newer kernels: Boot.Main.extend run *)
```
For analyses that should run on demand / be reusable, also expose a function and **register it
dynamically** (below) rather than only side-effecting from `run`.

## dune build
```lisp
; dune
(library
 (name hello)
 (public_name frama-c-hello.core)
 (flags (:standard -open Frama_c_kernel))   ; so Cil_types/Plugin/… are unqualified
 (libraries frama-c.kernel)
 (optional))                                 ; build only if Frama-C is installed
(plugin (name hello) (libraries frama-c-hello.core) (site (frama-c plugins)))
```
`-open Frama_c_kernel` lets you write `Cil_types.stmt`, `Plugin`, `Visitor`, … directly. Build with
`dune build`; load with `frama-c -load-plugin` or via the installed plugin site.

## Cross-plugin calls — `Dynamic`
Plugins don't depend on each other's libraries; they call through dynamic typing:
```ocaml
(* expose a function from your plugin: *)
let () = Dynamic.register ~plugin:"Hello" "do_it" Datatype.(func unit unit) ~journalize:false run
(* call another plugin (e.g. a value query) — give the exact registered name + Type: *)
let f = Dynamic.get ~plugin:"Eva" "name" Datatype.(func ...) in …
```
`Datatype.(func a b)` builds the dynamic `Type.t` of `a -> b`. Mismatched type/name fails at the call
— this is the seam where a version mismatch bites (the registered name/signature changed).

## Testing — Ptests
Put test inputs under `tests/<suite>/` with a header configuring the run, e.g.:
```c
/* run.config
   OPT: -hello -hello-depth 2
*/
```
`dune test` (which drives the **ptests** harness) runs each file and diffs stdout/stderr against the
saved **oracle** in `tests/<suite>/oracle/`. Update oracles by passing `-update` to ptests
(`dune exec -- frama-c-ptests -update`, the exact target depends on your dune setup). This is the
standard non-regression harness; mirror it for your plugin. (`ptests` is a *separate tool*, not a
`frama-c` kernel flag — there is no `frama-c -ptest`.)
