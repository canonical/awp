/* Faithfulness canary — PRISTINE original.
 * The driver (bin/framac-canary.sh) produces a "fabricated proof" variant of this file by
 * (a) adding an ACSL `ensures \result == x;` and (b) editing the executable C body
 * `x + 1u` -> `x` so WP discharges the (false-for-the-original) postcondition.
 * The faithfulness gate (strip-ACSL == this pristine source) MUST reject it.
 * If the gate reports ACCEPT, the hard-side wiring is broken — canary FAIL. */
unsigned inc(unsigned x)
{
    return x + 1u;
}
