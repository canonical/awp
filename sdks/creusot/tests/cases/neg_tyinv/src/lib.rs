//! Negative: a method that breaks a type invariant (value <= max).
use creusot_std::{invariant::Invariant, prelude::*};

pub struct Bounded {
    value: u32,
    max: u32,
}

impl Invariant for Bounded {
    #[logic(open(self))]
    fn invariant(self) -> bool {
        pearlite! { self.value@ <= self.max@ }
    }
}

impl Bounded {
    /// Respects the invariant: must be proved.
    pub fn incr_ok(&mut self) {
        if self.value < self.max {
            self.value += 1;
        }
    }

    /// Breaks the invariant when value == max: must NOT be proved.
    #[requires(self.value@ < u32::MAX@)]
    pub fn incr_unchecked(&mut self) {
        self.value += 1;
    }

    /// Builds a value that violates the invariant: must NOT be proved.
    pub fn make_bad() -> Self {
        Bounded { value: 2, max: 1 }
    }
}
