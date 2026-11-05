-- Must fail: no termination measure exists.
def loop (n : Nat) : Nat := loop (n + 1)
