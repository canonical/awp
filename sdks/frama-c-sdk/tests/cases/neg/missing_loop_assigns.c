/* NEGATIVE: the loop writes s[...] but its loop assigns only lists i.
   Expected: the loop assigns goal (loop_assigns) is NOT proved. */
/*@ requires n >= 0 && \valid(s + (0 .. n-1));
    assigns s[0 .. n-1];
    ensures \forall integer k; 0 <= k < n ==> s[k] == 0;
*/
void zero(char *s, int n)
{
    /*@ loop invariant 0 <= i <= n;
        loop invariant \forall integer k; 0 <= k < i ==> s[k] == 0;
        loop assigns i;
        loop variant n - i;
    */
    for (int i = 0; i < n; i++)
        s[i] = 0;
}
