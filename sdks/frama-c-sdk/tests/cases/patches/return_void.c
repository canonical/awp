/* cabs2cil-c23-auto fix 2: `return <void expression>;` in a void
   function (C11 6.8.6.4). Stock Frama-C 32.1 rejects it. */
int counter;
void bump(void) { counter++; }
void bump_wrapper(void) { return bump(); }
