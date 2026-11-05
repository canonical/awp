import Algo

def main (args : List String) : IO UInt32 := do
  let ns := args.filterMap String.toNat?
  if ns.length != args.length then
    IO.eprintln "usage: algo <nat>..."
    return 2
  let sorted := Algo.isort ns
  IO.println (" ".intercalate (sorted.map toString))
  IO.println s!"log2'(1000) = {Algo.log2' 1000}, gcd'(84, 36) = {Algo.gcd' 84 36}"
  return 0
