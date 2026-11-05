(* EXPECT-FAIL: Tactic failure: +Cannot find witness *)
(* A false arithmetic lemma: lia must refuse it. *)
From Stdlib Require Import Lia.
Lemma bad (n : nat) : n + 1 <= n.
Proof. lia. Qed.
