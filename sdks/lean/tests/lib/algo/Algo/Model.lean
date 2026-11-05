/-! A verified model in the auto-wp style: a bounded FIFO as a state machine, an invariant
proved inductive over every reachable state, and a refinement of the abstract queue. -/
namespace Algo.Model

structure St where
  cap   : Nat
  items : List Nat
  deriving Repr

inductive Op where
  | push (v : Nat)
  | pop
  deriving Repr

/-- Invariant: the queue never exceeds its capacity. -/
def Inv (s : St) : Prop := s.items.length ≤ s.cap

/-- One step; a push on a full queue and a pop on an empty one are no-ops (the C code
returns an error code there). -/
def step (s : St) : Op → St
  | .push v => if s.items.length < s.cap then { s with items := s.items ++ [v] } else s
  | .pop => { s with items := s.items.drop 1 }

def run (s : St) : List Op → St
  | [] => s
  | o :: os => run (step s o) os

inductive Reachable (cap : Nat) : St → Prop
  | init : Reachable cap ⟨cap, []⟩
  | step {s} (o : Op) : Reachable cap s → Reachable cap (step s o)

theorem step_cap (s : St) (o : Op) : (step s o).cap = s.cap := by
  cases o <;> simp only [step] <;> split <;> rfl

theorem step_inv (s : St) (o : Op) (h : Inv s) : Inv (step s o) := by
  unfold Inv at *
  cases o with
  | push v =>
    simp only [step]
    split
    · simp; omega
    · exact h
  | pop => simp only [step, List.length_drop]; omega

theorem reachable_inv (cap : Nat) (s : St) (h : Reachable cap s) : Inv s := by
  induction h with
  | init => simp [Inv]
  | step o _ ih => exact step_inv _ o ih

theorem run_inv (s : St) (os : List Op) (h : Inv s) : Inv (run s os) := by
  induction os generalizing s with
  | nil => exact h
  | cons o os ih => exact ih _ (step_inv s o h)

/-- FIFO order: what is pushed into an empty queue of room is what is popped first. -/
theorem push_pop_fifo (cap v : Nat) (hc : 0 < cap) :
    (step (step ⟨cap, []⟩ (.push v)) .pop).items = [] ∧
    (step ⟨cap, []⟩ (.push v)).items.head? = some v := by
  simp [step, hc]

end Algo.Model
