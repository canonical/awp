/* Soft-side canary — the TRIVIAL WITNESS for sort2.c's weak spec.
 * Same contract as sort2.c, but the body zero-fills instead of sorting. If WP STILL proves
 * `ordered` here (0 <= 0), the weak spec is satisfied by an artifact that throws the input
 * away — i.e. it is a valid-but-wrong-question contract. That WP-green-on-the-trivial-witness
 * is exactly what Gate C' / the disjoint completeness oracle must flag, and what WP alone
 * (green on both real and trivial bodies) cannot. */
/*@ requires \valid(a + (0..1));
  @ assigns a[0], a[1];
  @ ensures ordered: a[0] <= a[1];
  @*/
void sort2(int *a)
{
    a[0] = 0;
    a[1] = 0;
}
