(* EXPECT-OK: Axioms:(.|\n)*helper *)
(* Admitted is accepted by coqc, so the audit must reveal it: the theorem
   that uses it is not closed under the global context. *)
From Stdlib Require Import Arith.
Lemma helper (n : nat) : n * n >= n.
Admitted.
Theorem uses_helper : 3 * 3 >= 3.
Proof. apply helper. Qed.
Print Assumptions uses_helper.
