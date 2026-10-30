# WS8a — boundary contract as a peer-owed obligation (worked demonstration)

The spec is N-4 in [`stride-gates.md`](./stride-gates.md): a trusted stub
(`verify_token`, `get_query_param`, storage, the clock) is not assumed — it becomes a **proof
obligation owed by the peer unit**, scheduled and discharged by the monitor's existing leaf-first
`ensures → requires` propagation. WS8a adds **no new mechanism**; it re-seats an assumption as a
contract. This file makes that concrete.

## The move

Before — the caller *assumes* the boundary (the residual is invisible):

```c
/* storage backend — trusted stub, no contract: "we assume fsync happened" */
int storage_write(const unsigned char *buf, size_t n);   /* declaration only */
int storage_ack(void);
```

After — the boundary is an **interface contract** the peer unit must satisfy. The monitor turns the
callee's proven `ensures` into the caller's `requires` (the same propagation it already does for leaf
units), so "trusted" becomes "owed and scheduled":

```c
/*@ // durability boundary: the ack may only claim success once the bytes are on stable storage.
  ghost int g_durable;                       // ghost: bytes flushed through fsync
  ghost int g_acked;                         // ghost: success reported to the peer

  requires \valid_read(buf + (0 .. n-1));
  assigns  g_durable;
  ensures  g_durable >= \old(g_durable);     // monotone: durability never regresses
*/
int storage_write(const unsigned char *buf, size_t n);

/*@ requires g_durable == 1;                 // <-- the OWED obligation: fsync-before-ack ordering
    assigns  g_acked;
    ensures  g_acked == 1;
*/
int storage_ack(void);
```

Now `storage_ack`'s `requires g_durable == 1` is a **goal at every call site**: the caller must prove
durability was established first. A code path that acks before flushing **fails WP** — the fsync-before-ack
ordering that was a silent assumption is now a discharged (or refuted) obligation.

## Two more canonical boundaries

- **Parser totality + non-aliasing** (the `get_query_param` / decoder stub):
  ```c
  /*@ requires \valid_read(in + (0 .. len-1));
      requires \separated(in + (0 .. len-1), out + (0 .. cap-1));   // non-aliasing, owed
      assigns  out[0 .. cap-1];
      ensures  \result == 0 || \result == -1;                       // TOTAL: never traps, never UB
  */
  int parse_param(const char *in, size_t len, char *out, size_t cap);
  ```
  The peer parser unit owes totality (no input traps) and output/input non-aliasing.

- **Authenticator** (the `verify_token` stub — ties to WS3): the contract is
  `ensures \result == 1 ==> authorized(current_principal, OP)` (the uninterpreted `authorized` from
  WS3/M-3), so a `\result == 1` return *binds an identity*, not merely "a check ran."

## How the monitor schedules it (no new gate)

This is the **leaf-first** schedule the monitor already runs (SKILL.md §scheduling):

1. The stub's contract is registered as the **callee `ensures`**.
2. At each call site, that `ensures` becomes the **caller's `requires`** — a WP goal.
3. The peer unit that *implements* the boundary is scheduled as a leaf; proving its `ensures`
   **discharges** the obligation. Until then it is an **honest owed obligation**, not a silent trust.

So in the crosswalk STRIDE ledger, the boundary's cell moves `TRUSTED → PROVED` exactly when the peer
unit's `ensures` is proven — never by assumption. A boundary still unimplemented stays `TRUSTED-PENDING`
(a named, owed residual), which is what the ratchet (`bin/ledger-ratchet.sh`) tracks. **No-blend holds:** the
green is the *ordering / totality / binding* property named in the contract, nothing more.
