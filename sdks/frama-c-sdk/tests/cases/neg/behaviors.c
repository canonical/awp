/* NEGATIVE: the behaviors miss x == 0 (not complete) and overlap on
   x == 5 (not disjoint).
   Expected: complete_behaviors and disjoint_behaviors goals NOT proved. */
/*@ assigns \nothing;
    behavior neg:
      assumes x < 0;
      ensures \result == -1;
    behavior pos:
      assumes x > 0;
      ensures \result == 1;
    complete behaviors;
*/
int sign(int x) { return x < 0 ? -1 : (x > 0 ? 1 : 0); }

/*@ assigns \nothing;
    behavior small:
      assumes x <= 5;
      ensures \result <= 6;
    behavior large:
      assumes x >= 5;
      ensures \result >= 6;
    disjoint behaviors;
*/
int succ(int x) { return x < 100 ? x + 1 : 100; }
