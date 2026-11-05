/* Named behaviors with complete/disjoint clauses.
   Expected: every goal proved, including complete_behaviors and
   disjoint_behaviors goals. */

/*@ assigns \nothing;
    behavior neg:
      assumes x < 0;
      ensures \result == -1;
    behavior zero:
      assumes x == 0;
      ensures \result == 0;
    behavior pos:
      assumes x > 0;
      ensures \result == 1;
    complete behaviors;
    disjoint behaviors;
*/
int sign(int x)
{
    if (x < 0) return -1;
    if (x > 0) return 1;
    return 0;
}

/*@ requires \valid(p);
    requires lo <= hi;   // without it, clamp_high and clamp_low overlap
    assigns *p;
    behavior clamp_high:
      assumes *p > hi;
      ensures *p == hi;
    behavior clamp_low:
      assumes *p < lo;
      ensures *p == lo;
    behavior keep:
      assumes lo <= *p <= hi;
      ensures *p == \old(*p);
    complete behaviors;
    disjoint behaviors;
*/
void clamp(int *p, int lo, int hi)
{
    if (*p > hi) *p = hi;
    else if (*p < lo) *p = lo;
}
