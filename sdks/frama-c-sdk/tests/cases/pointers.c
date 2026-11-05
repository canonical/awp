/* Pointers: \valid, \separated, assigns, calls.
   Expected: every goal proved (alt-ergo,z3). */
#include <limits.h>

/*@ requires \valid(a) && \valid(b);
    assigns *a, *b;
    ensures *a == \old(*b) && *b == \old(*a);
*/
void swap(int *a, int *b)
{
    int t = *a;
    *a = *b;
    *b = t;
}

/*@ assigns \nothing;
    ensures \result == 1;
*/
int use_swap(void)
{
    int x = 1, y = 2;
    swap(&x, &y);
    return y;
}

/*@ requires \valid(p) && \valid_read(q);
    requires \separated(p, q);
    requires *p < INT_MAX;
    assigns *p;
    ensures *p == \old(*p) + 1;
    ensures *q == \old(*q);
*/
void incr_first(int *p, const int *q)
{
    *p = *p + 1;
}

/*@ requires n >= 0;
    requires \valid(dst + (0 .. n-1));
    requires \valid_read(src + (0 .. n-1));
    requires \separated(dst + (0 .. n-1), src + (0 .. n-1));
    assigns dst[0 .. n-1];
    ensures \forall integer k; 0 <= k < n ==> dst[k] == src[k];
*/
void copy(int *dst, const int *src, int n)
{
    /*@ loop invariant 0 <= i <= n;
        loop invariant \forall integer k; 0 <= k < i ==> dst[k] == src[k];
        loop assigns i, dst[0 .. n-1];
        loop variant n - i;
    */
    for (int i = 0; i < n; i++)
        dst[i] = src[i];
}

struct point { int x; int y; };

/*@ requires \valid(p);
    requires INT_MIN < p->x && INT_MIN < p->y;
    assigns p->x, p->y;
    ensures p->x == -\old(p->x) && p->y == -\old(p->y);
*/
void negate(struct point *p)
{
    p->x = -p->x;
    p->y = -p->y;
}
