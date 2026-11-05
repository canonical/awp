-- Compiles with a warning; the axiom audit must expose `sorryAx`.
theorem cheat (n : Nat) : n = n + 1 := by sorry

theorem uses_cheat : 0 = 1 := cheat 0

#print axioms uses_cheat
