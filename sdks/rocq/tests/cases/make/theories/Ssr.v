(* The ssreflect tactic language bundled with the standard library. *)
From Stdlib Require Import ssreflect ssrfun ssrbool.
From Stdlib Require Import Arith List.
From AutoWP Require Import Trees.
Import ListNotations.

Lemma size_mirror_ssr {A} (t : tree A) : size (mirror t) = size t.
Proof.
  elim: t => [|l IHl x r IHr] //=.
  by rewrite IHl IHr Nat.add_comm.
Qed.

Lemma andb_swap (a b : bool) : a && b -> b && a.
Proof. by case: a; case: b. Qed.

Lemma andP_example (a b : bool) : a && b -> a.
Proof. by move=> /andP []. Qed.

Lemma rev_involutive_ssr (A : Type) (l : list A) : rev (rev l) = l.
Proof.
  elim: l => [|x l IH] //=.
  by rewrite rev_app_distr IH.
Qed.

Lemma have_example (n : nat) : n + 0 = n.
Proof.
  have H : forall m, m + 0 = m by elim=> [|m IH] //=; rewrite IH.
  exact: H.
Qed.
