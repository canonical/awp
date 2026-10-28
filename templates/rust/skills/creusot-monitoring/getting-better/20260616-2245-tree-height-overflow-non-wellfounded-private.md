# Feature gap: recursive-measure overflow bound unreachable for non-WellFounded, private-field, Box-nested ADT

## Symptom
`annotate/syntax/10_mutual_rec_types.rs` defines a legal Box-nested *mutually recursive*
ADT:
```
pub struct Tree(Option<Box<Node>>);
struct Node { left: Tree, right: Tree, /* ... */ }
```
A `height` function does `n.left.height().max(n.right.height()) + 1`, which raises a
genuine `+ 1` integer-overflow VC. The type TRANSLATES fine (unlike the
"Illegal recursive type" case — Box-nested recursion is legal, no front-end error), but
the overflow VC cannot be discharged faithfully (without `#[trusted]`).

## Why both faithful routes dead-end
1. **Type-invariant route:** bounding height via a recursive `#[logic] height_log(self)->Int`
   referenced from `impl Invariant for Tree` forces a termination proof
   ("Cannot prove termination for height_log") that no `#[variant]` can satisfy —
   `Tree: !WellFounded`, so even `#[variant(self)]` fails the `WellFounded` bound on
   `variant_check`.
2. **Contract route:** putting the bound in a `#[requires]`/`#[ensures]` on the
   necessarily-`pub fn height` hits "Cannot make `Node::left` / `Tree::height_log`
   transparent … less-visible item" because the helper pattern-matches PRIVATE fields and
   a pub method's contract cannot reference a less-visible item.

Net: a recursive-measure overflow bound is unreachable when the ADT is BOTH non-WellFounded
AND has private fields under a pub consumer. Only `#[trusted]` closes it (forbidden).

## Requested improvement
Either (a) a built-in structural/depth `WellFounded` instance for `Box`-nested recursive
enums (so `#[variant]` works), or (b) acceptance of structural recursion in
invariant-context logic fns WITHOUT a `WellFounded` variant — mirroring how Creusot
already accepts such structural recursion in plain postconditions. Either would let this
whole class of tree-height/depth overflow proofs close faithfully.

## Distinction from the earlier "Illegal recursive type" gap
That gap (specification/trusted.rs) is a *translation-time* rejection
(`Vec<Rose<T>>` inside `struct Rose`). THIS gap translates cleanly and only the *proof*
is unclosable. Same remedy family (need a usable measure), different failure layer.

## Provenance
creusot-monitoring batch 17, file `annotate/syntax/10_mutual_rec_types.rs`.
