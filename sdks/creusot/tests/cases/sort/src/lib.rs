//! An in-place insertion sort: the result is sorted and a permutation of the
//! input (`permutation_of`, `^` for the final value of a mutable borrow).
use creusot_std::prelude::*;

#[logic(open)]
pub fn sorted_range(s: Seq<i32>, l: Int, u: Int) -> bool {
    pearlite! { forall<i: Int, j: Int> l <= i && i < j && j < u ==> s[i] <= s[j] }
}

#[logic(open)]
pub fn sorted(s: Seq<i32>) -> bool {
    pearlite! { sorted_range(s, 0, s.len()) }
}

#[ensures(a@.permutation_of((^a)@))]
#[ensures(sorted((^a)@))]
pub fn insertion_sort(a: &mut [i32]) {
    let original = snapshot!(a);
    let n = a.len();
    #[invariant(sorted_range(a@, 0, produced.len() + 1))]
    #[invariant(a@.len() == n@)]
    #[invariant(original@.permutation_of(a@))]
    for i in 1..n {
        let mut j = i;
        #[invariant(j <= i)]
        #[invariant(a@.len() == n@)]
        #[invariant(original@.permutation_of(a@))]
        #[invariant(forall<p: Int, q: Int> 0 <= p && p <= q && q <= i@ ==> p != j@ ==> q != j@ ==> a[p] <= a[q])]
        #[invariant(forall<p: Int> j@ + 1 <= p && p <= i@ ==> a[j@] < a[p])]
        while j > 0 {
            if a[j - 1] > a[j] {
                a.swap(j - 1, j);
            } else {
                break;
            }
            j -= 1;
        }
    }
    proof_assert!(sorted_range(a@, 0, a@.len()));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sorts() {
        let mut a = [5, -1, 3, 3, 0, 9, -7];
        insertion_sort(&mut a);
        assert_eq!(a, [-7, -1, 0, 3, 3, 5, 9]);
        let mut e: [i32; 0] = [];
        insertion_sort(&mut e);
    }
}
