(* Global references *)
let d3 = Js.Unsafe.variable "d3"
let d3_svg   = d3##svg
let d3_scale = d3##scale

(* Alias for useful wrapper of method callbacks *)
let mb = Js.wrap_meth_callback

(* [translate x y] expresses the "transform" command of translation,
 * given an x and a y. *)
let translate x y =
  "translate(" ^ (string_of_int x) ^ "," ^ (string_of_int y) ^ ")"

(* Makes a JS object representing an (x,y) pair *)
let make_coord x y =
  let c = Js.Unsafe.obj [||] in
  c##x <- x; c##y <- y;
  c

(* OCaml to coordinates in JavaScript *)
let list_to_coord_js_array lst =
  let n = List.length lst in
  let arr = Js.(jsnew array_length (n)) in
  let rec add_vals l i =
    match l with
    | [] -> ()
    | h::k -> Js.array_set arr i (make_coord (fst h) (snd h));
              add_vals k (i+1) in
  add_vals lst 0;
  arr

(* Create a linear scaling function *)
let linear dom rng =
  let lin = Js.Unsafe.new_obj (d3_scale##linear) [||] in
  let _ = (Js.Unsafe.(meth_call lin "domain"
    [| inject (Array.of_list [fst dom; snd dom]) |])) in
  let _ = (Js.Unsafe.(meth_call lin "range"
    [| inject (Array.of_list [fst rng; snd rng]) |])) in
  lin

(* Allows us to use a scale *)
let use_scale lne x = Js.Unsafe.(fun_call lne [| inject x |])

(* Create a line function *)
let line x_scale y_scale =
  let dot_line = Js.Unsafe.new_obj (d3_svg##line) [||] in
  let _ = (Js.Unsafe.(meth_call dot_line "x"
    [| inject (mb (fun this d i -> use_scale x_scale d##x)) |])) in
  let _ = (Js.Unsafe.(meth_call dot_line "y"
    [| inject (mb (fun this d i -> use_scale y_scale d##y)) |])) in
  let _ = Js.Unsafe.(meth_call dot_line "interpolate" [| inject "linear" |]) in
  dot_line

(* Allows us to use a line-auto path generator function *)
let use_line lne data =
  Js.Unsafe.(fun_call lne [| inject data |])
