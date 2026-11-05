(* Inductive types, structural Fixpoints, proofs by induction. *)
From Stdlib Require Import Arith Lia List.
Import ListNotations.

Inductive tree (A : Type) : Type :=
| Leaf : tree A
| Node : tree A -> A -> tree A -> tree A.
Arguments Leaf {A}.
Arguments Node {A} _ _ _.

Fixpoint size {A} (t : tree A) : nat :=
  match t with Leaf => 0 | Node l _ r => S (size l + size r) end.

Fixpoint mirror {A} (t : tree A) : tree A :=
  match t with Leaf => Leaf | Node l x r => Node (mirror r) x (mirror l) end.

Fixpoint to_list {A} (t : tree A) : list A :=
  match t with Leaf => [] | Node l x r => to_list l ++ x :: to_list r end.

Fixpoint height {A} (t : tree A) : nat :=
  match t with Leaf => 0 | Node l _ r => S (Nat.max (height l) (height r)) end.

Lemma mirror_involutive {A} (t : tree A) : mirror (mirror t) = t.
Proof. induction t as [|l IHl x r IHr]; simpl; congruence. Qed.

Lemma size_mirror {A} (t : tree A) : size (mirror t) = size t.
Proof. induction t; simpl; lia. Qed.

Lemma length_to_list {A} (t : tree A) : length (to_list t) = size t.
Proof.
  induction t as [|l IHl x r IHr]; simpl; [reflexivity|].
  rewrite length_app; simpl; lia.
Qed.

Lemma to_list_mirror {A} (t : tree A) : to_list (mirror t) = rev (to_list t).
Proof.
  induction t as [|l IHl x r IHr]; simpl; [reflexivity|].
  rewrite IHl, IHr, rev_app_distr; simpl.
  now rewrite <- app_assoc.
Qed.

Lemma height_le_size {A} (t : tree A) : height t <= size t.
Proof. induction t; simpl; lia. Qed.

(* Injectivity and discrimination of constructors. *)
Lemma node_inj {A} (l1 r1 l2 r2 : tree A) x1 x2 :
  Node l1 x1 r1 = Node l2 x2 r2 -> x1 = x2 /\ l1 = l2.
Proof. intros H; injection H; auto. Qed.

Lemma leaf_not_node {A} (l r : tree A) x : Leaf <> Node l x r.
Proof. congruence. Qed.
