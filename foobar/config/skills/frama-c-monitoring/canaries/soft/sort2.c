/* Soft-side canary — REAL body with a deliberately WEAK ("valid-but-wrong-question") spec.
 * The contract asserts only `ordered` (a[0] <= a[1]) — NOT that the output is a permutation of
 * the input. WP discharges it (green). But a trivial witness (sort2_trivial.c: zero-fill) also
 * satisfies it, so the spec does not pin the intended property. WP alone cannot tell — only the
 * disjoint completeness oracle's trivial-witness probe (Gate C') catches it.
 * If the trivial witness does NOT also prove green, the spec was strong enough and the soft
 * canary would not fire — canary FAIL (the wiring that exercises the soft side is broken). */
/*@ requires \valid(a + (0..1));
  @ assigns a[0], a[1];
  @ ensures ordered: a[0] <= a[1];
  @*/
void sort2(int *a)
{
    if (a[0] > a[1]) {
        int t = a[0];
        a[0] = a[1];
        a[1] = t;
    }
}
