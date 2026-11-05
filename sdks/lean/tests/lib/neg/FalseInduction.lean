-- Must fail: a false statement "proved" by induction and simp leaves goals open.
def double : Nat → Nat
  | 0 => 0
  | n + 1 => double n + 2

theorem bad (n : Nat) : double n = n + 1 := by
  induction n with
  | zero => simp [double]
  | succ n ih => simp [double, ih]
