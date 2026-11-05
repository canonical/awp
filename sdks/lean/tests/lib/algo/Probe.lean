import Algo.Sort
theorem probe_ok (l : List Nat) : (Algo.isort l).length = l.length := by
  exact (Algo.isort_perm l).length_eq
theorem probe_bad (n : Nat) : n + 1 = n := by
  omega
