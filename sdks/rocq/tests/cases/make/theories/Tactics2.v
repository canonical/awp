(* Ltac2 and the decision procedures shipped with the standard library. *)
From Ltac2 Require Import Ltac2.
From Stdlib Require Import ZArith Lia Psatz Ring Field QArith Qfield Btauto.

Ltac2 rec count_hyps (hs : (ident * constr option * constr) list) :=
  match hs with [] => 0 | _ :: t => Int.add 1 (count_hyps t) end.

Lemma ltac2_example (P Q : Prop) : P -> Q -> P /\ Q.
Proof.
  intros p q.
  (if Int.equal (count_hyps (Control.hyps ())) 4 then () else
     Control.throw (Tactic_failure None)).
  split > [exact p | exact q].
Qed.

Set Default Proof Mode "Classic".

Lemma lia_z (x y : Z) : (x < y)%Z -> (2 * x + 1 < 2 * y)%Z.
Proof. lia. Qed.

Lemma nia_example (x : nat) : (x * x >= 0)%nat.
Proof. nia. Qed.

Lemma ring_example (a b : Z) : ((a + b) * (a + b) = a*a + 2*a*b + b*b)%Z.
Proof. ring. Qed.

Lemma field_example (q : Q) : ~ (q == 0)%Q -> (q / q == 1)%Q.
Proof. intros H. field; assumption. Qed.

Lemma btauto_example (a b : bool) : orb (andb a b) (negb a) = orb b (negb a).
Proof. btauto. Qed.

Lemma tauto_example (P Q : Prop) : (P -> Q) -> ~ Q -> ~ P.
Proof. tauto. Qed.

Lemma firstorder_example (A : Type) (P : A -> Prop) (a : A) :
  (forall x, P x) -> exists y, P y.
Proof. firstorder. Qed.

(* Kernel reduction machines: vm_compute, and native_compute (which falls
   back to the VM when the native compiler is not configured). *)
Lemma vm_example : (2 ^ 100 mod 7 = 2)%Z.
Proof. vm_compute. reflexivity. Qed.

Lemma native_example : (3 ^ 50 mod 11 = 1)%Z.
Proof. native_compute. reflexivity. Qed.
