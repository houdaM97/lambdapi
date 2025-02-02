(** Parser-level abstract syntax. *)

open Extra
open Files
open Pos

(** Representation of a (located) identifier. *)
type ident = strloc

(** Representation of a possibly qualified (and located) identifier. *)
type qident = (module_path * string) loc

(** Representation of the associativity of an infix operator. *)
type assoc =
  | Assoc_none
  | Assoc_left
  | Assoc_right

(** The priority of an infix operator is a floating-point number. *)
type priority = float

(** Representation of a binary operator. *)
type binop = string * assoc * priority * qident

(** Parser-level (located) term representation. *)
type p_term = p_term_aux loc
and p_term_aux =
  | P_Type
  (** TYPE constant. *)
  | P_Iden of qident * bool
  (** Variable or (qualified, explicitly applied) symbol. *)
  | P_Wild
  (** Wildcard (place-holder for terms). *)
  | P_Meta of strloc * p_term array
  (** Meta-variable with the given environment. *)
  | P_Patt of strloc * p_term array
  (** Higher-order pattern (used for rules LHS / RHS). *)
  | P_Appl of p_term * p_term
  (** Application. *)
  | P_Impl of p_term * p_term
  (** Implication. *)
  | P_Abst of p_arg list * p_term
  (** Abstraction over several variables. *)
  | P_Prod of p_arg list * p_term
  (** Product over several variables. *)
  | P_LLet of ident * p_arg list * p_term * p_term
  (** Local let. *)
  | P_NLit of int
  (** Natural number literal. *)
  | P_BinO of p_term * binop * p_term
  (** Binary operator. *)
  | P_Wrap of p_term
  (** Parentheses. *)
  | P_Expl of p_term
  (** Explicitly given argument. *)

(** {b NOTE} the boolean parameter of {!constructor:P_Iden} tells whether  the
    corresponding symbol is explicitly applied (value [true]) or not. The flag
    hence indicates whether the symbol has been prefixed with ["@"]. *)

(** Synonym of [p_term] for semantic hints. *)
and p_type = p_term

(** Synonym of [p_term] for semantic hints. *)
and p_patt = p_term

(** Parser-level representation of a function argument. The boolean is true if
    the argument is marked as implicit (i.e., between curly braces). *)
and p_arg = ident option list * p_type option * bool

(** Representation of a symbol tag. *)
type symtag =
  | Sym_const
  (** The symbol is constant. *)
  | Sym_inj
  (** The symbol is injective. *)

(** Parser-level rewriting rule representation. *)
type p_rule = (p_patt * p_term) loc

(** Rewrite pattern specification. *)
type p_rw_patt =
  | P_rw_Term           of p_term
  | P_rw_InTerm         of p_term
  | P_rw_InIdInTerm     of ident * p_term
  | P_rw_IdInTerm       of ident * p_term
  | P_rw_TermInIdInTerm of p_term * ident * p_term
  | P_rw_TermAsIdInTerm of p_term * ident * p_term

(** Parser-level representation of an assertion. *)
type p_assertion =
  | P_assert_typing of p_term * p_type
  (** The given term should have the given type. *)
  | P_assert_conv   of p_term * p_term
  (** The two given terms should be convertible. *)

(** Parser-level representation of a query command. *)
type p_query_aux =
  | P_query_verbose   of int
  (** Sets the verbosity level. *)
  | P_query_debug     of bool * string
  (** Toggles logging functions described by string according to boolean. *)
  | P_query_flag      of string * bool
  (** Sets the boolean flag registered under the given name (if any). *)
  | P_query_assert    of bool * p_assertion
  (** Assertion (must fail if boolean is [true]). *)
  | P_query_infer     of p_term * Eval.config
  (** Type inference command. *)
  | P_query_normalize of p_term * Eval.config
  (** Normalisation command. *)

type p_query = p_query_aux loc

(** Parser-level representation of a proof tactic. *)
type p_tactic_aux =
  | P_tac_refine  of p_term
  (** Refine the current goal using the given term. *)
  | P_tac_intro   of ident option list
  (** Eliminate quantifiers using the given names for hypotheses. *)
  | P_tac_apply   of p_term
  (** Apply the given term to the current goal. *)
  | P_tac_simpl
  (** Normalize in the focused goal. *)
  | P_tac_rewrite of p_rw_patt loc option * p_term
  (** Apply rewriting using the given lemma and pattern. *)
  | P_tac_refl
  (** Apply reflexivity of equality. *)
  | P_tac_sym
  (** Apply symmetry of equality. *)
  | P_tac_focus   of int
  (** Focus on the given goal. *)
  | P_tac_print
  (** Print the current goal. *)
  | P_tac_proofterm
  (** Print the current proof term (possibly containing open goals). *)
  | P_tac_query   of p_query
  (** Query. *)
type p_tactic = p_tactic_aux loc

(** Parser-level representation of a proof terminator. *)
type p_proof_end =
  | P_proof_qed
  (** The proof is done and fully checked. *)
  | P_proof_admit
  (** Give up current state and admit the theorem. *)
  | P_proof_abort
  (** Abort the proof (theorem not admitted). *)

(** Parser-level representation of a configuration command. *)
type p_config =
  | P_config_builtin of string * qident
  (** Sets the configuration for a builtin syntax (e.g., nat literals). *)
  | P_config_binop   of binop
  (** Define (or redefine) a binary operator (e.g., ["+"] or ["×"]). *)

(** Parser-level representation of a single command. *)
type p_statement = (ident * p_arg list * p_type) loc

type p_command_aux =
  | P_require    of bool * module_path list
  (** Require statement (require open if the boolean is true). *)
  | P_require_as of module_path * ident
  (** Require as statement. *)
  | P_open       of module_path list
  (** Open statement. *)
  | P_symbol     of symtag list * ident * p_arg list * p_type
  (** Symbol declaration. *)
  | P_rules      of p_rule list
  (** Rewriting rule declarations. *)
  | P_definition of bool * ident * p_arg list * p_type option * p_term
  (** Definition of a symbol (unfoldable). *)
  | P_theorem    of p_statement * p_tactic list * p_proof_end loc
  (** Theorem with its proof. *)
  | P_set        of p_config
  (** Set the configuration. *)
  | P_query      of p_query
  (** Query. *)

(** Parser-level representation of a single (located) command. *)
type p_command = p_command_aux loc

(** Top level AST returned by the parser. *)
type ast = p_command list

let eq_ident : ident eq = fun x1 x2 -> x1.elt = x2.elt

let eq_qident : qident eq = fun q1 q2 -> q1.elt = q2.elt

let eq_binop : binop eq = fun (n1,a1,p1,id1) (n2,a2,p2,id2) ->
  n1 = n2 && a1 = a2 && p1 = p2 && eq_qident id1 id2

let rec eq_p_term : p_term eq = fun t1 t2 ->
  match (t1.elt, t2.elt) with
  | (P_Iden(q1,b1)       , P_Iden(q2,b2)       ) ->
      eq_qident q1 q2 && b1 = b2
  | (P_Meta(x1,ts1)      , P_Meta(x2,ts2)      )
  | (P_Patt(x1,ts1)      , P_Patt(x2,ts2)      ) ->
      eq_ident x1 x2 && Array.equal eq_p_term ts1 ts2
  | (P_Appl(t1,u1)       , P_Appl(t2,u2)       )
  | (P_Impl(t1,u1)       , P_Impl(t2,u2)       ) ->
      eq_p_term t1 t2 && eq_p_term u1 u2
  | (P_Abst(xs1,t1)      , P_Abst(xs2,t2)      )
  | (P_Prod(xs1,t1)      , P_Prod(xs2,t2)      ) ->
      List.equal eq_p_arg xs1 xs2 && eq_p_term t1 t2
  | (P_LLet(x1,xs1,t1,u1), P_LLet(x2,xs2,t2,u2)) ->
      eq_ident x1 x2 && eq_p_term t1 t2 && eq_p_term u1 u2
      && List.equal eq_p_arg xs1 xs2
  | (P_BinO(t1,b1,u1)    , P_BinO(t2,b2,u2)    ) ->
      eq_binop b1 b2 && eq_p_term t1 t2 && eq_p_term u1 u2
  | (P_Wrap(t1)          , P_Wrap(t2)          ) ->
      eq_p_term t1 t2
  | (P_Expl(t1)          , P_Expl(t2)          ) ->
      eq_p_term t1 t2
  | (t1                  ,                   t2) ->
      t1 = t2

and eq_p_arg : p_arg eq = fun (x1,ao1,b1) (x2,ao2,b2) ->
  List.equal (Option.equal (fun x1 x2 -> x1.elt = x2.elt)) x1 x2
  && Option.equal eq_p_term ao1 ao2 && b1 = b2

let eq_p_rule : p_rule eq = fun r1 r2 ->
  let {elt = (lhs1, rhs1); _} = r1 in
  let {elt = (lhs2, rhs2); _} = r2 in
  eq_p_term lhs1 lhs2 && eq_p_term rhs1 rhs2

let eq_p_rw_patt : p_rw_patt loc eq = fun r1 r2 ->
  match (r1.elt, r2.elt) with
  | (P_rw_Term(t1)                , P_rw_Term(t2)                )
  | (P_rw_InTerm(t1)              , P_rw_InTerm(t2)              ) ->
      eq_p_term t1 t2
  | (P_rw_InIdInTerm(x1,t1)       , P_rw_InIdInTerm(x2,t2)       )
  | (P_rw_IdInTerm(x1,t1)         , P_rw_IdInTerm(x2,t2)         ) ->
      eq_ident x1 x2 && eq_p_term t1 t2
  | (P_rw_TermInIdInTerm(t1,x1,u1), P_rw_TermInIdInTerm(t2,x2,u2))
  | (P_rw_TermAsIdInTerm(t1,x1,u1), P_rw_TermAsIdInTerm(t2,x2,u2)) ->
      eq_ident x1 x2 && eq_p_term t1 t2 && eq_p_term u1 u2
  | (_                            , _                            ) ->
      false

let eq_p_assertion : p_assertion eq = fun a1 a2 ->
  match (a1, a2) with
  | (P_assert_typing(t1,a1), P_assert_typing(t2,a2)) ->
      eq_p_term t1 t2 && eq_p_term a1 a2
  | (P_assert_conv(t1,u1)  , P_assert_conv(t2,u2)  ) ->
      eq_p_term t1 t2 && eq_p_term u1 u2
  | (_                     , _                     ) ->
      false

let eq_p_query : p_query eq = fun q1 q2 ->
  match (q1.elt, q2.elt) with
  | (P_query_assert(b1,a1)   , P_query_assert(b2,a2)   ) ->
     b1 = b2 && eq_p_assertion a1 a2
  | (P_query_infer(t1,c1)    , P_query_infer(t2,c2)    ) ->
     eq_p_term t1 t2 && c1 = c2
  | (P_query_normalize(t1,c1), P_query_normalize(t2,c2)) ->
     eq_p_term t1 t2 && c1 = c2
  | (_                       , _                       ) ->
      false

let eq_p_tactic : p_tactic eq = fun t1 t2 ->
  match (t1.elt, t2.elt) with
  | (P_tac_refine(t1)    , P_tac_refine(t2)    ) ->
      eq_p_term t1 t2
  | (P_tac_intro(xs1)    , P_tac_intro(xs2)    ) ->
      List.equal (Option.equal eq_ident) xs1 xs2
  | (P_tac_apply(t1)     , P_tac_apply(t2)     ) ->
      eq_p_term t1 t2
  | (P_tac_rewrite(r1,t1), P_tac_rewrite(r2,t2)) ->
      Option.equal eq_p_rw_patt r1 r2 && eq_p_term t1 t2
  | (P_tac_query(q1)     , P_tac_query(q2)     ) ->
      eq_p_query q1 q2
  | (t1                  , t2                  ) ->
      t1 = t2

let eq_p_config : p_config eq = fun c1 c2 ->
  match (c1, c2) with
  | (P_config_builtin(s1,q1), P_config_builtin(s2,q2)) ->
      s1 = s2 && eq_qident q1 q2
  | (c1                     , c2                     ) ->
      c1 = c2

(** [eq_command c1 c2] tells whether [c1] and [c2] are the same commands. They
    are compared up to source code positions. *)
let eq_p_command : p_command eq = fun c1 c2 ->
  match (c1.elt, c2.elt) with
  | (P_require(b1,ps1)           , P_require(b2,ps2)           ) ->
     b1 = b2 && List.equal (=) ps1 ps2
  | (P_open(ps1)                 , P_open(ps2)                 ) ->
     List.equal (=) ps1 ps2
  | (P_require_as(p1,id1)  , P_require_as(p2,id2)              ) ->
     p1 = p2 && id1.elt = id2.elt
  | (P_symbol(l1,s1,al1,a1)      , P_symbol(l2,s2,al2,a2)      ) ->
      l1 = l2 && eq_ident s1 s2 && eq_p_term a1 a2
      && List.equal eq_p_arg al1 al2
  | (P_rules(rs1)                , P_rules(rs2)                ) ->
      List.equal eq_p_rule rs1 rs2
  | (P_definition(b1,s1,l1,a1,t1), P_definition(b2,s2,l2,a2,t2)) ->
      b1 = b2 && eq_ident s1 s2 && List.equal eq_p_arg l1 l2
      && Option.equal eq_p_term a1 a2 && eq_p_term t1 t2
  | (P_theorem(st1,ts1,e1)       , P_theorem(st2,ts2,e2)       ) ->
      let (s1,l1,a1) = st1.elt in
      let (s2,l2,a2) = st2.elt in
      eq_ident s1 s2 && eq_p_term a1 a2 && e1.elt = e2.elt
      && List.equal eq_p_arg l1 l2 && List.equal eq_p_tactic ts1 ts2
  | (P_set(c1)                   , P_set(c2)                   ) ->
      eq_p_config c1 c2
  | (P_query(q1)                 , P_query(q2)                 ) ->
      eq_p_query q1 q2
  | (_                           , _                           ) ->
      false

(** [get_args t] decomposes the parser level term [t] into a spine [(h,args)],
    when [h] is the term at the head of the application and [args] is the list
    of all its arguments. *)
let get_args : p_term -> p_term * p_term list =
  let rec get_args args t =
    match t.elt with
    | P_Appl(t,u) -> get_args (u::args) t
    | P_Wrap(t)   -> get_args args t
    | _           -> (t, args)
  in get_args []
