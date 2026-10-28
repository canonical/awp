# OCaml toolchain & standard library (manual Part III–IV)

> **In the OCaml manual (Part III):** `ocamlc`, `ocamlopt`, the `ocaml` toplevel, `ocamlrun`,
> `ocamllex`/`ocamlyacc`, `ocamldep`, `ocamldoc`, `ocamldebug`, profiling, the C interface, Flambda.
> **Community tools (NOT in the manual, documented separately):** **opam**, **dune**, **Merlin** /
> ocaml-lsp, **ocamlformat**, **menhir**, **odoc**, **utop**. Both are listed below; the verbatim
> details are taken from the 5.4 manual for the in-manual tools.

## opam — packages & compiler switches
```sh
opam switch create 5.4.0           # a sandboxed install of a compiler + packages
opam switch list ; opam switch 5.4.0
eval $(opam env)                   # put THIS switch's tools on PATH (per shell)
opam install dune utop merlin ocaml-lsp-server odoc
opam install <lib> ; opam list ; opam show <lib>
```
A **switch** is an isolated `(compiler, package set)` — the OCaml analogue of a venv. Always
`eval $(opam env)` (or use `--switch`) before building. (This repo's Frama-C work uses the
`framac-coq8` switch the same way.)

- **Install order can matter when a package has a *conditional* build step keyed on an optional
  dependency.** opam resolves a dependency *set*, but a package whose build emits extra artifacts
  only if another package is already present must be installed **after** it. Verified case: `why3`
  builds its Coq realization libraries (`$(why3 --print-libdir)/coq/*.vo`) **only if `coq` is
  already in the switch** — so `opam install coq.8.20.1` **then** `opam install why3`, not both in
  one resolve (which may build `why3` first and silently skip the realizations). If you got the
  order wrong, `opam reinstall why3` after Coq is present. Check the artifact, not just exit code
  (`test -f "$(why3 --print-libdir)/coq/BuiltIn.vo"`). The general lesson: for an optional-feature
  build step, pin the order explicitly and verify the produced files exist.

## dune — the build system
Minimal project:
```
myproj/
  dune-project          (lang dune 3.0)
  bin/   dune  main.ml
  lib/   dune  foo.ml foo.mli
  test/  dune  test_foo.ml
```
```lisp
; dune-project
(lang dune 3.16)
; lib/dune
(library (name foo) (public_name myproj) (libraries str unix)
         (preprocess (pps ppx_deriving.std)))
; bin/dune
(executable (name main) (libraries foo))
; test/dune
(test (name test_foo) (libraries foo alcotest))
```
- `dune build` (whole project), `dune exec bin/main.exe -- args`, `dune runtest`, `dune utop lib`,
  `dune build @doc` (odoc), `dune fmt` (ocamlformat). `_build/` holds outputs; never edit it.
- A `(library (name foo))` with `foo.ml` is module `Foo`; multiple files become submodules under a
  generated `Foo` wrapper. Public API via `.mli` (see `modules-and-functors.md`).

## The compilers (§13 ocamlc, §16 ocamlopt)
- **`ocamlc`** → bytecode; **`ocamlopt`** → native (faster). dune drives both; you rarely call them
  directly. Key flags (same for both): **`-c`** compile only (no link), **`-o file`** output name,
  **`-I dir`** add `dir` to the `.cmi` search path, **`-a`** build a library, **`-w <list>`**
  enable/disable/fatal warnings, **`-warn-error <list>`** make warnings fatal.
- **File kinds (exact):**
  | ext | what | producer |
  |---|---|---|
  | `.mli` | interface source — "specifies the names exported by a compilation unit" | you |
  | `.ml` | implementation source | you |
  | **`.cmi`** | **compiled interface** — from `.mli`; *if no `.mli`, compiling `.ml` produces a `.cmi` too* | ocamlc/ocamlopt |
  | `.cmo` / `.cma` | bytecode object / library (`-a` packs `.cmo`s into a `.cma`) | ocamlc |
  | `.cmx` (+`.o`) / `.cmxa` | native object / library | ocamlopt |
  | `.cmt` / `.cmti` | typed AST of `.ml` / `.mli` (for Merlin, odoc) | with `-bin-annot` |
  | `.c`→`.o`, `.o`/`.a`, `.so`/`.dll` | C source → object; C objects/libs; C shared libs | C compiler |

## The toplevel / REPL (§14)
`ocaml` is the REPL; **`utop`** (community) is the nicer front-end. A phrase is terminated by **`;;`**.
**Built-in directives** (manual §14): `#help`, `#quit`, `#cd "d"`, `#directory "d"` /
`#remove_directory "d"`, `#load "f.cmo"` / `#load_rec`, `#use "f.ml"` (read+compile+run a file) /
`#use_output "cmd"` / `#mod_use "f.ml"`, `#show ident` (and `#show_val`/`#show_type`/`#show_module`/
`#show_module_type`/`#show_exception`/`#show_class`), `#install_printer` / `#remove_printer` /
`#print_depth n` / `#print_length n`, `#trace f` / `#untrace f` / `#untrace_all`, `#ppx "f"`,
`#warnings "..."` / `#warn_error "..."`, `#rectypes`, `#principal b`, `#labels b`, `#debug b`.
**`#require "pkg"` and `#list` are NOT built-in** — they come from **findlib/topfind** (load it with
`#use "topfind";;`; `utop` and `dune utop` preload it). Don't attribute them to the core toplevel.

## Tooling
- **Merlin** + **ocaml-lsp-server** — editor type-on-hover, completion, jump-to-def, errors.
- **ocamlformat** (`dune fmt`) — autoformatter (config `.ocamlformat`).
- **ocamllex** (`.mll`) + **ocamlyacc**/**menhir** (`.mly`) — lexer/parser generators (menhir is the
  modern, better-error LR generator; dune `(menhir (modules parser))`).
- **odoc** / **ocamldoc** (§19) — HTML docs from `(** … *)` comments.
- **ocamldebug** (§20) — time-travel debugger for *bytecode* (`dune exec --` then `ocamldebug`); native
  debugging via `gdb`/`perf`.
- **Profiling** (§21): `perf` for native; `ocamlprof`; allocation/GC via `Gc.stat`/`statmemprof`.
- **C interface / FFI** (§22): declare **`external name : type = "c_fn"`** (arity = the number of
  arrows in `type`; abbreviations are *not* expanded; for arity > 5 give two names
  `"bytecode_fn" "native_fn"`). The C stub's **GC contract is mandatory**: open with `CAMLparam0..5`
  (`CAMLxparam*` / `CAMLparamN` for >5 `value` args), declare every local `value` with
  `CAMLlocal1..5` / `CAMLlocalN` **after** `CAMLparam` and **before** any allocation, and exit through
  `CAMLreturn(v)` / `CAMLreturn0` / `CAMLreturnT(t,x)` at **every** return point. Convert with
  `Int_val`/`Val_int`, `Long_val`/`Val_long`, `Bool_val`/`Val_bool`, `Val_unit`, `Val_emptylist`,
  `String_val`/`caml_copy_string`, `Double_val`/`caml_copy_double`; read a field with `Field(v,n)` and
  **write through `Store_field(b,n,v)`** (direct `Field(v,n) = w` is safe only immediately after
  `caml_alloc_small`); allocate with `caml_alloc(n,tag)` / `caml_alloc_tuple(n)` / `caml_alloc_string(n)`;
  register global `value`s with `caml_register_global_root(&v)` / `caml_remove_global_root(&v)`
  (globals holding only ints need no root). dune: `(foreign_stubs (language c) (names mystubs))`.
- **Flambda** (§23) — aggressive inliner/optimizer (a switch variant, `+flambda`).

## The libraries (Part IV, §28–35) → `libraries.md`
The shipped libraries — §28 core vs §29 standard library, §30 the **compiler-libs** front-end (+ its
instability caveat), §31 `unix`, §32 `str` (vs `re`), §33 `runtime_events`, §34 `threads`, §35
`dynlink` (how plugins load) — are covered in **`libraries.md`**. Day to day: `Stdlib` is
auto-opened (§28); reach for `List`/`Array`/`String`/`Map.Make`/`Hashtbl`/`Seq`/`Option`/`Result` and
**`Format`** (the `%a` box-based pretty-printer) from the standard library (§29). Removed/moved (§36):
`Graphics`, `Bigarray` (now built-in), `Num` (→ opam `zarith`), `LablTk` — historical.

## A first build, end to end
```sh
opam switch create myproj 5.4.0 && eval $(opam env)
opam install dune
mkdir -p myproj/bin && cd myproj
printf '(lang dune 3.16)\n' > dune-project
printf '(executable (name main))\n' > bin/dune
printf 'let () = Printf.printf "hello %s\\n" Sys.argv.(0)\n' > bin/main.ml
dune exec bin/main.exe
```
