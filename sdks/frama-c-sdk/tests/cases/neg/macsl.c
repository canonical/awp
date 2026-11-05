/* NEGATIVE macsl: tamper() writes secret_reg, which the meta-property
   no_tamper forbids for every function but set_secret.
   Expected: the macsl assertion no_tamper in tamper is NOT proved, while
   the one in set_pub is proved. */
int secret_reg;
int pub;

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

/*@ assigns secret_reg; */
void tamper(int v) { secret_reg = v; }
