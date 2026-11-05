//! Slices and `Vec`s with quantified specifications: a binary search over a
//! sorted slice, an in-place reversal, and the index of a maximum.
use creusot_std::prelude::*;

#[logic(open)]
pub fn sorted(s: Seq<u32>) -> bool {
    pearlite! { forall<i: Int, j: Int> 0 <= i && i <= j && j < s.len() ==> s[i] <= s[j] }
}

/// Ok(i): s[i] == x. Err(i): x would be inserted at i (everything before is
/// smaller, everything from i on is larger).
#[requires(sorted(s@))]
#[ensures(forall<i: usize> result == Ok(i) ==> i@ < s@.len() && s[i@] == x)]
#[ensures(forall<i: usize> result == Err(i) ==> i@ <= s@.len()
    && (forall<j: Int> 0 <= j && j < i@ ==> s[j] < x)
    && (forall<j: Int> i@ <= j && j < s@.len() ==> x < s[j]))]
pub fn binary_search(s: &[u32], x: u32) -> Result<usize, usize> {
    let mut lo: usize = 0;
    let mut hi: usize = s.len();
    #[invariant(lo@ <= hi@ && hi@ <= s@.len())]
    #[invariant(forall<j: Int> 0 <= j && j < lo@ ==> s[j] < x)]
    #[invariant(forall<j: Int> hi@ <= j && j < s@.len() ==> x < s[j])]
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        if s[mid] < x {
            lo = mid + 1;
        } else if s[mid] > x {
            hi = mid;
        } else {
            return Ok(mid);
        }
    }
    Err(lo)
}

/// In-place reversal: the final slice is the reverse of the initial one.
#[ensures((^s)@.len() == s@.len())]
#[ensures(forall<i: Int> 0 <= i && i < s@.len() ==> (^s)[i] == s[s@.len() - 1 - i])]
pub fn reverse(s: &mut [i32]) {
    let old = snapshot!(s);
    let n = s.len();
    let mut i: usize = 0;
    #[invariant(s@.len() == n@ && old@.len() == n@)]
    #[invariant(i@ <= n@ / 2)]
    #[invariant(forall<k: Int> 0 <= k && k < i@ ==> s[k] == old[n@ - 1 - k])]
    #[invariant(forall<k: Int> 0 <= k && k < i@ ==> s[n@ - 1 - k] == old[k])]
    #[invariant(forall<k: Int> i@ <= k && k < n@ - i@ ==> s[k] == old[k])]
    while i < n / 2 {
        s.swap(i, n - 1 - i);
        i += 1;
    }
}

/// Index of a maximum of a non-empty vector.
#[requires(v@.len() > 0)]
#[ensures(result@ < v@.len())]
#[ensures(forall<i: Int> 0 <= i && i < v@.len() ==> v[i] <= v[result@])]
pub fn argmax(v: &Vec<i64>) -> usize {
    let mut best: usize = 0;
    #[invariant(best@ < v@.len())]
    #[invariant(forall<j: Int> 0 <= j && j < produced.len() + 1 ==> v[j] <= v[best@])]
    for i in 1..v.len() {
        if v[i] > v[best] {
            best = i;
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn search() {
        let s = [1, 3, 5, 7, 9];
        assert_eq!(binary_search(&s, 7), Ok(3));
        assert_eq!(binary_search(&s, 4), Err(2));
        assert_eq!(binary_search(&s, 0), Err(0));
        assert_eq!(binary_search(&s, 10), Err(5));
        assert_eq!(binary_search(&[], 1), Err(0));
    }

    #[test]
    fn rev() {
        let mut a = [1, 2, 3, 4, 5];
        reverse(&mut a);
        assert_eq!(a, [5, 4, 3, 2, 1]);
        let mut b: [i32; 0] = [];
        reverse(&mut b);
    }

    #[test]
    fn max() {
        assert_eq!(argmax(&std::vec![3, 9, -1, 9]), 1);
    }
}
