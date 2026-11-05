/-! Inductive types and structural recursion, with proofs by induction. -/
namespace Algo

inductive Tree where
  | leaf : Tree
  | node : Tree → Nat → Tree → Tree
  deriving Repr, DecidableEq

namespace Tree

def size : Tree → Nat
  | leaf => 0
  | node l _ r => l.size + 1 + r.size

def mirror : Tree → Tree
  | leaf => leaf
  | node l x r => node r.mirror x l.mirror

def sum : Tree → Nat
  | leaf => 0
  | node l x r => l.sum + x + r.sum

theorem mirror_mirror (t : Tree) : t.mirror.mirror = t := by
  induction t with
  | leaf => rfl
  | node l x r ihl ihr => simp [mirror, ihl, ihr]

theorem size_mirror (t : Tree) : t.mirror.size = t.size := by
  induction t with
  | leaf => rfl
  | node l x r ihl ihr => simp only [mirror, size, ihl, ihr]; omega

theorem sum_mirror (t : Tree) : t.mirror.sum = t.sum := by
  induction t <;> grind [mirror, sum]

end Tree

/-- A tiny expression language, its evaluator and a verified optimiser. -/
inductive Expr where
  | lit : Nat → Expr
  | var : String → Expr
  | add : Expr → Expr → Expr
  | mul : Expr → Expr → Expr
  deriving Repr

namespace Expr

def eval (env : String → Nat) : Expr → Nat
  | lit n => n
  | var x => env x
  | add a b => a.eval env + b.eval env
  | mul a b => a.eval env * b.eval env

/-- Constant folding plus the neutral elements `0 + e`, `e + 0`, `1 * e`, `e * 1`. -/
def simpAdd : Expr → Expr → Expr
  | lit a, lit b => lit (a + b)
  | lit 0, e => e
  | e, lit 0 => e
  | a, b => add a b

def simpMul : Expr → Expr → Expr
  | lit a, lit b => lit (a * b)
  | lit 1, e => e
  | e, lit 1 => e
  | a, b => mul a b

def opt : Expr → Expr
  | add a b => simpAdd a.opt b.opt
  | mul a b => simpMul a.opt b.opt
  | e => e

theorem eval_simpAdd (env : String → Nat) (a b : Expr) :
    (simpAdd a b).eval env = a.eval env + b.eval env := by
  unfold simpAdd; split <;> simp_all [eval]

theorem eval_simpMul (env : String → Nat) (a b : Expr) :
    (simpMul a b).eval env = a.eval env * b.eval env := by
  unfold simpMul; split <;> simp_all [eval]

theorem opt_correct (env : String → Nat) (e : Expr) : e.opt.eval env = e.eval env := by
  induction e with
  | lit n => rfl
  | var x => rfl
  | add a b iha ihb => simp [opt, eval_simpAdd, eval, iha, ihb]
  | mul a b iha ihb => simp [opt, eval_simpMul, eval, iha, ihb]

end Expr

/-- Facts closed by `decide` (kernel evaluation). -/
theorem squares_small : ∀ n : Fin 10, n.val * n.val < 100 := by decide

theorem bool_and_comm : ∀ a b : Bool, (a && b) = (b && a) := by decide

end Algo
