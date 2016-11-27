open D3
open Extensions

val path                     : 'a Js.js_array      -> 'a Js.t -> 'a Js.t -> string        -> string        -> int           -> string -> ('b, 'c) D3.t -> ('b, 'c) D3.t
val constant                 : Bitstream.bitstream -> float   -> float   -> float         -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val register                 : Bitstream.bitstream -> float   -> float   -> float         -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val mux2_c                   : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val nth_c                    : float               -> float   -> float   -> int           -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val sub_seq_c                : float               -> float   -> float   -> int           -> int           -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val arith_not                : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val arith_and                : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val arith_nand               : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val arith_or                 : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val arith_nor                : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val arith_xor                : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val arith_nxor               : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val red_and                  : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val red_nand                 : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val red_or                   : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val red_nor                  : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val red_xor                  : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val red_nxor                 : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val logical_and              : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val logical_or               : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val logical_not              : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val less_than                : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val greater_than             : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val equal_to                 : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val less_than_or_equal_to    : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val greater_than_or_equal_to : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val not_equal_to             : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val add_c                    : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val subtract_c               : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val shift_left_logical       : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val shift_right_logical      : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
val shift_right_arithmetic   : float               -> float   -> float   -> ('a, 'b) D3.t -> ('a, 'b) D3.t
