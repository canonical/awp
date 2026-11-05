(* EXPECT-FAIL: The term "\[1\]" has type "list nat" while it is expected to have type "nat" *)
From Stdlib Require Import List.
Import ListNotations.
Definition y : nat := Nat.add 1 [1].
