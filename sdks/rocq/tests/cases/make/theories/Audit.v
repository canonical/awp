(* Every main theorem must rest on no axiom at all. *)
From AutoWP Require Import Trees Compiler Sort Recursion Ssr Tactics2.

Print Assumptions Trees.to_list_mirror.
Print Assumptions Compiler.compile_correct.
Print Assumptions Compiler.cfold_correct.
Print Assumptions Sort.isort_correct.
Print Assumptions Recursion.gcd_is_greatest.
Print Assumptions Recursion.gcd_agrees.
Print Assumptions Recursion.log2_spec.
Print Assumptions Recursion.countdown_length.
Print Assumptions Ssr.size_mirror_ssr.
Print Assumptions Tactics2.ltac2_example.
Print Assumptions Tactics2.field_example.
Print Assumptions Recursion.interleave.
Print Assumptions Recursion.pred_pos.
