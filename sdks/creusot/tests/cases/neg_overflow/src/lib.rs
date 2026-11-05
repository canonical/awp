//! Negative: unchecked arithmetic that can overflow (the classic (lo+hi)/2
//! and an unguarded multiplication).
use creusot_std::prelude::*;

/// Overflow-free: must be proved.
#[requires(lo@ <= hi@)]
#[ensures(lo@ <= result@ && result@ <= hi@)]
pub fn midpoint_ok(lo: usize, hi: usize) -> usize {
    lo + (hi - lo) / 2
}

/// lo + hi overflows: must NOT be proved.
#[requires(lo@ <= hi@)]
#[ensures(lo@ <= result@ && result@ <= hi@)]
pub fn midpoint_overflow(lo: usize, hi: usize) -> usize {
    (lo + hi) / 2
}

/// No precondition bounds x: must NOT be proved.
#[ensures(result@ == x@ * x@)]
pub fn square_overflow(x: u32) -> u32 {
    x * x
}
