-- Must fail: grind cannot prove a false goal.
theorem bad (a b : Nat) (h : a < b) : b < a := by grind
