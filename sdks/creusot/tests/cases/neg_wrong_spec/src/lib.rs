//! Negative: a postcondition that does not hold (max specified as a minimum).
use creusot_std::prelude::*;

/// Correct: must be proved.
#[ensures(result >= a && result >= b)]
#[ensures(result == a || result == b)]
pub fn max_ok(a: i32, b: i32) -> i32 {
    if a >= b { a } else { b }
}

/// Wrong spec: must NOT be proved.
#[ensures(result <= a && result <= b)]
pub fn max_wrong_spec(a: i32, b: i32) -> i32 {
    if a >= b { a } else { b }
}
