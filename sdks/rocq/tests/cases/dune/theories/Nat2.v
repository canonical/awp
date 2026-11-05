(* A theory built by dune's rocq.theory stanza. *)
From Stdlib Require Import Arith Lia List.
Import ListNotations.

Fixpoint sum (l : list nat) : nat :=
  match l with [] => 0 | x :: l' => x + sum l' end.

Fixpoint upto (n : nat) : list nat :=
  match n with 0 => [] | S p => upto p ++ [S p] end.

Lemma sum_app l1 l2 : sum (l1 ++ l2) = sum l1 + sum l2.
Proof. induction l1; simpl; lia. Qed.

Theorem gauss n : 2 * sum (upto n) = n * (n + 1).
Proof.
  induction n as [|n IH]; simpl; [reflexivity|].
  rewrite sum_app; simpl. nia.
Qed.
