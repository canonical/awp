(* Non-structural recursion: Function with a measure and with a
   well-founded relation, Program Fixpoint, functional induction. *)
From Stdlib Require Import Arith Lia List Wf_nat Recdef FunInd.
From Stdlib Require Import Program.Wf.
Import ListNotations.

(* Euclid's algorithm, recursive on [a mod b], which is not a subterm. *)
Function gcd (a b : nat) {measure (fun n => n) b} : nat :=
  match b with
  | 0 => a
  | S b' => gcd (S b') (a mod S b')
  end.
Proof. intros; apply Nat.mod_upper_bound; lia. Defined.

Lemma divide_from_mod g a b :
  b <> 0 -> Nat.divide g b -> Nat.divide g (a mod b) -> Nat.divide g a.
Proof.
  intros Hb H1 H2. rewrite (Nat.div_mod a b Hb).
  apply Nat.divide_add_r; [now apply Nat.divide_mul_l | exact H2].
Qed.

Lemma gcd_divides a b : Nat.divide (gcd a b) a /\ Nat.divide (gcd a b) b.
Proof.
  functional induction (gcd a b).
  - split; [apply Nat.divide_refl | apply Nat.divide_0_r].
  - destruct IHn as [H1 H2]. split; [|exact H1].
    apply (divide_from_mod _ _ (S b')); [lia | exact H1 | exact H2].
Qed.

Lemma gcd_greatest a b k :
  Nat.divide k a -> Nat.divide k b -> Nat.divide k (gcd a b).
Proof.
  functional induction (gcd a b); intros Ha Hb; [exact Ha|].
  match goal with IH : _ -> _ -> Nat.divide k _ |- _ => apply IH end;
    [exact Hb|].
  rewrite Nat.Div0.mod_eq.
  apply Nat.divide_sub_r; [exact Ha | now apply Nat.divide_mul_l].
Qed.

(* The kernel of auto-wp's gcd escalation: a goal SMT cannot close
   (a variable divisor, no trigger), closed here by induction. *)
Theorem gcd_is_greatest a b k :
  0 < a -> 0 < k -> Nat.divide k a -> Nat.divide k b -> k <= gcd a b.
Proof.
  intros Ha Hk Hka Hkb. apply Nat.divide_pos_le.
  - destruct (gcd_divides a b) as [[c Hc] _].
    destruct (gcd a b); lia.
  - now apply gcd_greatest.
Qed.

Theorem gcd_agrees a b : gcd a b = Nat.gcd a b.
Proof.
  symmetry; apply Nat.gcd_unique.
  - apply gcd_divides.
  - apply gcd_divides.
  - intros q Ha Hb. now apply gcd_greatest.
Qed.

(* Function over a well-founded relation given explicitly. *)
Function log2 (n : nat) {wf lt n} : nat :=
  match n with
  | 0 => 0
  | 1 => 0
  | S (S m) => S (log2 (Nat.div2 (S (S m))))
  end.
Proof.
  - intros; apply Nat.lt_div2; lia.
  - exact lt_wf.
Defined.

Lemma log2_spec n : 1 <= n -> 2 ^ log2 n <= n.
Proof.
  functional induction (log2 n); intros H; [lia | simpl; lia |].
  (* lia does not see through Nat.div2: go to division by 2. *)
  assert (1 <= Nat.div2 (S (S m))) as Hd
    by (simpl; apply le_n_S, Nat.le_0_l).
  match goal with IH : _ -> 2 ^ _ <= _ |- _ => specialize (IH Hd) end.
  rewrite Nat.pow_succ_r', Nat.div2_div in *.
  pose proof (Nat.Div0.mul_div_le (S (S m)) 2).
  lia.
Qed.

(* Program Fixpoint with a measure, obligations discharged by lia. *)
Program Fixpoint interleave (l1 l2 : list nat)
  {measure (length l1 + length l2)} : list nat :=
  match l1 with
  | [] => l2
  | x :: l1' => x :: interleave l2 l1'
  end.
Next Obligation. intros; subst; simpl; lia. Qed.

(* Program with subset types. *)
Program Definition pred_pos (n : {n : nat | 0 < n})
  : {m : nat | S m = proj1_sig n} := pred (proj1_sig n).
Next Obligation. lia. Qed.

(* Explicit well-founded recursion with Fix and its unfolding lemma. *)
Definition countdown : nat -> list nat :=
  Fix lt_wf (fun _ => list nat)
    (fun n rec =>
       match n as k return (forall m, m < k -> list nat) -> list nat with
       | 0 => fun _ => [0]
       | S p => fun r => S p :: r p (Nat.lt_succ_diag_r p)
       end rec).

Lemma countdown_eq n :
  countdown n = match n with 0 => [0] | S p => S p :: countdown p end.
Proof.
  unfold countdown at 1. rewrite Init.Wf.Fix_eq.
  - destruct n; reflexivity.
  - intros [|k] f g Hfg; [reflexivity|]. cbn. f_equal. apply Hfg.
Qed.

Lemma countdown_length n : length (countdown n) = S n.
Proof.
  induction n as [|n IH]; rewrite countdown_eq; simpl; [reflexivity|].
  now rewrite IH.
Qed.
