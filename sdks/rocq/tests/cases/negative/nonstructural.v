(* EXPECT-FAIL: Recursive definition of log2 is ill-formed(.|\n)*Recursive call to log2 has principal argument *)
(* Recursion on div2 n, not a subterm of n: Fixpoint must refuse it. *)
Fixpoint log2 (n : nat) : nat :=
  match n with 0 | 1 => 0 | _ => S (log2 (Nat.div2 n)) end.
