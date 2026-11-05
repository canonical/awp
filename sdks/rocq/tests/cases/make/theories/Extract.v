(* Extraction to OCaml of the verified functions; ocaml/main.ml runs them. *)
From Stdlib Require Import Extraction ExtrOcamlBasic ExtrOcamlNatInt.
From AutoWP Require Import Sort Compiler Recursion Trees.

Extraction Language OCaml.
Set Extraction Output Directory "ocaml".
Extraction "verified.ml" isort gcd log2 interleave compile run eval cfold
  mirror to_list.
