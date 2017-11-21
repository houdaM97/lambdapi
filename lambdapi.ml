open Extra
open Console
open Files
open Terms
open Typing
open Parser

(**** Early compilation / module support ************************************)

(* [!compile_ref modpath] compiles the module corresponding to the module path
   [modpath], if necessary. This function is stored in a reference as we can't
   define it yet (we could alternatively use mutual definitions). *)
let compile_ref : (string list -> Sign.t) ref = ref (fun _ -> assert false)

(* [loaded] is a hashtable associating module paths to signatures. A signature
   will be mapped to a given module path only if it was already compiled. *)
let loaded : (string list, Sign.t) Hashtbl.t = Hashtbl.create 7

(* [load_signature modpath] returns the signature corresponding to the  module
   path [modpath].  Note that compilation may be required if this is the first
   time that the corresponding module is required. *)
let load_signature : Sign.t -> string list -> Sign.t = fun sign modpath ->
  if Stack.top current_module = modpath then sign else
  try Hashtbl.find loaded modpath with Not_found -> !compile_ref modpath

(**** Scoping ***************************************************************)

(* Representation of an environment for variables. *)
type env = (string * tvar) list

(* [scope new_wildcard env sign t] transforms the parsing level term [t]  into
   an actual term, using the free variables of the environement [env], and the
   symbols of the signature [sign].  If a function is given in [new_wildcard],
   then it is called on [P_Wild] nodes. This will only be allowed when reading
   a term as a pattern. *)
let scope : (unit -> tbox) option -> env -> Sign.t -> p_term -> tbox =
  fun new_wildcard vars sign t ->
    let rec scope vars t =
      match t with
      | P_Vari([],x)  ->
          begin
            try Bindlib.box_of_var (List.assoc x vars) with Not_found ->
            try _Symb (Sign.find sign x) with Not_found ->
            fatal "Unbound variable or symbol %S...\n%!" x
          end
      | P_Vari(fs,x)  ->
          begin
            try _Symb (Sign.find (load_signature sign fs) x) with Not_found ->
              let x = String.concat "." (fs @ [x]) in
              fatal "Unbound symbol %S...\n%!" x
          end
      | P_Type        -> _Type
      | P_Prod(x,a,b) ->
          let f v = scope (if x = "_" then vars else (x,v)::vars) b in
          _Prod (scope vars a) x f
      | P_Abst(x,a,t) ->
          let f v = scope ((x,v)::vars) t in
          let a =
            match a with
            | None    -> let fn (_,x) = Bindlib.box_of_var x in
                         let vars = List.map fn vars in
                         _Unif (ref None) (Array.of_list vars)
            | Some(a) -> scope vars a
          in
          _Abst a x f
      | P_Appl(t,u)   -> _Appl (scope vars t) (scope vars u)
      | P_Wild        ->
          match new_wildcard with
          | None    -> fatal "\"_\" not allowed in terms...\n"
          | Some(f) -> f ()
    in
    scope vars t

 (* [to_tbox ~vars sign t] is a convenient interface for [scope]. *)
let to_tbox : ?vars:env -> Sign.t -> p_term -> tbox =
  fun ?(vars=[]) sign t -> scope None vars sign t

(* [to_term ~vars sign t] composes [to_tbox] with [Bindlib.unbox]. *)
let to_term : ?vars:env -> Sign.t -> p_term -> term =
  fun ?(vars=[]) sign t -> Bindlib.unbox (scope None vars sign t)

(* Representation of a pattern as a head symbol, list of argument and array of
   variables corresponding to wildcards. *)
type patt = def * tbox list * tvar array

(* [to_patt env sign t] transforms the parsing level term [t] into a  pattern.
   Note that here, [t] may contain wildcards. The function also checks that it
   has a definable symbol as a head term, and gracefully fails otherwise. *)
let to_patt : env -> Sign.t -> p_term -> patt = fun vars sign t ->
  let wildcards = ref [] in
  let counter = ref 0 in
  let new_wildcard () =
    let x = "#" ^ string_of_int !counter in
    let x = Bindlib.new_var mkfree x in
    incr counter; wildcards := x :: !wildcards; Bindlib.box_of_var x
  in
  let t = Bindlib.unbox (scope (Some new_wildcard) vars sign t) in
  let (head, args) = get_args t in
  match head with
  | Symb(Def(s)) -> (s, List.map lift args, Array.of_list !wildcards)
  | Symb(Sym(s)) -> fatal "%s is not a definable symbol...\n" s.sym_name
  | _            -> fatal "%a is not a valid pattern...\n" pp t

(* [scope_rule sign r] scopes a parsing level reduction rule,  producing every
   element that is necessary to check its type. This includes its context, the
   symbol, the LHS and RHS as terms and the rule. *)
let scope_rule : Sign.t -> p_rule -> Ctxt.t * def * term * term * rule =
  fun sign (xs_ty_map,t,u) ->
    let xs = List.map fst xs_ty_map in
    (* Scoping the LHS and RHS. *)
    let vars = List.map (fun x -> (x, Bindlib.new_var mkfree x)) xs in
    let (s, l, wcs) = to_patt vars sign t in
    let arity = List.length l in
    let l = Bindlib.box_list l in
    let u = to_tbox ~vars sign u in
    (* Building the definition. *)
    let xs = Array.append (Array.of_list (List.map snd vars)) wcs in
    let lhs = Bindlib.unbox (Bindlib.bind_mvar xs l) in
    let rhs = Bindlib.unbox (Bindlib.bind_mvar xs u) in
    (* Constructing the typing context. *)
    let ty_map = List.map (fun (n,x) -> (x, List.assoc n xs_ty_map)) vars in
    let add_var (vars, ctx) x =
      let a =
        try
          match snd (List.find (fun (y,_) -> Bindlib.eq_vars y x) ty_map) with
          | None    -> raise Not_found
          | Some(a) -> to_term ~vars sign a (* FIXME *)
        with Not_found ->
          let fn (_,x) = Bindlib.box_of_var x in
          let vars = List.map fn vars in
          Bindlib.unbox (_Unif (ref None) (Array.of_list vars))
      in
      ((Bindlib.name_of x, x) :: vars, Ctxt.add x a ctx)
    in
    let wcs = Array.to_list wcs in
    let wcs = List.map (fun x -> (Bindlib.name_of x, x)) wcs in
    let (_, ctx) = Array.fold_left add_var (wcs, Ctxt.empty) xs in
    (* Constructing the rule. *)
    let t = add_args (Symb(Def s)) (Bindlib.unbox l) in
    let u = Bindlib.unbox u in
    (ctx, s, t, u, { lhs ; rhs ; arity })

(**** Interpretation of commands ********************************************)

(* [sort_type sign x a] finds out the sort of the type [a],  which corresponds
   to variable [x]. The result may be either [Type] or [Kind]. If [a] is not a
   well-sorted type, then the program fails gracefully. *)
let sort_type : Sign.t -> string -> term -> term = fun sign x a ->
  if has_type sign Ctxt.empty a Type then Type else
  if has_type sign Ctxt.empty a Kind then Kind else
  fatal "%s is neither of type Type nor Kind.\n" x

(* [handle_newsym sign is_definable x a] scopes the type [a] in the  signature
   [sign], and defines a new symbol named [x] with the obtained type.  It will
   be definable if [is_definable] is true, and static otherwise. Note that the
   function will fail gracefully if the type corresponding to [a] has not sort
   [Type] or [Kind]. *)
let handle_newsym : Sign.t -> bool -> string -> p_term -> unit =
  fun sign is_definable x a ->
    let a = to_term sign a in
    let _ = sort_type sign x a in
    if is_definable then ignore (Sign.new_definable sign x a)
    else ignore (Sign.new_static sign x a)

(* [handle_defin sign x a t] scopes the type [a] and the term [t] in signature
   [sign], and creates a new definable symbol with name [a], type [a] (when it
   is given, or an infered type), and definition [t]. This amounts to defining
   a symbol with a single reduction rule for the standalone symbol. In case of
   error (typing, sorting, ...) the program fails gracefully. *)
let handle_defin : Sign.t -> string -> p_term option -> p_term -> unit =
  fun sign x a t ->
    let t = to_term sign t in
    let a =
      match a with
      | None   -> infer sign Ctxt.empty t
      | Some a -> to_term sign a
    in
    let _ = sort_type sign x a in
    if not (has_type sign Ctxt.empty t a) then
      fatal "Cannot type the definition of %s...\n" x;
    let s = Sign.new_definable sign x a in
    let rule =
      let lhs = Bindlib.mbinder_from_fun [||] (fun _ -> []) in
      let rhs = Bindlib.mbinder_from_fun [||] (fun _ -> t) in
      {arity = 0; lhs ; rhs}
    in
    add_rule s rule

(* [check_rule sign r] check whether the rule [r] is well-typed in the signat-
   ure [sign]. The program fails gracefully in case of error. *)
let check_rule sign (ctx, s, t, u, rule) =
  (* Infer the type of the LHS and the constraints. *)
  let (tt, tt_constrs) =
    try infer_with_constrs sign ctx t with Not_found ->
      fatal "Unable to infer the type of [%a]\n" pp t
  in
  (* Infer the type of the RHS and the constraints. *)
  let (tu, tu_constrs) =
    try infer_with_constrs sign ctx u with Not_found ->
      fatal "Unable to infer the type of [%a]\n" pp u
  in
  (* Checking the implication of constraints. *)
  let check_constraint (a,b) =
    if not (eq_modulo_constrs tt_constrs a b) then
      fatal "A constraint is not satisfied...\n"
  in
  List.iter check_constraint tu_constrs;
  (* Checking if the rule is well-typed. *)
  if not (eq_modulo_constrs tt_constrs tt tu) then
    begin
      err "Infered type for LHS: %a\n" pp tt;
      err "Infered type for RHS: %a\n" pp tu;
      fatal "[%a → %a] is ill-typed\n" pp t pp u
    end;
  (* Adding the rule. *)
  (s,t,u,rule)

(* [handle_rules sign rs] scopes the rules of [rs] first, then check that they
   are well-typed, and finally add them to the corresponding symbol. Note that
   the program fails gracefully in case of error. *)
let handle_rules = fun sign rs ->
  let rs = List.map (scope_rule sign) rs in
  let rs = List.map (check_rule sign) rs in
  let add_rule (s,t,u,rule) =
    add_rule s rule
  in
  List.iter add_rule rs

(* [handle_check sign t a] scopes the term [t] and the type [a],  and attempts
   to show that [t] has type [a] in the signature [sign]*)
let handle_check : Sign.t -> p_term -> p_term -> unit = fun sign t a ->
  let t = to_term sign t in
  let a = to_term sign a in
  if not (has_type sign Ctxt.empty t a) then
    fatal "%a does not have type %a...\n" pp t pp a

(* [handle_infer sign t] scopes [t] and attempts to infer its type with [sign]
   as the signature. *)
let handle_infer : Sign.t -> p_term -> unit = fun sign t ->
  let t = to_term sign t in
  try out 2 "(infr) %a : %a\n" pp t pp (infer sign Ctxt.empty t)
  with Not_found -> fatal "%a : unable to infer\n%!" pp t

(* [handle_eval sign t] scopes (in the signature [sign] and evaluates the term
   [t]. Note that the term is not typed prior to evaluation. *)
let handle_eval : Sign.t -> p_term -> unit = fun sign t ->
  let t = to_term sign t in
  out 2 "(eval) %a\n" pp (Eval.eval t)

(* [handle_conv sign t u] checks the convertibility between the terms [t]  and
   [u] (they are scoped in the signature [sign]). The program fails gracefully
   if the check fails. *)
let handle_conv : Sign.t -> p_term -> p_term -> unit = fun sign t u ->
  let t = to_term sign t in
  let u = to_term sign u in
  if Conv.eq_modulo t u then out 2 "(conv) OK\n"
  else fatal "cannot convert %a and %a...\n" pp t pp u

(* [handle_file sign fname] parses and interprets the file [fname] with [sign]
   as its signature. All exceptions are handled, and errors lead to (graceful)
   failure of the whole program. *)
let handle_file : Sign.t -> string -> unit = fun sign fname ->
  let handle_item it =
    match it with
    | NewSym(d,x,a) -> handle_newsym sign d x a
    | Defin(x,a,t)  -> handle_defin sign x a t
    | Rules(rs)     -> handle_rules sign rs
    | Check(t,a)    -> handle_check sign t a
    | Infer(t)      -> handle_infer sign t
    | Eval(t)       -> handle_eval sign t
    | Conv(t,u)     -> handle_conv sign t u
    | Debug(s)      -> set_debug s
    | Name(_)       -> if !debug then wrn "#NAME directive not implemented.\n"
    | Step(_)       -> if !debug then wrn "#STEP directive not implemented.\n"
  in
  try List.iter handle_item (parse_file fname) with e ->
    fatal "Uncaught exception...\n%s\n%!" (Printexc.to_string e)

(**** Main compilation functions ********************************************)

(* [compile modpath] compiles the file correspinding to module path  [modpath]
   if necessary (i.e., if no corresponding binary file exists).  Note that the
   produced signature is stored into an object file, and in [loaded] before it
   is returned. *)
let compile : string list -> Sign.t = fun modpath ->
  Stack.push modpath current_module;
  let base = String.concat "/" modpath in
  let src = base ^ src_extension in
  let obj = base ^ obj_extension in
  if not (Sys.file_exists src) then fatal "File not found: %s\n" src;
  let sign =
    if more_recent src obj then
      begin
        out 1 "Loading file [%s]\n%!" src;
        let sign = Sign.create modpath in
        handle_file sign src;
        Sign.write sign obj;
        Hashtbl.add loaded modpath sign; sign
      end
    else
      begin
        out 1 "Already compiled [%s]\n%!" obj;
        let sign = Sign.read obj in
        Hashtbl.add loaded modpath sign; sign
      end
  in
  out 1 "Done with file [%s]\n%!" src;
  ignore (Stack.pop current_module); sign

(* Setting the compilation function since it is now available. *)
let _ = compile_ref := compile

(* [compile fname] compiles the source file [fname]. *)
let compile fname =
  let modpath =
    try module_path fname with Invalid_argument _ ->
    fatal "Invalid extension for %S (expected %S)...\n" fname src_extension
  in
  ignore (compile modpath)

(**** Main program, handling of command line arguments **********************)

let _ =
  let debug_doc =
    let flags = List.map (fun s -> String.make 20 ' ' ^ s)
      [ "a : general debug informations"
      ; "e : extra debugging informations for equality"
      ; "i : extra debugging informations for inference"
      ; "p : extra debugging informations for patterns"
      ; "t : extra debugging informations for typing" ]
    in "<str> enable debugging modes:\n" ^ String.concat "\n" flags
  in
  let verbose_doc =
    let flags = List.map (fun s -> String.make 20 ' ' ^ s)
      [ "0 (or less) : no output at all"
      ; "1 : only file loading information (default)"
      ; "2 (or more) : show the results of commands" ]
    in "<int> et the verbosity level:\n" ^ String.concat "\n" flags
  in
  let spec =
    [ ("--debug"  , Arg.String set_debug  , debug_doc  )
    ; ("--verbose", Arg.Int ((:=) verbose), verbose_doc) ]
  in
  let files = ref [] in
  let anon fn = files := fn :: !files in
  let summary = " [--debug [a|e|i|p|t]] [--verbose N] [FILE] ..." in
  Arg.parse (Arg.align spec) anon (Sys.argv.(0) ^ summary);
  List.iter compile (List.rev !files)
