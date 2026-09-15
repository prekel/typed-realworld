open! Base

let n = 32_768
let r = 8
let p = 1
let key_length = 32l
let encode value = Base64.encode_exn ~pad:false ~alphabet:Base64.uri_safe_alphabet value

let decode value =
  Base64.decode ~pad:false ~alphabet:Base64.uri_safe_alphabet value
  |> Result.map_error ~f:(fun (`Msg message) -> message)
;;

let equal left right =
  let different = ref (String.length left lxor String.length right) in
  let length = Int.min (String.length left) (String.length right) in
  for index = 0 to length - 1 do
    different := !different lor (Char.to_int left.[index] lxor Char.to_int right.[index])
  done;
  Int.equal !different 0
;;

let derive ~password ~salt = Scrypt.scrypt ~password ~salt ~n ~r ~p ~dk_len:key_length

let hash password =
  try
    let salt = Mirage_crypto_rng.generate 16 in
    let derived = derive ~password ~salt in
    Ok
      (String.concat
         ~sep:"$"
         [ "scrypt"
         ; Int.to_string n
         ; Int.to_string r
         ; Int.to_string p
         ; encode salt
         ; encode derived
         ])
  with
  | exn -> Error (Exn.to_string exn)
;;

let verify ~encoded password =
  match String.split encoded ~on:'$' with
  | [ "scrypt"; stored_n; stored_r; stored_p; salt; expected ] ->
    (match
       ( Int.of_string_opt stored_n
       , Int.of_string_opt stored_r
       , Int.of_string_opt stored_p
       , decode salt
       , decode expected )
     with
     | Some n', Some r', Some p', Ok salt, Ok expected
       when Int.equal n n' && Int.equal r r' && Int.equal p p' ->
       (try
          equal
            (Scrypt.scrypt ~password ~salt ~n:n' ~r:r' ~p:p' ~dk_len:key_length)
            expected
        with
        | _ -> false)
     | _ -> false)
  | _ -> false
;;
