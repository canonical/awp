/-! Well-founded recursion with explicit termination proofs. -/
namespace Algo

/-- Integer base-2 logarithm by repeated halving: recursion on `n / 2`, not structural. -/
def log2' (n : Nat) : Nat :=
  if h : n < 2 then 0 else 1 + log2' (n / 2)
termination_by n
decreasing_by omega

/-- Euclid's algorithm, terminating on the second argument. -/
def gcd' (a b : Nat) : Nat :=
  if _h : b = 0 then a else gcd' b (a % b)
termination_by b
decreasing_by exact Nat.mod_lt _ (by omega)

theorem pow_log2_le (n : Nat) (h : 1 ≤ n) : 2 ^ log2' n ≤ n := by
  unfold log2'
  split
  · simp; omega
  · have ih := pow_log2_le (n / 2) (by omega)
    rw [Nat.pow_add, Nat.pow_one]
    omega
termination_by n
decreasing_by omega

theorem gcd'_eq (a b : Nat) : gcd' a b = Nat.gcd a b := by
  unfold gcd'
  split
  · next h => subst h; simp
  · next h =>
    rw [gcd'_eq b (a % b), Nat.gcd_comm a b, Nat.gcd_rec b a, Nat.gcd_comm]
termination_by b
decreasing_by exact Nat.mod_lt _ (by omega)

theorem gcd'_dvd_left (a b : Nat) : gcd' a b ∣ a := by
  rw [gcd'_eq]; exact Nat.gcd_dvd_left a b

-- Well-founded definitions are irreducible for the kernel; prove through the spec, and
-- check the compiled code with `#guard_msgs`.
example : gcd' 84 36 = 12 := by rw [gcd'_eq]; decide

/-- info: 10 -/
#guard_msgs in
#eval log2' 1024

end Algo
