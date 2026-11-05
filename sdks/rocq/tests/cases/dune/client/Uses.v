(* A second theory depending on the first one. *)
From Stdlib Require Import Arith Lia.
From DuneLib Require Import Nat2.

Corollary gauss_10 : sum (upto 10) = 55.
Proof. reflexivity. Qed.

Corollary sum_upto_even n : Nat.Even (n * (n + 1)).
Proof. exists (sum (upto n)). now rewrite <- gauss. Qed.

Print Assumptions sum_upto_even.
