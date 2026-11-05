(* EXPECT-FAIL: Unable to unify "x :: l" with "l \+\+ \[x\]" *)
(* A false universal statement over lists, attempted by induction. *)
From Stdlib Require Import List Lia.
Import ListNotations.
Lemma bad (l : list nat) : rev l = l.
Proof. induction l as [|x l IH]; simpl; [reflexivity|]. rewrite IH. reflexivity. Qed.
