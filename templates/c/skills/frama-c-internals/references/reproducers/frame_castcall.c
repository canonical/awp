#include <stddef.h>

/* callee assigns ONLY the byte(s) behind p, via a cast — the frame-defect trigger */
/*@ requires \valid((char*)p);
    assigns *(char*)p;
    ensures *(char*)p == 0; */
void zero_byte(void *p);

int test_sep(void) {
    int a = 7;
    int b = 99;
    zero_byte(&a);                 /* assigns only *(char*)&a */
    /*@ assert sep_true: b == 99; */   /* SOUND+COMPLETE: b framed -> must PROVE */
    return b;
}

int test_unsound(void) {
    int a = 7;
    zero_byte(&a);                 /* a's first byte set to 0 */
    /*@ assert bad_false: a == 7; */   /* a was modified -> FALSE -> must NOT prove */
    return a;
}
