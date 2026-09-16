open! Base
module Domain = Realworld_domain.Domain

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

let json_string fields name =
  List.Assoc.find fields ~equal:String.equal name
  |> Option.bind ~f:(function
    | `String value -> Some value
    | _ -> None)
;;

let json_number fields name =
  List.Assoc.find fields ~equal:String.equal name
  |> Option.bind ~f:(function
    | `Int value -> Some (Float.of_int value)
    | `Intlit value -> Float.of_string_opt value
    | `Float value -> Some value
    | _ -> None)
;;

let create ~secret =
  (module struct
    let issue ~user_id =
      let now = Ptime_clock.now () |> Ptime.to_float_s in
      let header =
        encode
          (Yojson.Safe.to_string
             (`Assoc [ "alg", `String "HS256"; "typ", `String "JWT" ]))
      in
      let payload =
        Yojson.Safe.to_string
          (`Assoc
              [ "sub", `String (Domain.User.Id.to_string user_id)
              ; "iat", `Float now
              ; "exp", `Float (now +. (24. *. 60. *. 60.))
              ])
        |> encode
      in
      let signature =
        Digestif.SHA256.hmac_string ~key:secret (header ^ "." ^ payload)
        |> Digestif.SHA256.to_raw_string
        |> encode
      in
      String.concat ~sep:"." [ header; payload; signature ]
    ;;

    let verify token =
      match String.split token ~on:'.' with
      | [ header; payload; signature ] ->
        let expected =
          Digestif.SHA256.hmac_string ~key:secret (header ^ "." ^ payload)
          |> Digestif.SHA256.to_raw_string
          |> encode
        in
        if not (equal expected signature) then
          None
        else (
          match
            decode header, decode payload
          with
          | Ok header, Ok payload ->
            (try
               match Yojson.Safe.from_string header, Yojson.Safe.from_string payload with
               | `Assoc header, `Assoc payload ->
                 let now = Ptime_clock.now () |> Ptime.to_float_s in
                 (match
                    ( json_string header "alg"
                    , json_string header "typ"
                    , json_string payload "sub"
                    , json_number payload "exp" )
                  with
                  | Some "HS256", Some "JWT", Some subject, Some expiry
                    when Float.(expiry > now) -> Domain.User.Id.of_string subject
                  | _ -> None)
               | _ -> None
             with
             | _ -> None)
          | _ -> None)
      | _ -> None
    ;;
  end : Realworld_application.Token_service.S)
;;
