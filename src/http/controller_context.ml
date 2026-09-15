open! Base
open Typed_endpoint

type 'database dependencies =
  { database : 'database
  ; issue : user_id:int -> string
  ; verify : string -> int option
  }

type 'database authenticated =
  { dependencies : 'database dependencies
  ; user_id : int
  }

type 'database optional_auth =
  { dependencies : 'database dependencies
  ; viewer_id : int option
  }

module Make (Backend : Backend.S) = struct
  module Endpoint = Make (Backend)
  open Endpoint

  let bearer =
    Security.Scheme.http_bearer
      ~name:"tokenAuth"
      ~bearer_format:"JWT"
      ~description:"RealWorld Authorization header: Token <jwt>"
      ()
  ;;

  let token request =
    match Backend.header request "authorization" with
    | None -> Error `Missing
    | Some header ->
      (match String.chop_prefix header ~prefix:"Token " with
       | Some token -> Ok token
       | None -> Error `Invalid)
  ;;

  let authenticated dependencies =
    let principal =
      Guard.authenticate
        ~security:[ Security.require bearer ]
        ~status:`Unauthorized
        ~response:(Response.json (module Dto.Error_response))
        ~check:(fun request ->
          let result =
            match token request with
            | Error `Missing ->
              Error (Dto.Error_response.make [ "token", [ "is missing" ] ])
            | Error `Invalid ->
              Error (Dto.Error_response.make [ "token", [ "is invalid" ] ])
            | Ok token ->
              (match dependencies.verify token with
               | None -> Error (Dto.Error_response.make [ "token", [ "is invalid" ] ])
               | Some user_id -> Ok (Principal.v ~identity:user_id ()))
          in
          Backend.Io.return result)
        ()
    in
    let open Context.Let_syntax in
    let%map principal = principal
    and dependencies = Dependency.value dependencies in
    { dependencies; user_id = Principal.identity principal }
  ;;

  let optional_auth dependencies =
    Guard.v
      ~security:[ []; Security.require bearer ]
      ~status:`Unauthorized
      ~response:(Response.json (module Dto.Error_response))
      ~check:(fun request ->
        let result =
          match token request with
          | Error `Missing -> Ok { dependencies; viewer_id = None }
          | Error `Invalid ->
            Error (Dto.Error_response.make [ "token", [ "is invalid" ] ])
          | Ok token ->
            (match dependencies.verify token with
             | None -> Error (Dto.Error_response.make [ "token", [ "is invalid" ] ])
             | Some user_id -> Ok { dependencies; viewer_id = Some user_id })
        in
        Backend.Io.return result)
      ()
  ;;

  let public dependencies = Dependency.value dependencies

  let decode_error =
    Decode_error_response.json
      ~payload:(module Dto.Error_response)
      ~map:(fun _ -> Dto.Error_response.make [ "body", [ "is invalid" ] ])
  ;;
end
