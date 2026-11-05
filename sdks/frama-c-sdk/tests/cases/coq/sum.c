/* A lemma SMT cannot prove (it needs induction), discharged by a Coq
   script through WP's Coq support, then used by SMT for the function.
   The script is coq/lemma_sum_nonneg.v, copied into the WP session. */

/*@ axiomatic Sum {
      logic integer sum(integer n);
      axiom sum_zero: sum(0) == 0;
      axiom sum_succ: \forall integer n; n > 0 ==> sum(n) == sum(n - 1) + n;
    }
*/

/*@ lemma sum_nonneg: \forall integer n; n >= 0 ==> sum(n) >= 0; */

/*@ requires 0 <= n <= 1000;
    assigns \nothing;
    ensures \result == sum(n);
    ensures \result >= 0;
*/
int triangle(int n)
{
    int s = 0;
    /*@ loop invariant 0 <= i <= n;
        loop invariant s == sum(i);
        loop invariant s <= i * 1000;
        loop assigns i, s;
        loop variant n - i;
    */
    for (int i = 0; i < n; ) {
        i++;
        s += i;
    }
    return s;
}
