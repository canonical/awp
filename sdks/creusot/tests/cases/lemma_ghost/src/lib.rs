//! Logic functions, a lemma proved by induction (a recursive logic function
//! with a variant), its use in a `proof_assert!`, snapshots and `ghost!` code.
use creusot_std::prelude::*;

/// 1 + 3 + ... + (2n - 1), in the logic.
#[logic]
#[variant(n)]
pub fn sum_of_odds(n: Int) -> Int {
    if n <= 0 { 0 } else { sum_of_odds(n - 1) + 2 * n - 1 }
}

/// The lemma: sum_of_odds(n) == n * n, by induction on n.
#[logic]
#[requires(n >= 0)]
#[ensures(sum_of_odds(n) == n * n)]
#[variant(n)]
pub fn sum_of_odds_is_square(n: Int) {
    pearlite! { if n > 0 { sum_of_odds_is_square(n - 1) } else { () } }
}

/// The program computes the logic function; the lemma gives the closed form.
#[requires(n@ < 0x10000)]
#[ensures(result@ == n@ * n@)]
pub fn square_by_odds(n: u32) -> u32 {
    let mut s: u32 = 0;
    #[invariant(s@ == sum_of_odds(produced.len()))]
    #[invariant(s@ == produced.len() * produced.len())]
    for i in 0..n {
        proof_assert! { sum_of_odds_is_square(i@ + 1); true };
        s += 2 * i + 1;
    }
    s
}

/// Ghost code: a ghost counter mirrors the loop, and is erased at run time.
#[check(terminates)]
#[ensures(result@ == 2 * n@)]
pub fn double_with_ghost(n: u16) -> u32 {
    let mut r: u32 = 0;
    let mut i: u16 = 0;
    let mut steps = ghost!(0int);
    let start = snapshot!(r);
    #[variant(n@ - i@)]
    #[invariant(i@ <= n@)]
    #[invariant(r@ == 2 * i@)]
    #[invariant(*steps == i@)]
    #[invariant(start@ == 0)]
    while i < n {
        r += 2;
        i += 1;
        ghost! { *steps = *steps + 1int };
    }
    proof_assert!(*steps == n@);
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn squares() {
        assert_eq!(square_by_odds(0), 0);
        assert_eq!(square_by_odds(12), 144);
        assert_eq!(double_with_ghost(21), 42);
    }
}
