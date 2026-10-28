# OCaml libraries — manual Part IV (§28–35)

The libraries shipped with the compiler. **§28–29** are always available (linked into every program);
**§30–35** are separate libraries you must link (`dune` `(libraries …)`). For exhaustive per-module
signatures, the manual's API pages are the authority — this is the map + the load-bearing caveats.

## §28 The core library — what's *always* there
> "declarations for built-in types and exceptions, plus the module `Stdlib`."

The core library is the minimal foundation that is **automatically linked** with your object code and
**automatically opened** at compile time / in the toplevel. It is just the **built-in types &
exceptions** + the **`Stdlib`** module (the old `Pervasives`, renamed; an alias still exists). So
`compare`, `( + )`, `( |> )`, `( @@ )`, `ref`/`!`/`:=`, `raise`/`failwith`/`invalid_arg`, `print_string`,
`stdin`/`stdout`/`stderr`, `min`/`max`, `ignore`, `fst`/`snd`, `@`, `^`, … are in scope with no `open`.
You may shadow names from it; `Stdlib.foo` always reaches the original.

## §29 The standard library — the broader module set
A larger collection of modules, all reachable as `Module.f` (and also under `Stdlib.Module`).
Categories: **containers** `List Array String Bytes Char Hashtbl Map(.Make) Set(.Make) Queue Stack
Buffer Seq Lazy Bool Option Result Either Fun`; **numbers** `Int Float Int32 Int64 Nativeint Complex
Random`; **I/O & formatting** `Printf Scanf Format In_channel Out_channel Filename Marshal Digest`;
**runtime & concurrency** `Sys Gc Printexc Atomic Domain Mutex Condition Semaphore Effect` (multicore
set — see `concurrency-and-effects-5x.md`). Convention: most follow the `t` convention with
`compare`/`equal`/`hash`/`pp`, so they satisfy `Map.Make`/`Set.Make`/`Hashtbl.Make` out of the box.
Verbatim signatures of the workhorses (5.4 API):

### `List` — *"List operations."* (some functions are NOT tail-recursive — flagged below)
```ocaml
val length : 'a list -> int          val rev : 'a list -> 'a list
val hd : 'a list -> 'a    val tl : 'a list -> 'a list           (* both raise Failure on [] *)
val nth : 'a list -> int -> 'a       val nth_opt : 'a list -> int -> 'a option
val ( @ ) : 'a list -> 'a list -> 'a list   (* = append; tail-recursive since 5.1 *)
val concat : 'a list list -> 'a list        (* NOT tail-recursive *)
val iter : ('a -> unit) -> 'a list -> unit            val iteri : (int -> 'a -> unit) -> 'a list -> unit
val map : ('a -> 'b) -> 'a list -> 'b list            val mapi : (int -> 'a -> 'b) -> 'a list -> 'b list
val filter : ('a -> bool) -> 'a list -> 'a list       val filter_map : ('a -> 'b option) -> 'a list -> 'b list
val concat_map : ('a -> 'b list) -> 'a list -> 'b list   (* tail-recursive *)
val fold_left : ('acc -> 'a -> 'acc) -> 'acc -> 'a list -> 'acc
val fold_right : ('a -> 'acc -> 'acc) -> 'a list -> 'acc -> 'acc   (* NOT tail-recursive *)
val for_all : ('a -> bool) -> 'a list -> bool         val exists : ('a -> bool) -> 'a list -> bool
val mem : 'a -> 'a list -> bool      val memq : 'a -> 'a list -> bool   (* memq = physical (==) *)
val find : ('a -> bool) -> 'a list -> 'a              (* raises Not_found *)
val find_opt : ('a -> bool) -> 'a list -> 'a option   val find_map : ('a -> 'b option) -> 'a list -> 'b option
val partition : ('a -> bool) -> 'a list -> 'a list * 'a list
val assoc : 'a -> ('a * 'b) list -> 'b   (* raises Not_found *)   val assoc_opt : 'a -> ('a * 'b) list -> 'b option
val split : ('a*'b) list -> 'a list * 'b list   val combine : 'a list -> 'b list -> ('a*'b) list  (* both NOT tail-rec *)
val sort : ('a -> 'a -> int) -> 'a list -> 'a list    val sort_uniq : ('a -> 'a -> int) -> 'a list -> 'a list
val init : int -> (int -> 'a) -> 'a list   val to_seq : 'a list -> 'a Seq.t   val of_seq : 'a Seq.t -> 'a list
```

### `Array` — mutable; `a.(i)` ≡ `Array.get a i`, `a.(i) <- v` ≡ `Array.set a i v` (both raise `Invalid_argument` out of range)
```ocaml
val length : 'a array -> int    val get : 'a array -> int -> 'a    val set : 'a array -> int -> 'a -> unit
val make : int -> 'a -> 'a array    val init : int -> (int -> 'a) -> 'a array
val make_matrix : int -> int -> 'a -> 'a array array    val append : 'a array -> 'a array -> 'a array
val sub : 'a array -> int -> int -> 'a array    val copy : 'a array -> 'a array
val fill : 'a array -> int -> int -> 'a -> unit    val blit : 'a array -> int -> 'a array -> int -> int -> unit
val to_list : 'a array -> 'a list    val of_list : 'a list -> 'a array
val iter / iteri / map / mapi / fold_left / fold_right / exists / for_all / mem    (* like List *)
val sort : ('a -> 'a -> int) -> 'a array -> unit   (* in place *)    val stable_sort : … -> unit
```

### `String` — *"immutable sequence of n bytes"* (since 4.02; mutable twin is `Bytes`)
```ocaml
val length : string -> int    val get : string -> int -> char      (* s.[i] sugar *)
val ( ^ ) : string -> string -> string    val concat : string -> string list -> string
val sub : string -> int -> int -> string    val make : int -> char -> string    val init : int -> (int -> char) -> string
val equal : string -> string -> bool    val compare : string -> string -> int
val index_opt : string -> char -> int option    val rindex_opt : string -> char -> int option   (* index/rindex raise Not_found *)
val contains : string -> char -> bool    val split_on_char : char -> string -> string list    val trim : string -> string
val starts_with : prefix:string -> string -> bool    val ends_with : suffix:string -> string -> bool
val map : (char -> char) -> string -> string    val uppercase_ascii / lowercase_ascii : string -> string
val to_seq : string -> char Seq.t    val of_seq : char Seq.t -> string
```

### `Map.Make` / `Set.Make` — functorial immutable balanced trees
```ocaml
module type OrderedType = sig type t  val compare : t -> t -> int end
module Make (Ord : OrderedType) : S with type key = Ord.t
(* the resulting Map.S: *)
type key    type +'a t
val empty : 'a t    val is_empty : 'a t -> bool    val mem : key -> 'a t -> bool
val add : key -> 'a -> 'a t -> 'a t    val singleton : key -> 'a -> 'a t    val remove : key -> 'a t -> 'a t
val update : key -> ('a option -> 'a option) -> 'a t -> 'a t
val find : key -> 'a t -> 'a          (* raises Not_found *)    val find_opt : key -> 'a t -> 'a option
val cardinal : 'a t -> int    val bindings : 'a t -> (key * 'a) list
val iter : (key -> 'a -> unit) -> 'a t -> unit    val fold : (key -> 'a -> 'acc -> 'acc) -> 'a t -> 'acc -> 'acc
val map : ('a -> 'b) -> 'a t -> 'b t    val mapi : (key -> 'a -> 'b) -> 'a t -> 'b t
val filter : (key -> 'a -> bool) -> 'a t -> 'a t    val merge : (key -> 'a option -> 'b option -> 'c option) -> 'a t -> 'b t -> 'c t
val to_seq : 'a t -> (key * 'a) Seq.t    val of_seq : (key * 'a) Seq.t -> 'a t
```
(`Set.Make` is analogous over elements; `Hashtbl.Make` over a `HashedType = sig type t val equal … val hash … end`.)

### `Hashtbl` — *"hashed association tables, with in-place modification"* (imperative)
```ocaml
type ('a, 'b) t
val create : ?random:bool -> int -> ('a, 'b) t    val length : ('a,'b) t -> int
val add : ('a,'b) t -> 'a -> 'b -> unit       (* adds a binding; previous bindings HIDDEN, not removed *)
val replace : ('a,'b) t -> 'a -> 'b -> unit   (* OVERWRITES the current binding (or adds) *)
val find : ('a,'b) t -> 'a -> 'b              (* raises Not_found; returns the MOST RECENT binding *)
val find_opt : ('a,'b) t -> 'a -> 'b option   val find_all : ('a,'b) t -> 'a -> 'b list
val mem : ('a,'b) t -> 'a -> bool    val remove : ('a,'b) t -> 'a -> unit   (* removes the most recent *)
val iter : ('a -> 'b -> unit) -> ('a,'b) t -> unit    val fold : ('a -> 'b -> 'acc -> 'acc) -> ('a,'b) t -> 'acc -> 'acc
val filter_map_inplace : ('a -> 'b -> 'b option) -> ('a,'b) t -> unit    val to_seq / of_seq / copy / clear / reset
```

### `Seq` — *"a delayed list, … elements computed only when demanded"* (lazy, pull-based)
```ocaml
type 'a t = unit -> 'a node    and 'a node = Nil | Cons of 'a * 'a t
val empty : 'a t    val return : 'a -> 'a t    val cons : 'a -> 'a t -> 'a t
val map / filter / filter_map / take / drop / append / concat / flat_map     (* all LAZY: O(1) until forced *)
val init : int -> (int -> 'a) -> 'a t    val unfold : ('b -> ('a * 'b) option) -> 'b -> 'a t
val fold_left / iter / length / is_empty / for_all / exists    (* eager: force the sequence *)
val uncons : 'a t -> ('a * 'a t) option    val find : ('a -> bool) -> 'a t -> 'a option   (* NB: option, unlike List.find *)
val memoize : 'a t -> 'a t    val once : 'a t -> 'a t   (* once = single-use; raises if re-forced *)
```

### `Option` / `Result` — values for absence / errors
```ocaml
(* Option: "explicitly indicate the presence or absence of a value." *)
val none : 'a option    val some : 'a -> 'a option
val value : 'a option -> default:'a -> 'a    val get : 'a option -> 'a   (* raises Invalid_argument on None *)
val bind : 'a option -> ('a -> 'b option) -> 'b option    val map : ('a -> 'b) -> 'a option -> 'b option
val fold : none:'a -> some:('b -> 'a) -> 'b option -> 'a    val is_some / is_none : 'a option -> bool
val to_result : none:'e -> 'a option -> ('a,'e) result    val to_list / to_seq
(* Result: "handle results and errors explicitly … without resorting to exceptions." *)
type ('a, 'e) result = Ok of 'a | Error of 'e
val ok : 'a -> ('a,'e) result    val error : 'e -> ('a,'e) result    val value : ('a,'e) result -> default:'a -> 'a
val get_ok : ('a,'e) result -> 'a    val get_error : ('a,'e) result -> 'e
val bind : ('a,'e) result -> ('a -> ('b,'e) result) -> ('b,'e) result    val map : ('a -> 'b) -> ('a,'e) result -> ('b,'e) result
val map_error : ('e -> 'f) -> ('a,'e) result -> ('a,'f) result    val fold : ok:('a -> 'c) -> error:('e -> 'c) -> ('a,'e) result -> 'c
val to_option : ('a,'e) result -> 'a option
```

### `Format` — *"pretty-printing … values within pretty-printing boxes"* (the structured printer)
```ocaml
type formatter    val std_formatter : formatter    val err_formatter : formatter
val fprintf  : formatter -> ('a, formatter, unit) format -> 'a
val printf   : ('a, formatter, unit) format -> 'a    val eprintf : ('a, formatter, unit) format -> 'a
val asprintf : ('a, formatter, unit, string) format4 -> 'a    (* format to a string *)
val pp_print_string : formatter -> string -> unit    val pp_print_flush : formatter -> unit -> unit
```
Format-string control codes (verbatim semantics): **`@[` opens a box, `@]` closes it**; **`@ ` (space
after `@`)** = a *space* break hint (split here, else one space); **`@,`** a *cut* hint; **`@;`** a
*full* hint; **`@.`** flush + newline; **`@\n`** force newline. Conversions: **`%a`** takes a
`(formatter -> 'a -> unit)` printer **then** the value; **`%t`** takes a `(formatter -> unit)`. Box
semantics: in an **h** box hints never split; in a **v** box hints always split; in an **hv/hov** box
they split only if the box doesn't fit. Idiom: `let pp fmt x = Format.fprintf fmt "@[<v>%a@]" pp_elt x`.

### `Printf` — *"Formatted output functions."* (plain text, to channels/strings)
```ocaml
val printf  : ('a, out_channel, unit) format -> 'a    (* to stdout *)
val eprintf : ('a, out_channel, unit) format -> 'a    (* to stderr *)
val fprintf : out_channel -> ('a, out_channel, unit) format -> 'a
val sprintf : ('a, unit, string) format -> 'a         (* to a string *)
val bprintf : Buffer.t -> ('a, Buffer.t, unit) format -> 'a
val ksprintf : (string -> 'd) -> ('a, unit, string, 'd) format4 -> 'a
```
Specifiers: `%d`/`%i` (int), `%u`/`%x`/`%X`/`%o` (unsigned/hex/oct), `%s`/`%S`, `%c`/`%C`, `%f`/`%e`/
`%g`/`%h` (float), `%B` (bool), `%a` (user printer `out_channel -> 'a -> unit`), `%t`, `%ld`/`%Ld`/`%nd`
(sized ints), `%%`, `%!` (flush); with flags `- 0 + space #`, optional width, optional `.precision`.

## §30 The compiler front-end (`compiler-libs`) — the compiler *as a library*
The compiler's own internals, exposed so tools can parse / transform / typecheck OCaml: **ppx
rewriters**, custom toplevels, linters, doc/coverage tools, and analysis platforms like **Frama-C**
(built on these).
- **⚠ Stability (verbatim, `compilerlibref`):** *"This library is part of the internal OCaml compiler
  API, and is not the language standard library."* It is **not stable** — modules change between OCaml
  releases with no compatibility promise. Code a tool directly against `Parsetree`/`Typedtree` and it
  **breaks on a new compiler** — precisely how a tool can declare version compatibility yet misbehave
  on a kernel/compiler it was not built against (pin to your version). **For ppx, use `ppxlib`** (a
  stable AST wrapper over compiler-libs), not raw compiler-libs.
- **Surface AST & parsing** (confirmed in the index): `Location`, `Longident`, `Asttypes`,
  **`Parsetree`** (the untyped AST), `Parse`, `Lexer`, `Parser`, `Syntaxerr`, `Pparse`,
  **`Ast_helper`** (build) / **`Ast_mapper`** / `Ast_iterator` (traverse — the ppx surface),
  `Ast_invariants`, `Builtin_attributes`, `Attr_helper`, `Docstrings`, `Pprintast` / `Printast`
  (re-print / dump), `Depend` (dependency analysis).
- **Typing & files:** the typing modules `Typedtree`, `Types`, `Env`, `Ident`, `Path`, `Ctype`,
  `Typecore`/`Typemod`, plus `Cmi_format`/`Cmt_format` (read `.cmi`/`.cmt`) — among the "and others"
  the index lists beyond the parsing set.
- **Driver/config:** `Clflags`, `Warnings`, `Misc`, `Config`, `Load_path`, `Profile`.
- **Packaging:** shipped (via ocamlfind/dune) as `compiler-libs.common` (parsing/typing/config),
  `compiler-libs.bytecomp`, `compiler-libs.optcomp`, and `compiler-libs.toplevel` — note the API index
  itself does **not** itemize this split; it is the build-level partition, not part of the API docs.

## §31 The `unix` library — interface to the Unix system
Link `unix`. Module doc: *"Interface to the Unix system."* **Every function except `error_message`
and `handle_unix_error` raises `Unix.Unix_error` when the underlying syscall fails.**
```ocaml
type error = E2BIG | EACCES | EAGAIN | EBADF | EINTR | ENOENT | EPERM | (* … *) | EUNKNOWNERR of int
exception Unix_error of error * string * string   (* error code, fn name, string arg ("" if none) *)
val error_message : error -> string
val handle_unix_error : ('a -> 'b) -> 'a -> 'b     (* run f; on Unix_error print to stderr & exit 2 *)
(* files *)
type file_descr   val stdin : file_descr  val stdout : file_descr  val stderr : file_descr
val openfile : string -> open_flag list -> file_perm -> file_descr
val read  : file_descr -> bytes -> int -> int -> int   (* fd buf ofs len -> #bytes read *)
val write : file_descr -> bytes -> int -> int -> int
val close : file_descr -> unit
val lseek : file_descr -> int -> seek_command -> int
(* processes *)
val fork   : unit -> int                               (* 0 in child, child pid in parent *)
val execv  : string -> string array -> 'a
val execvp : string -> string array -> 'a
val execve : string -> string array -> string array -> 'a
type process_status = WEXITED of int | WSIGNALED of int | WSTOPPED of int
val wait    : unit -> int * process_status
val waitpid : wait_flag list -> int -> int * process_status
val system  : string -> process_status               val getpid : unit -> int
(* pipes / time / env / sockets *)
val pipe : ?cloexec:bool -> unit -> file_descr * file_descr
val time : unit -> float                              val gettimeofday : unit -> float
val getenv : string -> string                        val environment : unit -> string array
type sockaddr = ADDR_UNIX of string | ADDR_INET of inet_addr * int
val socket : ?cloexec:bool -> socket_domain -> socket_type -> int -> file_descr
val bind : file_descr -> sockaddr -> unit            val listen : file_descr -> int -> unit
val accept : ?cloexec:bool -> file_descr -> file_descr * sockaddr
val connect : file_descr -> sockaddr -> unit
```
**Windows caveat:** unavailable calls (`fork`, `wait`, `mkfifo`, `chroot`, signal/user/group ops) raise
`Invalid_argument` on Windows — use `create_process` / threads instead. For portable high-level
concurrency/IO prefer **Eio** over raw blocking `Unix`.

## §32 The `str` library — regular expressions
Link `str`. Module doc: *"Regular expressions and high-level string processing."*
```ocaml
type regexp
val regexp : string -> regexp        val regexp_case_fold : string -> regexp
val quote : string -> string         val regexp_string : string -> regexp
val string_match    : regexp -> string -> int -> bool   (* anchored at exactly the given pos *)
val search_forward  : regexp -> string -> int -> int    (* -> match start; raises Not_found *)
val search_backward : regexp -> string -> int -> int
val matched_string  : string -> string
val match_beginning : unit -> int    val match_end : unit -> int     (* <- NO string/regexp arg! *)
val matched_group   : int -> string -> string
val global_replace  : regexp -> string -> string -> string   (* regexp template s *)
val replace_first   : regexp -> string -> string -> string
val split : regexp -> string -> string list   val split_delim : regexp -> string -> string list
val full_split : regexp -> string -> split_result list
type split_result = Text of string | Delim of string
```
**⚠ Non-reentrant (load-bearing).** The match accessors (`matched_string`, `match_beginning`/`_end`,
`matched_group`) take **no `regexp`/`string` of their own** — they read **global match state** left by
the last `string_match`/`search_*`. So `Str` is **not thread/domain-safe**, and a nested or interleaved
match clobbers an outer one. The regex dialect is also small. **For new code (and any multicore code)
use the opam `re` library** (`Re`, `Re.Pcre`/`Re.Posix` — compiled, reentrant, results returned as
values, not stashed in globals).

## §33 The `runtime_events` library — low-overhead runtime tracing
Link `runtime_events`. Module doc: *"Runtime events — ring buffer-based runtime tracing"* — "enable and
subscribe to tracing events from the Garbage Collector and other parts of the OCaml runtime" (new in
OCaml 5; cheap enough to leave **always on** in production). A *producer* side (the program emits
events) and a *consumer* side (reads the ring buffer through a cursor).

**Control (producer):**
```ocaml
val start  : unit -> unit            (* begin recording — or set env OCAML_RUNTIME_EVENTS_START=1 *)
val pause  : unit -> unit
val resume : unit -> unit
val path   : unit -> string option   (* the ring-buffer file path, if any *)
```
**Event kinds** (each with a `*_name : _ -> string` helper):
- `type runtime_phase` — *span* events: `EV_EXPLICIT_GC_*`, `EV_MAJOR_*`, `EV_MINOR_*`, `EV_COMPACT_*`,
  `EV_DOMAIN_*`, `EV_STW_*`, `EV_EMPTY_MINOR`.
- `type runtime_counter` — *counter* events: `EV_C_FORCE_MINOR_*`, `EV_C_MINOR_*`,
  `EV_C_REQUEST_MAJOR_*`, `EV_C_MAJOR_*`.
- `type lifecycle` — ring/domain: `EV_RING_START | EV_RING_STOP | EV_RING_PAUSE | EV_RING_RESUME`,
  `EV_FORK_PARENT | EV_FORK_CHILD`, `EV_DOMAIN_SPAWN | EV_DOMAIN_TERMINATE`.

**Consume (cursor + callbacks):**
```ocaml
type cursor
val create_cursor : (string * int) option -> cursor   (* None = current process; Some (path,pid) = external *)
val free_cursor   : cursor -> unit
val read_poll     : cursor -> Callbacks.t -> int option -> int   (* dispatch events; returns #consumed *)

(* module Runtime_events.Callbacks *)
type t
val create :
  ?runtime_begin   : (int -> Timestamp.t -> runtime_phase -> unit) ->
  ?runtime_end     : (int -> Timestamp.t -> runtime_phase -> unit) ->
  ?runtime_counter : (int -> Timestamp.t -> runtime_counter -> int -> unit) ->
  ?alloc           : (int -> Timestamp.t -> int array -> unit) ->
  ?lifecycle       : (int -> Timestamp.t -> lifecycle -> int option -> unit) ->
  ?lost_events     : (int -> int -> unit) -> unit -> t
val add_user_event : 'a Type.t -> (int -> Timestamp.t -> 'a User.t -> 'a -> unit) -> t -> t
```
(Each handler's leading `int` is the emitting **domain id**; `Timestamp.t` is the event time.)

**Custom user events (module `Runtime_events.User`):**
```ocaml
type tag = ..                                              (* extend to name your own events *)
type 'value t
val register : string -> tag -> 'value Type.t -> 'value t  (* declare a typed event *)
val write    : 'value t -> 'value -> unit                  (* emit it *)
val name : 'a t -> string      val tag : 'a t -> tag
```
Payloads come from `Runtime_events.Type` (e.g. `Type.unit`, `Type.int`, `Type.span` for begin/end
spans, plus `Type.register` for custom encodings). Consumed by tooling — **`olly`** and the perf /
runtime-tracing integration (manual §25). Distinct from `Gc` / `Memprof`.

## §34 The `threads` library — concurrency (not parallelism)
Link `threads.posix`. Module doc: *"Lightweight threads for Posix 1003.1c and Win32."*
```ocaml
type t
val create : ('a -> 'b) -> 'a -> t     val self : unit -> t     val id : t -> int
val join : t -> unit                   val exit : unit -> unit
val yield : unit -> unit               val delay : float -> unit
val wait_timed_read  : Unix.file_descr -> float -> bool
val wait_timed_write : Unix.file_descr -> float -> bool
val sigmask : Unix.sigprocmask_command -> int list -> int list
val wait_signal : int list -> int
```
Threads give **interleaved concurrency**, plus `Mutex` / `Condition` / `Semaphore` (now in `Stdlib`).
In OCaml 5, threads *within one domain* do **not** run in parallel (one runs at a time) — the manual
notes: *"See also `Domain.spawn` if you want parallel execution instead."* Use threads for blocking-I/O
concurrency and legacy code; for **CPU-parallel** work use `Domain` + `domainslib` (see
`concurrency-and-effects-5x.md`). Threads run in parallel only insofar as they sit on different domains.

## §35 The `dynlink` library — load compiled modules at runtime
Link `dynlink`. Module doc: *"Dynamic loading of `.cmo`, `.cma` and `.cmxs` files."* The mechanism
behind **plugins** (Frama-C loads its plugins this way). **The backend dictates the file form:
bytecode loads `.cmo` / `.cma`; native loads `.cmxs`** (a plugin shared object built with
`ocamlopt -shared`); `val is_native : bool` tells you which backend is running.
Exact API (verbatim):
```ocaml
val is_native : bool
val loadfile : string -> unit            (* load & link a unit; its module becomes visible to later loads *)
val loadfile_private : string -> unit    (* load in isolation: not visible to later loads (sandbox-friendly) *)
val adapt_filename : string -> string    (* .cmo <-> .cmxs for the current backend, so one path works in either *)
(* sandboxing — restrict which units a plugin may reference: *)
val set_allowed_units : string list -> unit
val allow_only  : string list -> unit
val prohibit    : string list -> unit
val main_program_units : unit -> string list
val public_dynamically_loaded_units : unit -> string list
val all_units   : unit -> string list
val allow_unsafe_modules : bool -> unit
(* errors: *)
type linking_error = private
  | Undefined_global of string | Unavailable_primitive of string | Uninitialized_global of string
type error = private
  | Not_a_bytecode_file of string | Inconsistent_import of string | Unavailable_unit of string
  | Unsafe_file | Linking_error of string * linking_error | Corrupted_interface of string
  | Cannot_open_dynamic_library of exn | Library's_module_initializers_failed of exn
  | Inconsistent_implementation of string | Module_already_loaded of string
  | Private_library_cannot_implement_interface of string
exception Error of error
val error_message : error -> string
```
A loaded unit may only reference units already present in the program (or previously loaded);
violations surface as `Unavailable_unit`/`Linking_error`. **Native caveat (verbatim):** in native
code `allow_unsafe_modules` *does nothing* — files with external (C) functions always link dynamically.

## Quick "which library do I link?" (dune `(libraries …)`)
`unix` · `str` (or opam `re`) · `threads.posix` · `dynlink` · `runtime_events` · `compiler-libs.common`
(or `ppxlib` for ppx). §28–29 need nothing — they are always linked.
