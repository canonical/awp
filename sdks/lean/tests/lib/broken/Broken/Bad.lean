import Broken.Good
namespace Broken
-- Must make `lake build` fail: a type error in a dependent module.
theorem bad (n : Nat) : n + 1 = n := Broken.good n
end Broken
