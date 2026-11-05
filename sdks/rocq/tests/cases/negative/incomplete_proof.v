(* EXPECT-FAIL: Attempt to save an incomplete proof *)
(* Qed with a goal left open. *)
Lemma bad (P Q : Prop) : P -> P /\ Q.
Proof. intros p. split. exact p. Qed.
