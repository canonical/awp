//! A struct with a type invariant (`Invariant`) and a logical model
//! (`View`, the `@` notation): a bounded counter and a stack over a `Vec`.
use creusot_std::{invariant::Invariant, prelude::*};

/// value <= max, always.
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

impl View for Bounded {
    type ViewTy = Int;
    #[logic(open(self))]
    fn view(self) -> Int {
        pearlite! { self.value@ }
    }
}

impl Bounded {
    #[ensures(result@ == 0)]
    pub fn new(max: u32) -> Self {
        Bounded { value: 0, max }
    }

    #[ensures(result@ == self@)]
    pub fn get(&self) -> u32 {
        self.value
    }

    /// Saturates at max; never breaks the invariant, never overflows.
    #[ensures((^self)@ == self@ + 1 || (^self)@ == self@)]
    #[ensures(self.max == (^self).max)]
    pub fn incr(&mut self) {
        if self.value < self.max {
            self.value += 1;
        }
    }
}

/// A stack whose model is the sequence of its elements, and whose length is
/// bounded by its type invariant.
pub struct Stack {
    items: Vec<u64>,
}

impl Invariant for Stack {
    #[logic(open(self))]
    fn invariant(self) -> bool {
        pearlite! { self.items@.len() <= 1000 }
    }
}

impl View for Stack {
    type ViewTy = Seq<u64>;
    #[logic(open(self))]
    fn view(self) -> Seq<u64> {
        pearlite! { self.items@ }
    }
}

impl Stack {
    #[ensures(result@ == Seq::empty())]
    pub fn new() -> Self {
        Stack { items: Vec::new() }
    }

    #[ensures(result == (self@.len() == 1000))]
    pub fn is_full(&self) -> bool {
        self.items.len() == 1000
    }

    #[requires(self@.len() < 1000)]
    #[ensures((^self)@ == self@.snoc(x))]
    pub fn push(&mut self, x: u64) {
        self.items.push(x);
    }

    #[ensures(self@.len() == 0 ==> result == None && (^self)@ == self@)]
    #[ensures(self@.len() > 0 ==> result == Some(self@[self@.len() - 1])
        && (^self)@ == self@.subsequence(0, self@.len() - 1))]
    pub fn pop(&mut self) -> Option<u64> {
        self.items.pop()
    }
}

/// A client relies only on the model.
pub fn client() {
    let mut s = Stack::new();
    s.push(1);
    s.push(2);
    let top = s.pop();
    proof_assert!(top == Some(2u64));
    proof_assert!(s@.len() == 1);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counter() {
        let mut b = Bounded::new(2);
        b.incr();
        b.incr();
        b.incr();
        assert_eq!(b.get(), 2);
    }

    #[test]
    fn stack() {
        let mut s = Stack::new();
        assert!(!s.is_full());
        s.push(4);
        assert_eq!(s.pop(), Some(4));
        assert_eq!(s.pop(), None);
        client();
    }
}
