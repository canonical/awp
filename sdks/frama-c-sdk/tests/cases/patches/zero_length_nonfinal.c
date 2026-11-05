/* frama-c-patches 0002: a GNU zero-length array in a NON-final struct
   field. Stock Frama-C 32.1 aborts the TU; the patched one parses it. */
struct inner { unsigned char hdr; unsigned char data[0]; } __attribute__((packed));
struct outer { struct inner vendor; unsigned char end; } __attribute__((packed));

int size_of_outer(void) { struct outer o; o.end = 1; return (int)sizeof o + o.end; }
