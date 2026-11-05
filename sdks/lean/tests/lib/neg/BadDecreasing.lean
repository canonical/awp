-- Must fail: the given measure does not decrease.
def up (n : Nat) : Nat := if n = 0 then 0 else up (n + 1)
termination_by n
decreasing_by omega
