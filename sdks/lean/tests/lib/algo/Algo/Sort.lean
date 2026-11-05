/-! A verified insertion sort: the result is sorted and a permutation of the input. -/
namespace Algo

def insert (x : Nat) : List Nat → List Nat
  | [] => [x]
  | y :: ys => if x ≤ y then x :: y :: ys else y :: insert x ys

def isort : List Nat → List Nat
  | [] => []
  | x :: xs => insert x (isort xs)

abbrev Sorted (l : List Nat) : Prop := List.Pairwise (· ≤ ·) l

theorem insert_perm (x : Nat) (l : List Nat) : List.Perm (insert x l) (x :: l) := by
  induction l with
  | nil => exact List.Perm.refl _
  | cons y ys ih =>
    unfold insert
    split
    · exact List.Perm.refl _
    · exact List.Perm.trans (List.Perm.cons y ih) (List.Perm.swap x y ys)

theorem isort_perm : ∀ l, List.Perm (isort l) l
  | [] => List.Perm.nil
  | x :: xs => (insert_perm x (isort xs)).trans ((isort_perm xs).cons x)

theorem mem_insert {x z : Nat} {l : List Nat} : z ∈ insert x l ↔ z = x ∨ z ∈ l := by
  rw [(insert_perm x l).mem_iff]
  simp

theorem insert_sorted (x : Nat) : ∀ l, Sorted l → Sorted (insert x l)
  | [], _ => by simp [insert]
  | y :: ys, h => by
    have h := List.pairwise_cons.1 h
    unfold insert
    split
    · next hxy =>
      refine List.pairwise_cons.2 ⟨?_, List.pairwise_cons.2 h⟩
      intro z hz
      rcases List.mem_cons.1 hz with rfl | hz
      · exact hxy
      · exact Nat.le_trans hxy (h.1 z hz)
    · next hxy =>
      refine List.pairwise_cons.2 ⟨?_, insert_sorted x ys h.2⟩
      intro z hz
      rcases mem_insert.1 hz with rfl | hz
      · omega
      · exact h.1 z hz

theorem isort_sorted : ∀ l, Sorted (isort l)
  | [] => List.Pairwise.nil
  | x :: xs => insert_sorted x _ (isort_sorted xs)

theorem isort_length (l : List Nat) : (isort l).length = l.length :=
  (isort_perm l).length_eq

/-- The specification, packaged: sorted and a permutation. -/
theorem isort_correct (l : List Nat) : Sorted (isort l) ∧ List.Perm (isort l) l :=
  ⟨isort_sorted l, isort_perm l⟩

theorem isort_idem (l : List Nat) : isort (isort l) = isort l := by
  -- a sorted list is a fixed point of insertion sort
  have key : ∀ l, Sorted l → isort l = l := by
    intro l hl
    induction l with
    | nil => rfl
    | cons x xs ih =>
      have hl := List.pairwise_cons.1 hl
      simp only [isort, ih hl.2]
      cases xs with
      | nil => rfl
      | cons y ys => simp [insert, hl.1 y (by simp)]
  exact key _ (isort_sorted l)

example : isort [5, 2, 8, 1, 9, 3] = [1, 2, 3, 5, 8, 9] := by decide

end Algo
