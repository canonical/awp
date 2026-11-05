/* macsl (HAPPY) meta-property: no function but set_secret may write
   secret_reg (\writing context, write confinement).
   Expected: macsl instruments every write site with an assertion
   "no_tamper: meta: ...", and every goal is proved. */
int secret_reg;
int pub;
int log_buf[8];

/*@ happy \prop,
      \name(no_tamper),
      \targets(\diff(\ALL, {set_secret})),
      \context(\writing),
      \separated(\written, &secret_reg);
*/

/*@ assigns secret_reg; */
void set_secret(int v) { secret_reg = v; }

/*@ assigns pub; */
void set_pub(int v) { pub = v; }

/*@ requires 0 <= i < 8;
    assigns log_buf[i];
*/
void log_at(int i, int v) { log_buf[i] = v; }

/*@ requires \valid(p) && \separated(p, &secret_reg);
    assigns *p;
*/
void write_through(int *p, int v) { *p = v; }
