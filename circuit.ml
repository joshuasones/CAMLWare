open Bitstream
open Combinational

(* a map with strings as the keys *)
module StringMap = Map.Make(String)
type 'a map = 'a StringMap.t

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

let map_of_assoclist l =
  List.fold_left (fun acc (k,v) -> StringMap.add k v acc) StringMap.empty l

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

let format_format_circuit f circ =
  Format.fprintf f "Columns : %s\n\n" (string_of_int (List.length circ));
  List.iter (fun x -> (
    print_string "\n";
    StringMap.iter
      (fun k v -> print_string (k^", ") ) x
    )
  ) circ

(************************ eval ***********************)

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

(*[eval_regs r circ] evaluates the rising / falling registers *)
let eval_regs r circ =
  match r.next with
  | User_input -> Register r
  | AST comb -> if (r.reg_type = Falling && circ.clock)
                || (r.reg_type = Rising && not circ.clock)
                then let new_val = evaluate circ comb in
                Register {r with value = new_val; length = length new_val}
              else Register r

let update_rising_falling circ c =
  match c with
    | Register r -> eval_regs r circ
    | _ -> c

let update_outputs circ c =
  match c with
    | Register r -> (match (r.next, r.reg_type) with
                    |(AST comb, Output) -> let new_val = evaluate circ comb in
                                            Register {r with value = new_val;
                                            length = length new_val}
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


  type comb_id =
    | Id_Const     of int * bitstream
    | Id_Var       of int * id
    | Id_Sub_seq   of int * int * int * comb_id
    | Id_Nth       of int * int * comb_id
    | Id_Gate      of int * gate * comb_id * comb_id
    | Id_Logical   of int * gate * comb_id * comb_id
    | Id_Reduce    of int * gate * comb_id
    | Id_Neg       of int * negation * comb_id
    | Id_Comp      of int * comparison * comb_id * comb_id
    | Id_Arith     of int * arithmetic * comb_id * comb_id
    | Id_Concat    of int * comb_id list
    | Id_Mux2      of int * comb_id * comb_id * comb_id
    | Id_Apply     of int * id * comb_id list
    | Id_Let       of int * id * comb_id * comb_id


  type id_comb = int * comb
  let new_id = ref 0

  (** generate an unused type variable *)
  let newvar =
    new_id := 1 + !(new_id);
    !new_id

  let attach_ids ast =
    let rec id_helper ast =
      match ast with
      | Const b -> Id_Const (newvar, b)
      | Var v -> Id_Var (newvar, v)
      | Sub_seq(i1, i2, comb) -> Id_Sub_seq (newvar, i1, i2, id_helper comb)
      | Nth (n, comb) -> Id_Nth (newvar, n, id_helper comb)
      | Gate (g, c1, c2) ->  Id_Gate (newvar, g, id_helper c1, id_helper c2)
      | Logical(l, c1, c2) -> Id_Logical(newvar, l, id_helper c1, id_helper c2)
      | Reduce (g, comb) -> Id_Reduce (newvar, g, id_helper comb)
      | Neg (n, comb) -> Id_Neg (newvar, n, id_helper comb)
      | Comp(c, c1, c2) -> Id_Comp (newvar, c, id_helper c1, id_helper c2)
      | Arith (o, c1, c2) -> Id_Arith (newvar, o, id_helper c1, id_helper c2)
      | Concat (c_list) -> Id_Concat (newvar, (List.map (function x -> id_helper x) c_list))
      | Mux2 (c1, c2, c3) -> Id_Mux2 (newvar, id_helper c1, id_helper c2, id_helper c3)
      | Apply (id, c_list) -> Id_Apply (newvar, id, (List.map (function x -> id_helper x) c_list))
      | Let (id, c1, c2) -> Id_Let (newvar, id, id_helper c1, id_helper c2)
    in id_helper ast

let get_all_registers circ =
  let reg =
    (StringMap.filter (fun k v -> match v with |Register _ -> true | _ -> false) circ.comps)
    in
  (StringMap.map
    (fun v ->
      match v with
      | Register r -> r
      | _ -> failwith "invalid map")
    reg)


let id_comp = fun x y ->  0

let list_dependencies ast reg_list =
  let rec dependency_helper ast dep =
  match ast with
  | Id_Const (_, b) -> dep
  | Id_Var (_, v) -> if (StringMap.mem v reg_list) then v::dep else dep
  | Id_Sub_seq (_,_, _, comb) -> (dependency_helper comb dep)
  | Id_Nth (_,_, comb) -> (dependency_helper comb dep)
  | Id_Gate (_,_, c1, c2) -> (dependency_helper c1 dep)@(dependency_helper c2 dep)
  | Id_Logical(_,_, c1, c2) -> (dependency_helper c1 dep)@(dependency_helper c2 dep)
  | Id_Reduce (_,_, comb) -> (dependency_helper comb dep)
  | Id_Neg (_,_, comb) -> (dependency_helper comb dep)
  | Id_Comp(_,_, c1, c2) -> (dependency_helper c1 dep)@(dependency_helper c2 dep)
  | Id_Arith (_,_, c1, c2) -> (dependency_helper c1 dep)@(dependency_helper c2 dep)
  | Id_Concat (_,c_list) -> List.fold_left
    (fun acc c -> acc@(dependency_helper c acc)) dep c_list
  | Id_Mux2 (_,c1, c2, c3) ->
    (dependency_helper c1 dep)@(dependency_helper c2 dep)@(dependency_helper c3 dep)
  | Id_Apply (_,_, c_list) -> List.fold_left
    (fun acc c -> acc@(dependency_helper c acc)) dep c_list
  | Id_Let (_,_, c1, c2) -> (dependency_helper c1 dep)@(dependency_helper c2 dep)
  in List.sort_uniq id_comp (dependency_helper ast [])

let no_inputs reg_list =
  StringMap.filter
  (fun k v -> match v.reg_type with |Input -> false | _ -> true) reg_list

let find_inputs reg_list =
  StringMap.filter
  (fun k v -> match v.reg_type with |Input -> true | _ -> false) reg_list

let no_outputs reg_list =
  StringMap.filter
  (fun k v -> match v.reg_type with |Output -> false | _ -> true) reg_list

let find_outputs reg_list =
  StringMap.filter
  (fun k v -> match v.reg_type with |Output -> true | _ -> false) reg_list

type formatted_circuit = register StringMap.t list

let assign_columns circ =
  let reg = get_all_registers circ in
  let inputs = find_inputs reg in
  let p = print_string (string_of_int (StringMap.cardinal inputs)) in
  let outputs = find_outputs reg in
  let asts = (no_outputs (no_inputs reg)) in

  let p2 = print_string (string_of_int (StringMap.cardinal asts)) in
  let list_dep_of_register r =
    (match r.reg_type with
    | Rising | Falling -> (
      match r.next with
      | AST ast -> list_dependencies (attach_ids ast) reg
      | _ -> []
    )
    | _ -> []) in
  let reg_deps = (StringMap.map (fun v -> list_dep_of_register v) (no_inputs reg)) in
  let p2 = print_string (string_of_int (StringMap.cardinal reg_deps)) in
  let rec dep_helper not_done d cols =
    (match (StringMap.is_empty not_done) with
    | true -> cols
    | false ->
      let resolved k v =
        (List.for_all (fun x -> StringMap.mem x d) (StringMap.find k reg_deps)) in
      let new_col = StringMap.filter resolved not_done in
      let new_done = StringMap.union (fun k v1 v2 -> Some v2) d new_col in
      let new_not_done = StringMap.filter (fun k v -> not (StringMap.mem k new_done)) not_done in

      dep_helper new_not_done new_done (new_col::cols))

  in
    if (StringMap.is_empty outputs)
    then (List.rev ((dep_helper asts inputs [inputs])))
    else List.rev (outputs::(dep_helper asts inputs [inputs]))


let get_ids ast =
  match ast with
  | Id_Const (id, _ ) -> id
  | Id_Var (id, _ ) -> id
  | Id_Sub_seq(id, _, _, _ ) -> id
  | Id_Nth (id, _, _ ) -> id
  | Id_Gate (id, _ , _, _ ) -> id
  | Id_Logical(id, _, _, _ ) -> id
  | Id_Reduce (id, _, _ ) -> id
  | Id_Neg (id, _, _ ) -> id
  | Id_Comp(id, _, _, _ ) -> id
  | Id_Arith (id, _, _, _ ) -> id
  | Id_Concat (id, _ ) -> id
  | Id_Mux2 (id, _, _, _ ) -> id
  | Id_Apply (id, _, _ ) -> id
  | Id_Let (id, _, _, _ ) -> id


  (* type unique = Register of id | Let of id

  type non_unique =
   B of gate | L of gate | A of arithmetic | N of negation | C of comparison
   | Sub of int*int | Nth of int | Subcirc of id | Red of gate | Concat of int list
   | Mux of int *int * int | Const of b | Apply of id * int list *)

  type node = Register of id | Let of id | B of gate | L of gate | A of arithmetic
  | N of negation | C of comparison | Sub of int*int | Nth of int | Subcirc of id |
  Red of gate | Concat of int list | Mux of int *int * int | Const of bitstream | Apply of id * int list

  type display_info = {
    y_coord : float;
    id : int;
    node : node;
    parents : int list;
  }


  let tree_to_list ast reg_id reg_list =
    (* ast:comb - what we are analyzing
     * parents : [int] - the parents of the current node
     * lets : Map: string -> ([int], comb) - a map from each variable name to its
     *        parents as well as its combinational logic
     * reg_list : the reg map we throw around everywhere
     * reg_parents : Map id -> [int]*)
    let rec list_helper ast parents lets reg_list reg_parents =
      match ast with
      | Id_Const (id, b) ->
        [{y_coord=0.; id=id; node = Const b; parents = parents}]
      | Id_Var (id, v) ->
        let new_reg_list =
          if (StringMap.mem v reg_list)
          then
            if (StringMap.mem v reg_parents)
            then StringMap.add v (parents@(StringMap.find v reg_parents)) reg_parents
            else StringMap.add v parents reg_parents
          else reg_list in
        let new_lets =
          if (StringMap.mem v reg_list)
          then lets
          else
            let (p, comb) = StringMap.find v lets in
            StringMap.add v (parents@p, comb) lets in
        [{y_coord = 0.; id=id; node = (Let v); parents = parents}]
      | Id_Sub_seq(id, i1, i2, comb) ->
        {y_coord = 0.; id=id; node = Sub (i1, i2); parents=parents}
        ::(list_helper comb [id] lets reg_list reg_parents)
      | Id_Nth (id, n, comb) ->
        {y_coord = 0.; id=id; node = Nth n; parents=parents}
        ::(list_helper comb [id] lets reg_list reg_parents)
      | Id_Gate (id, g, c1, c2) ->
        {y_coord = 0.; id=id; node = B g; parents = parents}
        ::((list_helper c1 [id] lets reg_list reg_parents)
        @ (list_helper c2 [id] lets reg_list reg_parents))
      | Id_Logical (id, l, c1, c2) ->
        {y_coord = 0.; id=id; node = L l; parents = parents}
        ::((list_helper c1 [id] lets reg_list reg_parents)
        @ (list_helper c2 [id] lets reg_list reg_parents))
      | Id_Reduce ( id, g, comb ) ->
        {y_coord = 0.; id=id; node = Red g; parents=parents}
        ::(list_helper comb [id] lets reg_list reg_parents)
      | Id_Neg (id, n, comb) ->
        {y_coord = 0.; id=id; node = N n; parents=parents}
        ::(list_helper comb [id] lets reg_list reg_parents)
      | Id_Comp(id, c, c1, c2) ->
        {y_coord = 0.; id=id; node = C c; parents = parents}
        ::((list_helper c1 [id] lets reg_list reg_parents)
        @ (list_helper c2 [id] lets reg_list reg_parents))
      | Id_Arith (id, o, c1, c2) ->
        {y_coord = 0.; id=id; node = A o; parents = parents}
        ::((list_helper c1 [id] lets reg_list reg_parents)
        @ (list_helper c2 [id] lets reg_list reg_parents))
      | Id_Concat (id, c_list) ->
        let ids = List.fold_left (fun acc x -> (get_ids x)::acc) [] c_list in
        {y_coord = 0.; id=id; node=(Concat (List.rev ids)); parents=parents}
        ::List.flatten((List.fold_right(fun x acc -> (list_helper x [id] lets reg_list reg_parents)::acc) c_list []))
      | Id_Mux2 (id, c1, c2, c3) ->
        {y_coord = 0.; id=id; node = (Mux (get_ids c1, get_ids c2, get_ids c3) ); parents=parents}
        :: ((list_helper c1 [id] lets reg_list reg_parents)
        @ (list_helper c2 [id] lets reg_list reg_parents)
        @ (list_helper c3 [id] lets reg_list reg_parents))
      | Id_Apply (id, var, c_list) ->
        {y_coord = 0.; id = id; node = (Subcirc var); parents = parents}
        ::List.flatten ((List.fold_right (fun x acc -> (list_helper x [id] lets reg_list reg_parents)::acc) c_list []))
      | Id_Let (id, var, c1, c2) ->
        let new_lets = StringMap.add var ([], c1) lets in
        let inputs = list_dependencies c1 reg_list in
        {y_coord = 0.; id = id; node = Let (var); parents = parents}
        ::(list_helper c1 [id] new_lets reg_list reg_parents)
      in (list_helper ast [reg_id] StringMap.empty reg_list StringMap.empty)


  let format circ = assign_columns circ
