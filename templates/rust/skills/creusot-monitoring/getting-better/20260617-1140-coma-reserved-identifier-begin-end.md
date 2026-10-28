# Creusot: a Rust parameter named `begin`/`end` produces an invalid `.coma` file

Date: 2026-06-17
Surfaced while: verifying `lace-util/src/lib.rs::hex_seq(bytes, begin, end)`.

## Symptom
`cargo creusot` compiles + translates fine, but the prover stage dies with a
raw OCaml/Why3 syntax error, NOT a Creusot diagnostic:

```
Fatal error: exception File "verif/<crate>/hex_seq.coma", line 52, characters 41-42:
syntax error
Error: 'why3find prove' failed
```

## Cause
Creusot maps the Rust parameter identifier `begin` verbatim into the generated
Coma. `begin` (and `end`) is a reserved keyword in the Coma / Why3 surface
syntax, so the emitted theory is unparseable. There is no name-mangling /
escaping for these identifiers. `end` is already escaped elsewhere as `end'`,
but `begin` is not.

## Workaround
Rename the offending Rust parameters/locals (e.g. `begin -> beg`, `end -> fin`)
in the verification scratch copy. After renaming, `hex_seq` verified fully
(all goals green).

## Suggested fix (upstream)
Creusot's Coma identifier printer should escape / rename Rust identifiers that
collide with Coma keywords (`begin`, `end`, `let`, `in`, `fun`, ...), the same
way it already rewrites `end` to `end'` in struct fields.

## Impact on monitoring
This is a BLOCKED-looking failure that is actually trivially worked around.
A green/red verdict is unaffected once renamed. Flag any source function whose
parameters are named `begin`/`end` and pre-rename in the scratch copy.
