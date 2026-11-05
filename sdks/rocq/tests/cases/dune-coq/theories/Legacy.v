(* Built by dune's deprecated Coq build language (coq.theory). *)
From Stdlib Require Import Arith Lia.
Lemma double_even (n : nat) : Nat.Even (2 * n).
Proof. now exists n. Qed.
Print Assumptions double_even.
