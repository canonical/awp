/* NEGATIVE: a + b may overflow (no precondition bounds a and b).
   Expected: the RTE goal rte_signed_overflow is NOT proved. */
/*@ assigns \nothing;
    ensures \result == a + b;
*/
int add(int a, int b) { return a + b; }
