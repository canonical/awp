//! Integer overflow handled correctly: a precondition, checked, saturating
//! and wrapping arithmetic, and an overflow-free midpoint.
use creusot_std::prelude::*;

#[requires(a@ + b@ <= u32::MAX@)]
#[ensures(result@ == a@ + b@)]
pub fn add_bounded(a: u32, b: u32) -> u32 {
    a + b
}

#[ensures(a@ + b@ <= u32::MAX@ ==> result == Some(a + b))]
#[ensures(a@ + b@ > u32::MAX@ ==> result == None)]
pub fn add_checked(a: u32, b: u32) -> Option<u32> {
    a.checked_add(b)
}

#[ensures(result@ == if a@ + b@ <= u32::MAX@ { a@ + b@ } else { u32::MAX@ })]
pub fn add_saturating(a: u32, b: u32) -> u32 {
    a.saturating_add(b)
}

#[ensures(result@ == a@ + b@ || result@ == a@ + b@ - 256)]
pub fn add_wrapping(a: u8, b: u8) -> u8 {
    a.wrapping_add(b)
}

/// The midpoint without computing lo + hi.
#[requires(lo@ <= hi@)]
#[ensures(lo@ <= result@ && result@ <= hi@)]
#[ensures(result@ == (lo@ + hi@) / 2)]
pub fn midpoint(lo: usize, hi: usize) -> usize {
    lo + (hi - lo) / 2
}

/// i32 absolute value; i32::MIN has none.
#[requires(x@ > i32::MIN@)]
#[ensures(result@ >= 0)]
#[ensures(result@ == x@ || result@ == -x@)]
pub fn abs(x: i32) -> i32 {
    if x < 0 { -x } else { x }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arithmetic() {
        assert_eq!(add_bounded(2, 3), 5);
        assert_eq!(add_checked(u32::MAX, 1), None);
        assert_eq!(add_checked(1, 2), Some(3));
        assert_eq!(add_saturating(u32::MAX, 7), u32::MAX);
        assert_eq!(add_wrapping(250, 10), 4);
        assert_eq!(midpoint(usize::MAX - 2, usize::MAX), usize::MAX - 1);
        assert_eq!(abs(-5), 5);
    }
}
