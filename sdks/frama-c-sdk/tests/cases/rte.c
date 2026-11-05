/* -wp-rte runtime-error goals: overflow, division, shifts, array bounds.
   Expected: every goal proved; the RTE goals exist (rte_* in the goal names). */
#include <limits.h>

int table[16];

/*@ requires 0 <= i < 16;
    assigns \nothing;
    ensures \result == table[i];
*/
int get(int i) { return table[i]; }

/*@ requires b != 0;
    requires !(a == INT_MIN && b == -1);
    assigns \nothing;
    ensures \result == a / b;
*/
int safe_div(int a, int b) { return a / b; }

/*@ requires x > INT_MIN;
    assigns \nothing;
    ensures \result >= 0;
    ensures \result == x || \result == -x;
*/
int abs_int(int x) { return x < 0 ? -x : x; }

/*@ requires 0 <= lo <= hi;
    assigns \nothing;
    ensures lo <= \result <= hi;
*/
int midpoint(int lo, int hi) { return lo + (hi - lo) / 2; }

/*@ requires 0 <= a <= INT_MAX - b;
    requires 0 <= b;
    assigns \nothing;
    ensures \result == a + b;
*/
int add_nonneg(int a, int b) { return a + b; }

/*@ requires 0 <= n < 32;
    assigns \nothing;
*/
unsigned shl(unsigned x, int n) { return x << n; }   /* the shift amount is an RTE goal */

/*@ assigns \nothing;
    ensures \result == (unsigned)(a + b) ;
*/
unsigned wrap_add(unsigned a, unsigned b) { return a + b; }  /* unsigned wraps: no RTE */
