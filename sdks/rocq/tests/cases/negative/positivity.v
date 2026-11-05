(* EXPECT-FAIL: Non strictly positive occurrence of "bad" *)
(* A negative inductive would make the logic inconsistent. *)
Inductive bad : Type := C : (bad -> nat) -> bad.
