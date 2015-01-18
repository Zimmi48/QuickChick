Require Import QuickChick.

Require Import List seq ssreflect ssrbool ssrnat ZArith eqtype.
Import ListNotations.

(* Currenlty, these two have to be imported manually. Can we avoid this? *)
Import Gen GenComb. 

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

(* Small example with default arbitrary instances *)

Fixpoint remove (x : nat) (l : list nat) : list nat :=
  match l with
    | []   => []
    | h::t => if beq_nat h x then t else h :: remove x t
  end.

Definition removeP (x : nat) (l : list nat) :=
  ~~ (existsb (pred1 x) (remove x l)).

Definition test0 :=
  showResult (quickCheck removeP).

QuickCheck test0.

Definition prop_length (A : Type) (l : list A) :=
  (List.length l) <= 20.

Definition testLength :=
  showResult (quickCheck prop_length).

QuickCheck testLength.

(* Tree example showing custom datatypes *)

Inductive tree (A : Type) :=
| Leaf : tree A
| Node : A -> tree A -> tree A -> tree A.

Arguments Leaf {A}.
Arguments Node {A} _ _ _.

Fixpoint eq_tree (A : eqType) (t1 t2 : tree A) :=
  match t1, t2 with
  | Leaf, Leaf => true
  | Node x1 l1 r1, Node x2 l2 r2 => [&& x1 == x2, eq_tree l1 l2 & eq_tree r1 r2]
  | _, _ => false
  end.

Lemma eq_treeP (A : eqType) : Equality.axiom (@eq_tree A).
Proof.
  move=> t1 t2; apply/(iffP idP) => [|<-].
  elim: t1 t2 => [|x1 l1 IHl1 r1 IHr1] [|x2 l2 r2] //=.
    by case/and3P=> /eqP-> /IHl1-> /IHr1->.
    by elim: t1 => //= x ? -> ? ->; rewrite eqxx.
Qed.

Canonical tree_eqMixin (A : eqType) := EqMixin (@eq_treeP A).
Canonical tree_eqType (A : eqType) := Eval hnf in EqType (tree A) (tree_eqMixin A).

(* Step one: Write custom generators *)

Fixpoint gentreeS {A} (g : G A) (n : nat) : G (tree A) :=
  match n with
    | O => returnGen Leaf
    | S n' =>
      frequency (returnGen Leaf)
                 [(1, returnGen Leaf);
                   (n, liftGen3 Node g (gentreeS g n') (gentreeS g n'))]
  end.

Definition gentree {A : Type} (g : G A) : G (tree A) := 
  bindGen arbitrary (gentreeS g).


Instance arbtree {A} `{Arbitrary A} : Arbitrary (tree A) :=
{|
  arbitrary := gentree arbitrary;
  shrink t :=
      let fix shrinktree (t : tree A) :=
          match t with
            | Leaf => []
            | Node x l r => [l] ++ [r] ++
              map (fun x' => Node x' l r) (shrink x) ++
              map (fun l' => Node x l' r) (shrinktree l) ++
              map (fun r' => Node x l r') (shrinktree r)
          end
      in shrinktree t
|}.


Require Import String.
Open Scope string.

Instance showtree {A : Type} `{_ : Show A} : Show (tree A) :=
{|
  show t :=
    let fix showtree (t : tree A) :=
        match t with
          | Leaf => "Leaf"
          | Node x l r => "Node " ++ show x
                                  ++ " ( " ++ showtree l ++ " ) "
                                  ++ " ( " ++ showtree r ++ " ) "
        end
    in showtree t
|}.

Open Scope list.

(* Step 2: Use them for generation .. *)

(* Faulty mirror function *)
Fixpoint mirror {A : Type} (t : tree A) : tree A :=
  match t with
    | Leaf => Leaf
    | Node x l r => Node x (mirror l) (mirror l)
  end.
  
Definition mirrorK (t : tree nat) := mirror (mirror t) == t.
 
Definition testtree := showResult (quickCheck mirrorK).
 
QuickCheck testtree.
 
(* Step 3 : .. or prove them correct   *)

Fixpoint height {A} (t : tree A) :=
  match t with
    | Leaf => 0
    | Node a t1 t2 =>
      (maxn (height t1) (height t2)) + 1
  end.

Lemma gentreeS_correct :
  forall {A} (g : G A) n s,
    semSize g s <--> (fun _ => True) ->
    (semSize (gentreeS g n) s) <--> (fun t => (height t) <= n).
Proof.
  move=> A g n.
  elim : n => //= [| n IHn] s Hg t.
  * split.
    + rewrite semReturnSize. by move => <-.
    + case: t => [| t1 t2] //= a . by rewrite semReturnSize.
      by rewrite addn1 ltn0.
  * move/IHn : (Hg)=> HgenT. split => [| Hheight].
    + move/semFrequencySize. move =>
      [[n' [gtree [[[Heq1 Heq2] | [[Heq1 Heq2] | //=]] [H2 _]]]] | [H1 H2]]; subst;
      (try by apply semReturnSize in H2; subst). 
      apply semLiftGen3Size in H2.
      move : H2 => [a1 [ga1 [t1 [/HgenT Hgt1 [t2 [/HgenT Hgt2 Heq]]]]]]; subst.
      simpl. rewrite -[X in _ <= X]addn1 leq_add2r.
        by rewrite geq_max Hgt1 Hgt2.
    + apply/semFrequencySize. left.
      case: t Hheight => [| a t1 t2] //=.
      - move => _. exists 1. eexists. split. by constructor.
        split => //. by apply semReturnSize.
      - rewrite -[X in _ <= X]addn1 leq_add2r.
        rewrite geq_max => /andP [leq1 le2].
        exists n.+1. exists (liftGen3 Node g (gentreeS g n) (gentreeS g n)).
        split => //=. by right; left.
        split => //=. apply semLiftGen3Size.
        exists a; split; first exact/Hg.
        exists t1; split; first exact/IHn.
        by exists t2; split; first exact/IHn.
Qed.

Lemma gentree_correct:
  forall {A} (g : G A) s,
    semSize g s <--> (fun _ => True) -> 
    semSize (gentree g) s <--> (fun t => height t <= s).
Proof.
  move=> A g s Hg t. rewrite /gentree. 
  - split => //= [/semBindSize [n [/arbNat_correctSize/leP H1 /gentreeS_correct H2]] 
                 | H]. 
    eapply leq_trans; try eassumption. auto. 
  - apply semBindSize. exists s.
    split; first by apply arbNat_correctSize.
    apply gentreeS_correct; auto.
Qed.

(* Proving end-to-end equivalence *)

Definition max_elem :=
  fix f l :=
  match l with 
    | [] => 0
    | x :: xs => (max x (f xs))
  end.

Lemma below_max_elem:
  forall (l : list nat) x,
    In x l -> x <= (max_elem l).
Proof.
  intros l. 
  elim : l => //= [x1 xs IHxs] x2 [Heq | HIn]; subst.
  - apply/leP. by apply Max.le_max_l. 
  - apply IHxs in HIn. apply Max.max_case_strong => H; auto.
    apply/leP. eapply le_trans; try eassumption. by apply/leP.
Qed.

Lemma removeP_correct: 
  (forall size, proposition size removeP) <-> (forall (x : nat) l, ~ In x (remove x l)).
Proof.
  simpl. split.
  - move => H x l. 
    have H': removeP x l.
    { apply H with (size := max x (max (max_elem l) (List.length l))). 
      apply arbNat_correctSize. by apply Max.le_max_l.
      eapply arbList_correct with (P := fun x y => (y <= x)%coq_nat) . 
      move => n. by rewrite arbNat_correctSize. 
      split. apply Max.max_case_strong => H'; auto. apply/leP. 
      eapply Max.max_lub_r; eassumption. by apply/leP; apply Max.le_max_r. 
      move => x' /below_max_elem /leP Helem.  
      apply Max.max_case_strong => H'; auto. 
      eapply le_trans; try eassumption. eapply Max.max_lub_l. by eapply H'.
      apply Max.max_case_strong => H''; auto. 
      eapply le_trans; try eassumption. }
      rewrite /removeP in H'. move => HIn.
      have contra : existsb (pred1 x) (remove x l).
      { apply existsb_exists. exists x. split => //. by rewrite /= eq_refl. }
        by rewrite contra //= in H'.
  -  move => H a HIn Hsize l Hsize'. 
     rewrite /removeP. apply Bool.eq_true_not_negb.
     move => /existsb_exists contra.
     move : contra => [n [HIn' /=/eqP Hpred]]; subst. eapply H.
     eassumption. 
Qed.
