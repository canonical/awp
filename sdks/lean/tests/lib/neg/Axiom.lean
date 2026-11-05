-- Compiles without any error; only the axiom audit catches the smuggled axiom.
axiom smuggled : ∀ n : Nat, n = n + 1

theorem looks_fine : 0 = 1 := smuggled 0

#print axioms looks_fine
