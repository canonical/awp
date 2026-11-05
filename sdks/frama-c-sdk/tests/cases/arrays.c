/* Loops over arrays: invariants, loop assigns, variants, -wp-rte.
   Expected: every goal proved (alt-ergo,z3). */
#include <stddef.h>

/*@ requires n > 0;
    requires \valid_read(a + (0 .. n-1));
    assigns \nothing;
    ensures 0 <= \result < n;
    ensures \forall integer k; 0 <= k < n ==> a[k] <= a[\result];
*/
int max_index(const int *a, int n)
{
    int m = 0;
    /*@ loop invariant 1 <= i <= n;
        loop invariant 0 <= m < i;
        loop invariant \forall integer k; 0 <= k < i ==> a[k] <= a[m];
        loop assigns i, m;
        loop variant n - i;
    */
    for (int i = 1; i < n; i++)
        if (a[i] > a[m])
            m = i;
    return m;
}

/*@ requires n >= 0;
    requires \valid_read(a + (0 .. n-1));
    assigns \nothing;
    behavior found:
      assumes \exists integer k; 0 <= k < n && a[k] == v;
      ensures 0 <= \result < n && a[\result] == v;
      ensures \forall integer k; 0 <= k < \result ==> a[k] != v;
    behavior not_found:
      assumes \forall integer k; 0 <= k < n ==> a[k] != v;
      ensures \result == -1;
    complete behaviors;
    disjoint behaviors;
*/
int linear_search(const int *a, int n, int v)
{
    /*@ loop invariant 0 <= i <= n;
        loop invariant \forall integer k; 0 <= k < i ==> a[k] != v;
        loop assigns i;
        loop variant n - i;
    */
    for (int i = 0; i < n; i++)
        if (a[i] == v)
            return i;
    return -1;
}

/*@ requires n >= 0;
    requires \valid_read(a + (0 .. n-1));
    requires sorted: \forall integer i, j; 0 <= i <= j < n ==> a[i] <= a[j];
    assigns \nothing;
    behavior found:
      assumes \exists integer k; 0 <= k < n && a[k] == v;
      ensures 0 <= \result < n && a[\result] == v;
    behavior not_found:
      assumes \forall integer k; 0 <= k < n ==> a[k] != v;
      ensures \result == -1;
    complete behaviors;
    disjoint behaviors;
*/
int binary_search(const int *a, int n, int v)
{
    int lo = 0, hi = n - 1;
    /*@ loop invariant 0 <= lo && hi < n;
        loop invariant \forall integer k; 0 <= k < n && a[k] == v ==> lo <= k <= hi;
        loop assigns lo, hi;
        loop variant hi - lo;
    */
    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;   /* no overflow, unlike (lo + hi) / 2 */
        if (a[mid] == v)
            return mid;
        if (a[mid] < v)
            lo = mid + 1;
        else
            hi = mid - 1;
    }
    return -1;
}

/*@ requires \valid(s + (0 .. n-1));
    assigns s[0 .. n-1];
    ensures \forall integer k; 0 <= k < n ==> s[k] == c;
    ensures \result == s;
*/
char *my_memset(char *s, char c, size_t n)
{
    /*@ loop invariant 0 <= i <= n;
        loop invariant \forall integer k; 0 <= k < i ==> s[k] == c;
        loop assigns i, s[0 .. n-1];
        loop variant n - i;
    */
    for (size_t i = 0; i < n; i++)
        s[i] = c;
    return s;
}

/*@ requires n >= 0;
    requires \valid_read(a + (0 .. n-1));
    requires \forall integer k; 0 <= k < n ==> 0 <= a[k] <= 1000;
    requires n <= 1000;
    assigns \nothing;
    ensures 0 <= \result <= 1000 * n;
*/
int sum_bounded(const int *a, int n)
{
    int s = 0;
    /*@ loop invariant 0 <= i <= n;
        loop invariant 0 <= s <= 1000 * i;
        loop assigns i, s;
        loop variant n - i;
    */
    for (int i = 0; i < n; i++)
        s += a[i];
    return s;
}
