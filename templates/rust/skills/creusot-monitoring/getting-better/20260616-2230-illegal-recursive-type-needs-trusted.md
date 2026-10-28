# Feature gap: "Illegal recursive type" has no faithful (non-`#[trusted]`) opt-out

## Symptom
`cargo creusot` rejects a type that recurses under a non-WellFounded / opaque generic
container at **translation time** with `error: Illegal recursive type` — before any proof
obligation is generated. Examples from `annotate/specification/trusted.rs`:
- `struct Rose<T>(T, Vec<Rose<T>>)` — `Rose` recurses under `Vec`.
- `Carnation` nested inside `Rose<...>`.

This is a hard front-end error in the Creusot translator, not an SMT goal. No Pearlite
annotation (`#[requires]`/`#[ensures]`/`#[invariant]`/`#[logic]`) can suppress it.

## Why it matters to the monitor
The ONLY Creusot mechanism that makes such a type translate is `#[trusted]` on the
type/function (that is literally what the upstream `trusted.rs` example demonstrates).
The creusot-sl faithfulness rule forbids ADDING `#[trusted]`, so the whole file is an
irreducible **FAILED** — even though there is nothing wrong with the annotator's work.
The monitor must not score this empty-spec FAILED as an annotator miss; it is a terrain
limitation, structurally FAILED-without-`#[trusted]`.

## Requested improvement
A faithful (strip-clean) opt-in that lets a recursive type be treated as **opaque** for
modeling purposes WITHOUT the soundness-erasing blanket of `#[trusted]` would let the
loop handle this whole class. Absent that, the loop should classify
`Illegal recursive type` as a known FAILED-terrain and stop iterating immediately rather
than burning the 3-iteration budget.

## Provenance
creusot-monitoring batch 16, file `annotate/specification/trusted.rs`.
