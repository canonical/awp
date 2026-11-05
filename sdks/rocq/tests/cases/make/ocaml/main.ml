(* Runs the code extracted from theories/Extract.v. *)
open Verified

let show l = String.concat " " (List.map string_of_int l)

let () =
  Printf.printf "isort: %s\n" (show (isort [5; 3; 9; 1; 3; 0]));
  Printf.printf "gcd: %d\n" (gcd 1071 462);
  Printf.printf "log2: %d\n" (log2 1000);
  Printf.printf "interleave: %s\n" (show (interleave [1; 3; 5] [2; 4]));
  let e = Plus (Const 2, Mult (Const 3, Const 4)) in
  Printf.printf "run: %s eval: %d\n" (show (run (compile e) [])) (eval e)
