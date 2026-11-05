(* EXPECT-FAIL: Unable to unify "y :: l" with "x :: y :: l" *)
(* A mutant of Sort.insert that drops duplicates: the same proof script
   as the correct insertion sort must now fail on the permutation. *)
From Stdlib Require Import Arith Lia List.
From Stdlib Require Import Sorting.Permutation.
Import ListNotations.
Fixpoint insert (x : nat) (l : list nat) : list nat :=
  match l with
  | [] => [x]
  | y :: l' => if x <? y then x :: y :: l'
               else if x =? y then l else y :: insert x l'
  end.
Lemma insert_perm x l : Permutation (x :: l) (insert x l).
Proof.
  induction l as [|y l IH]; simpl; [reflexivity|].
  destruct (x <? y); [reflexivity|].
  destruct (x =? y); [reflexivity|].
  eapply perm_trans; [apply perm_swap|]. now apply perm_skip.
Qed.
