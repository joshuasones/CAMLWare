open Bitstream
open Combinational

(* a map with strings as the keys *)
module StringMap = Map.Make(String)
type 'a map = 'a StringMap.t

module StringSet = Set.Make(String)
type set = StringSet.t

(* since we internally represent inputs and outputs as registers, we need a
 * flag to specify their type *)
type reg_type =
  | Rising | Falling | Input | Output

type register_input =
  | User_input | AST of comb

(* a digital state component *)
type register = {
  reg_type : reg_type;
  length : int;
  value : bitstream;
  next : register_input;
}

(* a circuit component is either a register or a subcircuit *)
type component =
  | Register of register | Subcirc of comb * id list

(* a type to represent the state of a circuit *)
type circuit = {
  comps : component map;
  clock : bool;
}

module type CircuitSimulator = sig
  val evaluate : circuit -> comb -> bitstream
  val step : circuit -> circuit
  val step_n : circuit -> int -> circuit
  val change_input : circuit -> id -> bitstream -> circuit
end

module type StaticAnalyzer = sig
  type error_log
  val validate : circuit -> error_log
  val valid : error_log -> bool
  val format_log : Format.formatter -> error_log -> unit
end

let make_register length logic reg_type =
  Register {
    reg_type = reg_type;
    length = length;
    value = zeros length;
    next = logic;
  }

let rising_register length logic =
  make_register length (AST logic) Rising

let falling_register length logic =
  make_register length (AST logic) Falling

let input length =
  make_register length User_input Input

let output length logic =
  make_register length (AST logic) Output

let subcircuit logic args =
  Subcirc (logic, args)

let circuit comps =
  {
    comps = comps;
    clock = false;
  }

let circuit_from_list l =
  let map_of_assoclist =
    List.fold_left (fun acc (k,v) -> StringMap.add k v acc) StringMap.empty in
  l |> map_of_assoclist |> circuit

let format_register_input f input =
  match input with
  | User_input -> Format.fprintf f "User Input"
  | AST c -> Format.fprintf f "%a" (format_logic) c

let rec format_args f args =
  match args with
  | [] -> ()
  | h::[] -> Format.fprintf f "%s" h
  | h::t -> Format.fprintf f "%s, %a" h (format_args) t

let format_comp f comp =
  match comp with
  | Register reg ->
    Format.fprintf f "%s\nValue: %a\nNext: %a"
      (match reg.reg_type with
       | Rising -> "Rising Register"
       | Falling -> "Falling Register"
       | Input -> "Input"
       | Output -> "Output")
      (format_bitstream) reg.value
      (format_register_input) reg.next
  | Subcirc (sub,args) ->
    Format.fprintf f "(%a) -> %a" (format_args) args (format_logic) sub

let format_circuit f circ =
  Format.fprintf f "Clock: %s\n\n" (if circ.clock then "1" else "0");
  StringMap.iter
    (fun id comp -> Format.fprintf f ("%s =\n%a\n\n") id (format_comp) comp)
    circ.comps

(* [is_subcirc comp] is true if [comp] is a subcircuit, false otherwise *)
let is_subcirc _ = function
  | Subcirc _ -> true
  | _ -> false

(* [is_reg_type t comp] is true if [comp] is a register of type [t], false
 * otherwise *)
let is_reg_type t _ = function
  | Register r -> r.reg_type = t
  | _ -> false

(************************ eval ***********************)

module Simulator : CircuitSimulator = struct
  let rec eval_gates bin_op bin_not g b1 b2 =
    match g with
    | And -> bin_op and_bits b1 b2
    | Or -> bin_op or_bits b1 b2
    | Xor -> bin_op xor_bits b1 b2
    | Nand -> bin_not (bin_op and_bits b1 b2)
    | Nor -> bin_not (bin_op or_bits b1 b2)
    | Nxor -> bin_not (bin_op xor_bits b1 b2)

  let rec eval_reduce g b1 =
    match g with
    | And -> reduce and_bits b1
    | Or -> reduce or_bits b1
    | Xor -> reduce xor_bits b1
    | Nand -> bitwise_not (reduce and_bits b1)
    | Nor ->  bitwise_not (reduce or_bits b1)
    | Nxor -> bitwise_not (reduce xor_bits b1)

  let eval_neg n b1 =
    match n with
    | Neg_bitwise -> bitwise_not b1
    | Neg_logical -> logical_not b1
    | Neg_arithmetic -> negate b1

  let eval_comp comp b1 b2 =
    match comp with
     | Lt -> less_than b1 b2
     | Gt -> greater_than b1 b2
     | Eq -> equals b1 b2
     | Lte -> logical_binop or_bits (less_than b1 b2) (equals b1 b2)
     | Gte -> logical_binop or_bits (greater_than b1 b2) (equals b1 b2)
     | Neq -> logical_not (equals b1 b2)

  let eval_arith arth b1 b2 =
    match arth with
    | Add -> add b1 b2
    | Subtract -> subtract b1 b2
    | Sll -> shift_left b1 b2
    | Srl -> shift_right_logical b1 b2
    | Sra -> shift_right_arithmetic b1 b2

  let rec eval_hlpr circ comb env =
     match comb with
    | Const b -> b
    | Var id -> List.assoc id env
    | Sub_seq (n1,n2,c) -> substream (eval_hlpr circ c env) n1 n2
    | Nth (i,c) -> nth (eval_hlpr circ c env) i
    | Gate (g,c1,c2) -> let b1 = (eval_hlpr circ c1 env) in
                        let b2 = (eval_hlpr circ c2 env) in
                        eval_gates bitwise_binop bitwise_not g b1 b2
    | Logical (g,c1,c2) -> let b1 = (eval_hlpr circ c1 env) in
                        let b2 = (eval_hlpr circ c2 env) in
                        eval_gates logical_binop logical_not g b1 b2
    | Reduce (g,c) -> let b1 = (eval_hlpr circ c env) in
                      eval_reduce g b1
    | Neg (n,c) -> let b1 = (eval_hlpr circ c env) in eval_neg n b1
    | Comp (comp,c1,c2) -> let b1 = (eval_hlpr circ c1 env) in
                        let b2 = (eval_hlpr circ c2 env) in
                        eval_comp comp b1 b2
    | Arith (arth,c1,c2) -> let b1 = (eval_hlpr circ c1 env) in
                        let b2 = (eval_hlpr circ c2 env) in
                        eval_arith arth b1 b2
    | Concat (clst) -> List.fold_left
                      (fun acc c ->
                        concat (eval_hlpr circ c env) acc) (create []) clst
    | Mux2 (c1,c2,c3) -> let s = (eval_hlpr circ c1 env) in
                          if is_zero s
                          then eval_hlpr circ c3 env
                          else eval_hlpr circ c2 env
    | Apply (id,clst) -> let subcirc = StringMap.find id circ.comps in
                          let (nv, comb1) = eval_apply subcirc circ clst env in
                          eval_hlpr circ comb1 nv
    | Let (id,c1,c2) -> let b1 = (eval_hlpr circ c1 env) in
                        if List.mem_assoc id env then
                        failwith "Cannot use variable twice" else
                        let nv = (id, b1)::env in eval_hlpr circ c2 nv

  and

      eval_apply subcirc circ clst env = (* returns (new_environment, comb) *)
        match subcirc with
        | Subcirc (comb, ids) -> let nv = eval_apply_hlpr ids clst env circ in
                                  (nv, comb)
        | _ -> failwith "incorrect sub circuit application"

  and
      eval_apply_hlpr ids clst env circ =
         match (ids, clst) with
        | ([], []) -> env
        | (i::is,c::cs) -> let b = (eval_hlpr circ c env) in
                    (i, b)::(eval_apply_hlpr is cs env circ)
        | _ -> failwith "incorrect sub circuit application"

  let rec evaluate circ comb =
    let env = StringMap.fold
    (fun k v acc ->
      match v with
      | Register r -> (k, r.value)::acc
      | _ -> acc)
    circ.comps [] in
    (* env is a assoc list of RegID: bitstream ex: "A": 101011 *)
     eval_hlpr circ comb env

  (************************ eval ***********************)

  (* [register_len_check r new_val] zero eztends new_val or truncates new_val
      to be the same length as r *)
  let register_len_check r new_val =
    if (length new_val) < r.length
    then (zero_extend r.length new_val)
    else if (length new_val) > r.length then substream new_val 0 (r.length - 1)
    else new_val

  (*[eval_regs r circ] evaluates the rising / falling registers *)
  let eval_regs r circ =
    match r.next with
    | User_input -> Register r
    | AST comb -> if (r.reg_type = Falling && circ.clock)
                  || (r.reg_type = Rising && not circ.clock)
                  then let new_val = register_len_check r (evaluate circ comb) in
                  Register {r with value = new_val}
                else Register r

  let update_rising_falling circ c =
    match c with
      | Register r -> eval_regs r circ
      | _ -> c

  let update_outputs circ c =
    match c with
      | Register r -> (match (r.next, r.reg_type) with
                      |(AST comb, Output) -> let new_val =
                                        register_len_check r
                                        (evaluate circ comb)
                                            in
                                        Register {r with value = new_val}
                      | _ -> c)
      | _ -> c


  let step circ =
    let new_comps = StringMap.map (update_rising_falling circ) circ.comps in
    let new_circ = {comps = new_comps; clock = not circ.clock} in
    let comps_new = StringMap.map (update_outputs new_circ) new_circ.comps in
    {comps = comps_new; clock = new_circ.clock}

  let rec step_n circ n =
    match n with
    | 0 -> circ
    | i -> let new_circ = step circ in step_n new_circ (i - 1)

  let change_input circ id value =
    let r = match StringMap.find id circ.comps with
      | Register reg -> reg
      | _ -> failwith "tried to change the value of a subcircuit" in
    let new_comps =
      StringMap.add id (Register {r with value = value}) circ.comps in
    let new_circ = {comps = new_comps; clock = circ.clock} in
    let comps_new = StringMap.map (update_outputs new_circ) new_circ.comps in
    {comps = comps_new; clock = new_circ.clock}
end

module Analyzer : StaticAnalyzer = struct
  (* an error log is a monadic data type containing a circuit and a list of
   * string descriptions of the errors in it *)
  type error_log = circuit * string list

  exception Found_recursion of string list

  (* monadic return *)
  let make_log circ =
    (circ,[])

  (* monadic bind *)
  let (|>>) log f =
    let new_log = f (fst log) in
    (fst new_log, (snd new_log) @ (snd log))

  (* [detect_ast_errors comps env id ast] recursively traverses [ast] detecting and
   * logging errors in the context of overall component map [comps] and
   * environment env  *)
  let rec detect_ast_errors comps env id ast =
    let template = Printf.sprintf "Error in definition for %s:\n" id in
    match ast with
    | Const _ -> []
    | Var v ->
      if StringSet.mem v env
      then []
      else [Printf.sprintf "%sUnbound variable %s" template v]
    | Sub_seq (n1,n2,c) ->
      let warning =
        if n1 > n2
        then [Printf.sprintf
                "%sArray access [%i - %i] is in the wrong order" template n1 n2]
        else [] in
      warning @ (detect_ast_errors comps env id c)
    | Nth (_,c) -> (detect_ast_errors comps env id c)
    | Gate (_,c1,c2) | Logical (_,c1,c2) | Comp (_,c1,c2) | Arith (_,c1,c2) ->
      (detect_ast_errors comps env id c1) @ (detect_ast_errors comps env id c2)
    | Reduce (_,c) | Neg (_,c) -> detect_ast_errors comps env id c
    | Concat cs -> cs |> (List.map (detect_ast_errors comps env id))
                   |> (List.fold_left (@) [])
    | Mux2 (c1,c2,c3) ->
      (detect_ast_errors comps env id c1) @
      (detect_ast_errors comps env id c2) @
      (detect_ast_errors comps env id c3)
    | Apply (f,cs) ->
      let warning =
        if not (StringMap.mem f comps)
        then  [Printf.sprintf "%sUndefined subcircuit %s" template f]
        else match StringMap.find f comps with
          | Register _ -> [Printf.sprintf "%s%s is not a subcircuit" template f]
          | Subcirc (_,args) ->
            let expected = List.length args in
            let found = List.length cs in
            if expected <> found
            then [Printf.sprintf
                    "%sExpected %i %s to subcircuit %s but found %i"
                    template expected
                    (if expected = 1 then "input" else "inputs") f found]
            else [] in
      let arg_warnings = cs |> (List.map (detect_ast_errors comps env id))
                         |> (List.fold_left (@) []) in
      warning @ arg_warnings
    | Let (x,c1,c2) ->
      let warning =
        if StringMap.mem x comps
        then [Printf.sprintf "%sLocal variable %s shadows definition" template x]
        else [] in
      let new_env = StringSet.add x env in
      warning @
      (detect_ast_errors comps new_env id c1) @
      (detect_ast_errors comps new_env id c1)

  (* [detect_comp_errors comps id comp] detects and logs errors in the AST of
   * [comp] given the context of overall component map [comps] *)
  let detect_comp_errors comps id comp =
    let bound = comps |> (StringMap.filter
                (fun k v -> not (is_reg_type Output k v || is_subcirc k v))) in
    let env = StringMap.fold
                (fun k _ acc -> StringSet.add k acc) bound StringSet.empty in
    match comp with
    | Register r ->
      (match r.next with
       | User_input -> []
       | AST ast -> detect_ast_errors comps env id ast)
    | Subcirc (ast,args) ->
      let binding_warnings =
        args |>
        (List.map (fun arg ->
            if StringMap.mem arg comps
            then Some (Printf.sprintf
           "Error in definition for %s:\nArgument %s shadows definition" id arg)
            else None))
        |> (List.filter (fun w -> w <> None))
        |> (List.map (function Some c -> c | None -> failwith "impossible")) in
      let fun_env =
        List.fold_left (fun acc arg -> StringSet.add arg acc) env args in
      binding_warnings @ (detect_ast_errors comps fun_env id ast)

  (* [detect_variable_errors circ] detects and logs the following errors:
   * - binding a local variable that shadows a register name
   * - referring to the value of an output
   * - using an unbound variable
   * - accessing a substream with invalid indices
   * - applying a subcircuit with the wrong number of arguments *)
  let detect_variable_errors circ =
    let warnings_map =
      StringMap.mapi
        (detect_comp_errors circ.comps) circ.comps in
    let warnings_list =
      StringMap.fold (fun _ v acc -> v @ acc) warnings_map [] in
    (circ,warnings_list)


  (* [contains acc ast] is a list of the ids of the subcircuits contained
   * within [ast] *)
  let rec contains = function
    | Const _ | Var _ -> []
    | Sub_seq (_,_,c) | Nth (_,c) | Reduce (_,c) | Neg (_,c) ->
      contains c
    | Gate (_,c1,c2) | Logical (_,c1,c2) | Comp (_,c1,c2)
    | Arith (_,c1,c2) | Let (_,c1,c2) ->
      (contains c1) @ (contains c2)
    | Mux2 (c1,c2,c3) ->
      (contains c1) @ (contains c2) @ (contains c3)
    | Concat cs ->
      cs |> (List.map (contains)) |> (List.fold_left (@) [])
    | Apply (f,cs) ->
      f::(cs |> (List.map (contains)) |> (List.fold_left (@) []))

(* [detect_cycles graph] performs depth first search on directed graph [graph]
 * and raises [Found_recursion path] if it encouters a cycle with path [path]
 * It ignores edges pointing to nodes that do not exist *)
  let detect_cycles graph =
    let rec dfs_helper path visited node =
      if List.mem node path then raise (Found_recursion (node::path)) else
      if StringSet.mem node visited then visited else
      if not (StringMap.mem node graph) then (StringSet.add node visited) else
        let new_path = node::path in
        let new_visited = StringSet.add node visited in
        let edges = StringMap.find node graph in
        List.fold_left
          (fun acc edge -> dfs_helper new_path acc edge) new_visited edges in
    let nodes = graph |> StringMap.bindings |> (List.map (fst)) in
    List.fold_left
      (fun acc node -> dfs_helper [] acc node) StringSet.empty nodes

  (* [make_graph circ] constructs a directed graph from [circ] where each node
   * is a subcircuit and an edge is a contains relation *)
  let make_graph circ =
    circ.comps |> (StringMap.filter (is_subcirc))
    |> (StringMap.map
          (function | Subcirc (c,_) -> c
                    | _ -> failwith "impossible"))
    |> (StringMap.map (contains))

  (* [format_path_warning path] is a string representation of a recursion error
   * with path [path] *)
  let format_path_warning path =
    let rec format_path_helper _ = function
      | [] -> ""
      | h::[] -> Printf.sprintf "%s" h
      | h::t -> Printf.sprintf "%s contains %a" h (format_path_helper) t in
    Printf.sprintf
      "Recursion Detected:\n%a" (format_path_helper) (List.rev path)

  (* [detect_recursion circ] detects and logs any potentially recursive function
   * calls. These are not a valid construct in hardware implementation *)
  let rec detect_recursion (circ:circuit) : error_log =
    let g = make_graph circ in
    let warnings =
      try ignore (detect_cycles g); []
      with Found_recursion path -> [format_path_warning path] in
    (circ,warnings)

  (* validate pipes the circuit through several error checking functions *)
  let validate circ =
    circ |>
    make_log |>>
    detect_variable_errors |>>
    detect_recursion

  let valid (_,log) =
    List.length log = 0

  let format_log f (_,log) =
    let rec format_list f2 =
      function
      | [] -> ()
      | h::[] -> Format.fprintf f2 "%s\n" h
      | h::t -> Format.fprintf f2 "%s\n\n%a" h (format_list) t in
    let l = List.length log in
    if l = 0 then Format.fprintf f "No errors were detected\n" else
      Format.fprintf f "%i %s detected\n\n%a"
        l (if l = 1 then "error was" else "errors were") (format_list) log

end