/* Soundness canary: `ensures \false` must stay RED under any model.
 * +cast: 2/3 (\false NOT proved) -> +cast is not trivially unsound. */
/*@ requires \valid((char*)p+(0..7)); ensures \false; */
void f(void *p, char *v){ *(char**)p = v; }
