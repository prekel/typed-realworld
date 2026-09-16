open! Base
open Typed_endpoint
module Domain = Realworld_domain.Domain

type 'database dependencies =
  { database : 'database
  ; issue : user_id:Domain.User.id -> string
  ; verify : string -> Domain.User.id option
  }

type 'database authenticated =
  { dependencies : 'database dependencies
  ; user_id : Domain.User.id
  }

type 'database optional_auth =
  { dependencies : 'database dependencies
  ; viewer_id : Domain.User.id option
  }

module Make (Backend : Backend.S) = struct
  module Endpoint = Make (Backend)
  open Endpoint

  module Public = struct
    let database (context : _ dependencies) = context.database
    let issue (context : _ dependencies) = context.issue
  end

  module Authenticated = struct
    let database (context : _ authenticated) = context.dependencies.database
    let issue (context : _ authenticated) = context.dependencies.issue
    let user_id (context : _ authenticated) = context.user_id
  end

  module Optional_auth = struct
    let database (context : _ optional_auth) = context.dependencies.database
    let viewer_id (context : _ optional_auth) = context.viewer_id
  end

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
      ~map:(fun decode_error ->
        let field, message =
          match decode_error with
          | Decode_error.Invalid_parameter { name; _ } -> name, "is invalid"
          | Missing_parameter { name; _ } -> name, "is required"
          | Duplicate_parameter { name; _ } -> name, "must occur once"
          | Invalid_json _ | Invalid_body _ -> "body", "is invalid"
          | Unsupported_media_type _ -> "contentType", "is unsupported"
          | Body_too_large _ -> "body", "is too large"
        in
        Dto.Error_response.make [ field, [ message ] ])
  ;;
end
