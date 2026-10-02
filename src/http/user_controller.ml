open! Base
open Typed_endpoint
module Domain = Realworld_domain.Domain

module Make
    (Backend : Backend.S with type 'a io = 'a Lwt.t)
    (Users : Realworld_application.User_service.S) =
struct
  module Contexts = Controller_context.Make (Backend)
  module Endpoint = Contexts.Endpoint
  open Endpoint
  open Io.Let_syntax

  let error fields = Dto.Error_response.make fields

  let username =
    arg
      "username"
      (Endpoint_parameter.string_value
         (module Domain.User.Username)
         ~schema_name:"Username"
         ~description:"Username"
         ())
  ;;

  let unavailable = error [ "server", [ "is temporarily unavailable" ] ]
  let not_found resource = error [ resource, [ "not found" ] ]

  let register =
    post / "users"
    |> documented ~operation_id:"registerUser" ~summary:"Register a user"
    |> accepts (Request.json (module Dto.Registration_request))
    |> returns
         (case `Created (Response.json (module Dto.User_response))
          <|> case `Unprocessable_entity (Response.json (module Dto.Error_response))
          <|> case `Conflict (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun created invalid conflict unavailable_case context body ->
    let%bind registration = Request_body.read body in
    match registration with
    | Error body_error -> Request_body.reject body_error
    | Ok registration ->
      let registration = Dto.Registration_request.to_domain registration in
      let database = Contexts.Public.database context in
      let issue = Contexts.Public.issue context in
      let%bind result = Users.register ~database registration in
      (match result with
       | Ok user ->
         respond created (Dto.User_response.make ~token:(issue ~user_id:user.id) user)
       | Error (`Validation fields) -> respond invalid (error fields)
       | Error `Email_taken ->
         respond conflict (error [ "email", [ "has already been taken" ] ])
       | Error `Username_taken ->
         respond conflict (error [ "username", [ "has already been taken" ] ])
       | Error (`Persistence _) -> respond unavailable_case unavailable)
  ;;

  let login =
    post / "users" / "login"
    |> documented ~operation_id:"loginUser" ~summary:"Log in"
    |> accepts (Request.json (module Dto.Login_request))
    |> returns
         (case `OK (Response.json (module Dto.User_response))
          <|> case `Unprocessable_entity (Response.json (module Dto.Error_response))
          <|> case `Unauthorized (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun ok invalid unauthorized unavailable_case context body ->
    let%bind credentials = Request_body.read body in
    match credentials with
    | Error body_error -> Request_body.reject body_error
    | Ok credentials ->
      let email = Dto.Login_request.email credentials in
      let password = Dto.Login_request.password credentials in
      let database = Contexts.Public.database context in
      let issue = Contexts.Public.issue context in
      if String.is_empty (String.strip email) then
        respond invalid (error [ "email", [ "can't be blank" ] ])
      else if String.is_empty (String.strip password) then
        respond invalid (error [ "password", [ "can't be blank" ] ])
      else (
        let%bind result = Users.login ~database ~email ~password in
        match result with
        | Ok user ->
          respond ok (Dto.User_response.make ~token:(issue ~user_id:user.id) user)
        | Error `Invalid_credentials ->
          respond unauthorized (error [ "credentials", [ "invalid" ] ])
        | Error (`Persistence _) -> respond unavailable_case unavailable)
  ;;

  let current =
    get / "user"
    |> documented ~operation_id:"getCurrentUser" ~summary:"Get current user"
    |> accepts Request.empty
    |> returns
         (case `OK (Response.json (module Dto.User_response))
          <|> case `Unauthorized (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun ok unauthorized unavailable_case context () ->
    let database = Contexts.Authenticated.database context in
    let issue = Contexts.Authenticated.issue context in
    let user_id = Contexts.Authenticated.user_id context in
    let%bind result = Users.current ~database user_id in
    match result with
    | Ok user -> respond ok (Dto.User_response.make ~token:(issue ~user_id:user.id) user)
    | Error `Unauthorized -> respond unauthorized (error [ "token", [ "is invalid" ] ])
    | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let update =
    put / "user"
    |> documented ~operation_id:"updateCurrentUser" ~summary:"Update current user"
    |> accepts (Request.json (module Dto.User_update_request))
    |> returns
         (case `OK (Response.json (module Dto.User_response))
          <|> case `Unprocessable_entity (Response.json (module Dto.Error_response))
          <|> case `Conflict (Response.json (module Dto.Error_response))
          <|> case `Unauthorized (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun ok invalid conflict unauthorized unavailable_case context body ->
    let%bind request = Request_body.read body in
    match request with
    | Error body_error -> Request_body.reject body_error
    | Ok request ->
      (match Dto.User_update_request.to_domain request with
       | Error (field, message) -> respond invalid (error [ field, [ message ] ])
       | Ok changes ->
         let database = Contexts.Authenticated.database context in
         let issue = Contexts.Authenticated.issue context in
         let user_id = Contexts.Authenticated.user_id context in
         let%bind result = Users.update ~database ~user_id changes in
         (match result with
          | Ok user ->
            respond ok (Dto.User_response.make ~token:(issue ~user_id:user.id) user)
          | Error (`Validation fields) -> respond invalid (error fields)
          | Error `Email_taken ->
            respond conflict (error [ "email", [ "has already been taken" ] ])
          | Error `Username_taken ->
            respond conflict (error [ "username", [ "has already been taken" ] ])
          | Error `Unauthorized ->
            respond unauthorized (error [ "token", [ "is invalid" ] ])
          | Error (`Persistence _) -> respond unavailable_case unavailable))
  ;;

  let profile =
    get / "profiles" /: username
    |> documented ~operation_id:"getProfile" ~summary:"Get a profile"
    |> accepts Request.empty
    |> returns
         (case `OK (Response.json (module Dto.Profile_response))
          <|> case `Not_found (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun username ok missing unavailable_case context () ->
    let database = Contexts.Optional_auth.database context in
    let viewer_id = Contexts.Optional_auth.viewer_id context in
    let%bind result = Users.profile ~database ~viewer_id ~username in
    match result with
    | Ok (Some profile) -> respond ok (Dto.Profile_response.make profile)
    | Ok None -> respond missing (not_found "profile")
    | Error _ -> respond unavailable_case unavailable
  ;;

  let follow =
    post / "profiles" /: username / "follow"
    |> documented ~operation_id:"followUser" ~summary:"Follow a user"
    |> accepts Request.empty
    |> returns
         (case `OK (Response.json (module Dto.Profile_response))
          <|> case `Not_found (Response.json (module Dto.Error_response))
          <|> case `Unprocessable_entity (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun username ok missing invalid unavailable_case context () ->
    let database = Contexts.Authenticated.database context in
    let user_id = Contexts.Authenticated.user_id context in
    let%bind result = Users.follow ~database ~follower_id:user_id ~username in
    match result with
    | Ok profile -> respond ok (Dto.Profile_response.make profile)
    | Error `Cannot_follow_self ->
      respond invalid (error [ "profile", [ "cannot follow yourself" ] ])
    | Error `Not_found -> respond missing (not_found "profile")
    | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let unfollow =
    delete / "profiles" /: username / "follow"
    |> documented ~operation_id:"unfollowUser" ~summary:"Unfollow a user"
    |> accepts Request.empty
    |> returns
         (case `OK (Response.json (module Dto.Profile_response))
          <|> case `Not_found (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun username ok missing unavailable_case context () ->
    let database = Contexts.Authenticated.database context in
    let user_id = Contexts.Authenticated.user_id context in
    let%bind result = Users.unfollow ~database ~follower_id:user_id ~username in
    match result with
    | Ok profile -> respond ok (Dto.Profile_response.make profile)
    | Error `Not_found -> respond missing (not_found "profile")
    | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let groups dependencies =
    let group ~context ~description routes =
      Group.make_with_context
        ~context
        ~prefix:[ "api" ]
        ~decode_error:Contexts.decode_error
        ~tags:[ "Users" ]
        ~description
        routes
    in
    [ group
        ~context:(Contexts.public dependencies)
        ~description:"Public user operations"
        [ register; login ]
    ; group
        ~context:(Contexts.authenticated dependencies)
        ~description:"Authenticated user operations"
        [ current; update; follow; unfollow ]
    ; group
        ~context:(Contexts.optional_auth dependencies)
        ~description:"Public profiles with optional authentication"
        [ profile ]
    ]
  ;;
end
