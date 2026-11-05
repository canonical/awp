(* EXPECT-FAIL: Recursive definition of loop is ill-formed *)
(* An explicit {struct n} on a call that is not on a subterm. *)
Fixpoint loop (n : nat) {struct n} : nat := loop n.
