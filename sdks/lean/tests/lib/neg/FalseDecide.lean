-- Must fail: a false closed proposition; `decide` evaluates it to `false`.
theorem bad : 2 + 2 = 5 := by decide
