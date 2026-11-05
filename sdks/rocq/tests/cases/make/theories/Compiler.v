(* A verified compiler from arithmetic expressions to a stack machine. *)
From Stdlib Require Import Arith Lia List.
Import ListNotations.

Inductive expr : Type :=
| Const (n : nat)
| Plus (a b : expr)
| Mult (a b : expr).

Fixpoint eval (e : expr) : nat :=
  match e with
  | Const n => n
  | Plus a b => eval a + eval b
  | Mult a b => eval a * eval b
  end.

Inductive instr : Type := IPush (n : nat) | IAdd | IMul.

Fixpoint compile (e : expr) : list instr :=
  match e with
  | Const n => [IPush n]
  | Plus a b => compile a ++ compile b ++ [IAdd]
  | Mult a b => compile a ++ compile b ++ [IMul]
  end.

Fixpoint run (p : list instr) (s : list nat) : list nat :=
  match p with
  | [] => s
  | IPush n :: p' => run p' (n :: s)
  | IAdd :: p' =>
      match s with y :: x :: s' => run p' (x + y :: s') | _ => run p' s end
  | IMul :: p' =>
      match s with y :: x :: s' => run p' (x * y :: s') | _ => run p' s end
  end.

Lemma compile_correct_gen e p s :
  run (compile e ++ p) s = run p (eval e :: s).
Proof.
  revert p s; induction e as [n|a IHa b IHb|a IHa b IHb]; intros p s;
    simpl; auto; rewrite <- !app_assoc, IHa, IHb; reflexivity.
Qed.

Theorem compile_correct e : run (compile e) [] = [eval e].
Proof. rewrite <- (app_nil_r (compile e)), compile_correct_gen. reflexivity. Qed.

(* A constant folder, proved semantics-preserving. *)
Fixpoint cfold (e : expr) : expr :=
  match e with
  | Const n => Const n
  | Plus a b =>
      match cfold a, cfold b with
      | Const x, Const y => Const (x + y)
      | a', b' => Plus a' b'
      end
  | Mult a b =>
      match cfold a, cfold b with
      | Const x, Const y => Const (x * y)
      | a', b' => Mult a' b'
      end
  end.

Theorem cfold_correct e : eval (cfold e) = eval e.
Proof.
  induction e as [n|a IHa b IHb|a IHa b IHb]; simpl; auto;
    destruct (cfold a), (cfold b); simpl in *; congruence.
Qed.

Example run_example :
  run (compile (Plus (Const 2) (Mult (Const 3) (Const 4)))) [] = [14].
Proof. reflexivity. Qed.
