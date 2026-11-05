//! Negative: an off-by-one bug (`<=` for `<`) in a loop over a slice; the
//! index s[i] goes out of bounds when i == s.len().
use creusot_std::prelude::*;

/// Correct: must be proved.
#[ensures(result == true ==> exists<i: Int> 0 <= i && i < s@.len() && s[i] == x)]
pub fn contains_ok(s: &[u32], x: u32) -> bool {
    let mut i: usize = 0;
    #[invariant(i@ <= s@.len())]
    while i < s.len() {
        if s[i] == x {
            return true;
        }
        i += 1;
    }
    false
}

/// Off by one: must NOT be proved.
#[ensures(result == true ==> exists<i: Int> 0 <= i && i < s@.len() && s[i] == x)]
pub fn contains_off_by_one(s: &[u32], x: u32) -> bool {
    let mut i: usize = 0;
    #[invariant(i@ <= s@.len())]
    while i <= s.len() {
        if s[i] == x {
            return true;
        }
        i += 1;
    }
    false
}
