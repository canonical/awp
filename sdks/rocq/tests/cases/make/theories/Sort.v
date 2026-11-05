(* A small verified algorithm: insertion sort is sorted and a permutation. *)
From Stdlib Require Import Arith Lia List.
From Stdlib Require Import Sorting.Sorted Sorting.Permutation.
Import ListNotations.

Fixpoint insert (x : nat) (l : list nat) : list nat :=
  match l with
  | [] => [x]
  | y :: l' => if x <=? y then x :: y :: l' else y :: insert x l'
  end.

Fixpoint isort (l : list nat) : list nat :=
  match l with [] => [] | x :: l' => insert x (isort l') end.

Lemma insert_perm x l : Permutation (x :: l) (insert x l).
Proof.
  induction l as [|y l IH]; simpl; [reflexivity|].
  destruct (x <=? y); [reflexivity|].
  eapply perm_trans; [apply perm_swap|]. now apply perm_skip.
Qed.

Lemma isort_perm l : Permutation l (isort l).
Proof.
  induction l as [|x l IH]; simpl; [constructor|].
  eapply perm_trans; [apply perm_skip, IH | apply insert_perm].
Qed.

Lemma insert_sorted x l : Sorted le l -> Sorted le (insert x l).
Proof.
  induction 1 as [|y l Hs IH Hhd]; simpl; [repeat constructor|].
  destruct (Nat.leb_spec x y) as [Hxy|Hxy].
  - constructor; constructor; assumption.
  - constructor; [exact IH|].
    destruct l as [|z l']; simpl.
    + constructor; lia.
    + apply HdRel_inv in Hhd. destruct (x <=? z); constructor; lia.
Qed.

Lemma isort_sorted l : Sorted le (isort l).
Proof. induction l; simpl; [constructor | now apply insert_sorted]. Qed.

Theorem isort_correct l : Sorted le (isort l) /\ Permutation l (isort l).
Proof. split; [apply isort_sorted | apply isort_perm]. Qed.

Corollary isort_length l : length (isort l) = length l.
Proof. symmetry; apply Permutation_length, isort_perm. Qed.

Example isort_example : isort [3; 1; 2; 1] = [1; 1; 2; 3].
Proof. reflexivity. Qed.
