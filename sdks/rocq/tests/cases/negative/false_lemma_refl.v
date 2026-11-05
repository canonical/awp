(* EXPECT-FAIL: Unable to unify "5" with "2 \+ 2" *)
(* 2 + 2 = 5 by computation must be refused. *)
Lemma bad : 2 + 2 = 5.
Proof. reflexivity. Qed.
