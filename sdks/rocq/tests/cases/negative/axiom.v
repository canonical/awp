(* EXPECT-OK: Axioms:(.|\n)*cheat(.|\n)*Axioms:(.|\n)*classic *)
(* A smuggled axiom, and the excluded middle from Stdlib's Classical:
   Print Assumptions lists both. *)
From Stdlib Require Import Classical.
Axiom cheat : forall P : Prop, P.
Theorem anything : 0 = 1.
Proof. apply cheat. Qed.
Print Assumptions anything.
Lemma em (P : Prop) : P \/ ~ P.
Proof. apply classic. Qed.
Print Assumptions em.
