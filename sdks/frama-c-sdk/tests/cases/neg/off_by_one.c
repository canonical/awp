/* NEGATIVE: the loop writes s[n], one past the valid range.
   Expected: an RTE memory-access goal (rte_mem_access) is NOT proved. */
/*@ requires n >= 0 && \valid(s + (0 .. n-1));
    assigns s[0 .. n-1];
*/
void zero(char *s, int n)
{
    /*@ loop invariant 0 <= i <= n + 1;
        loop assigns i, s[0 .. n];
        loop variant n - i + 1;
    */
    for (int i = 0; i <= n; i++)
        s[i] = 0;
}
