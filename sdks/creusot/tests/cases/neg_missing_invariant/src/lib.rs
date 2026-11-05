//! Negative: the loop has no invariant about the elements, so the
//! postcondition cannot be established (the code itself is correct).
use creusot_std::prelude::*;

/// With the invariant: must be proved.
#[ensures((^v)@.len() == v@.len())]
#[ensures(forall<i: Int> 0 <= i && i < v@.len() ==> (^v)[i] == 0u32)]
pub fn zero_ok(v: &mut Vec<u32>) {
    let old = snapshot!(v);
    #[invariant(v@.len() == old@.len())]
    #[invariant(forall<j: Int> 0 <= j && j < produced.len() ==> v[j] == 0u32)]
    for i in 0..v.len() {
        v[i] = 0;
    }
}

/// The same code without the element invariant: must NOT be proved.
#[ensures((^v)@.len() == v@.len())]
#[ensures(forall<i: Int> 0 <= i && i < v@.len() ==> (^v)[i] == 0u32)]
pub fn zero_missing_invariant(v: &mut Vec<u32>) {
    let old = snapshot!(v);
    #[invariant(v@.len() == old@.len())]
    for i in 0..v.len() {
        v[i] = 0;
    }
}
