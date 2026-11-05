//! Negative: termination. A loop whose variant does not decrease on every
//! iteration, in a function checked to terminate.
use creusot_std::prelude::*;

/// Decreasing variant: must be proved.
#[check(terminates)]
pub fn countdown_ok(mut n: u32) {
    #[variant(n)]
    while n > 0 {
        n -= 1;
    }
}

/// The variant does not decrease when n is odd: must NOT be proved.
#[check(terminates)]
pub fn countdown_bad_variant(mut n: u32) {
    #[variant(n)]
    while n > 0 {
        if n % 2 == 0 {
            n -= 1;
        }
    }
}
