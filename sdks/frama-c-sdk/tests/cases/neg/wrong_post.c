/* NEGATIVE: the postcondition wrong_post is false (off by one).
   Expected: the goal typed_add_small_ensures_wrong_post is NOT proved. */
/*@ requires 0 <= a <= 1000 && 0 <= b <= 1000;
    assigns \nothing;
    ensures right_post: \result == a + b;
    ensures wrong_post: \result == a + b + 1;
*/
int add_small(int a, int b) { return a + b; }
