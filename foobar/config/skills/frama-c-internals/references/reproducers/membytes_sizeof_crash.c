extern int tbl[];
int *g(void){ return &tbl[0]; }

/* -wp-model bytes: Failure "Sizeof unknown-size array" -> wp aborted (MemBytes.protected_sizeof_object
   does not guard the unknown-size C_array case that Ctypes.sizeof_object raises on).
   Typed: Warning "Undefined array-size" (recoverable) -> 2/2. See REPORT-membytes-sizeof.md. */
