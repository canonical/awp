# Concrete-value assertions on `filter`/`filter_map` chains are intractable (doubly-existential `produces`)

- **Trigger:** annotate/cc/iter.rs (creusot-monitoring batch 9). Confirmed against L: the
  bare copy proves `test_mut_ref` (plain `[..].iter()` chain) with zero annotations, but
  `test_filter` and `test_filter_map` stay at 18/19 unproved and no faithful annotation
  closes the gap.
- **Observed behaviour:** an assertion that pins the concrete value yielded by a chained
  `filter()/filter_map().next()` (e.g. `assert_eq!((&mut it).next(), Some(&true))`) cannot
  be discharged. Creusot-std's `Filter::produces`/`completed` specs
  (creusot-std/src/std/iter/filter.rs) are existential over BOTH a witness sequence `s`
  AND a monotone index `Mapping<Int,Int>`; the spec author's own inline comment states Z3
  "gives up *totally* on s". The canonical Creusot example
  (examples/iterators/17_filter.rs) only ever proves the ABSTRACT `produces` relation
  (results are `< n` and were in the input), never a chained `next()` equal to a concrete
  `Some(value)`. The test bodies have no loop to host a `#[invariant]`, and any
  `proof_assert!` strong enough to pin the value carries the same unprovable existential
  witness.
- **Desired behaviour:** a tractable proof path for concrete first/second/None yields of
  `filter`/`filter_map` over a fully-known finite input — e.g. (a) a value-pinning lemma
  form of `Filter::produces` specialized to literal/finite inputs, or (b) library-side
  `extern_spec` support for evaluating adapter chains on literal arrays. Plain `iter()`
  chains already work, so the gap is specific to the lazy `filter`/`filter_map` adapters'
  doubly-existential `produces` encoding.
- **Minimal example:**
  ```rust
  let a = [true, false, true];
  let mut it = a.iter().filter(|b: &&bool| **b);
  assert_eq!(it.next(), Some(&true));   // unprovable: Filter::produces is existential over Seq + Mapping
  ```
