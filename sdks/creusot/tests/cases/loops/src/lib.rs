//! Loops: invariants, variants (#[check(terminates)]), `for` loops over
//! ranges with `produced`, and a loop that writes through a `&mut Vec`.
use creusot_std::prelude::*;

/// 0 + 1 + ... + n, by a `while` loop that must terminate (variant).
#[check(terminates)]
#[requires(n@ <= 100_000)]
#[ensures(result@ * 2 == n@ * (n@ + 1))]
pub fn triangle(n: u64) -> u64 {
    let mut i: u64 = 0;
    let mut acc: u64 = 0;
    #[variant(n@ - i@)]
    #[invariant(i@ <= n@)]
    #[invariant(acc@ * 2 == i@ * (i@ + 1))]
    while i < n {
        i += 1;
        acc += i;
    }
    acc
}

/// Counts down to zero; the number of steps is the input.
#[check(terminates)]
#[ensures(result == x)]
pub fn count_down(mut x: u32) -> u32 {
    let mut steps: u32 = 0;
    let total = snapshot!(x@);
    #[variant(x)]
    #[invariant(*total == x@ + steps@)]
    while x > 0 {
        x -= 1;
        steps += 1;
    }
    steps
}

/// Sets every element to `value`, with a `for` loop.
#[ensures((^v)@.len() == v@.len())]
#[ensures(forall<i: Int> 0 <= i && i < v@.len() ==> (^v)[i] == value)]
pub fn fill(v: &mut Vec<u32>, value: u32) {
    let old = snapshot!(v);
    #[invariant(v@.len() == old@.len())]
    #[invariant(forall<j: Int> 0 <= j && j < produced.len() ==> v[j] == value)]
    for i in 0..v.len() {
        v[i] = value;
    }
}

/// Number of elements equal to `x`, bounded by the length.
#[ensures(result@ <= s@.len())]
#[ensures(result@ == 0 ==> forall<i: Int> 0 <= i && i < s@.len() ==> s[i] != x)]
pub fn count(s: &[u32], x: u32) -> usize {
    let mut n: usize = 0;
    #[invariant(n@ <= produced.len())]
    #[invariant(n@ == 0 ==> forall<j: Int> 0 <= j && j < produced.len() ==> s[j] != x)]
    for i in 0..s.len() {
        if s[i] == x {
            n += 1;
        }
    }
    n
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn triangle_values() {
        assert_eq!(triangle(0), 0);
        assert_eq!(triangle(4), 10);
        assert_eq!(triangle(100_000), 5_000_050_000);
    }

    #[test]
    fn count_down_values() {
        assert_eq!(count_down(7), 7);
    }

    #[test]
    fn fill_and_count() {
        let mut v = std::vec![1, 2, 3];
        fill(&mut v, 9);
        assert_eq!(v, std::vec![9, 9, 9]);
        assert_eq!(count(&v, 9), 3);
        assert_eq!(count(&v, 1), 0);
    }
}
