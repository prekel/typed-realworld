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

  let user_json = Response.json (module Dto.User_response)
  let profile_json = Response.json (module Dto.Profile_response)
  let error_json = Response.json (module Dto.Error_response)
  let error fields = Dto.Error_response.make fields
  let username = arg "username" (Parameter.string ~description:"Username" ())
  let unavailable = error [ "server", [ "is temporarily unavailable" ] ]
  let not_found resource = error [ resource, [ "not found" ] ]

  let register ~context =
    let created = case `Created user_json in
    let invalid = case `Unprocessable_entity error_json in
    let conflict = case `Conflict error_json in
    let unavailable_case = case `Internal_server_error error_json in
    post / "users"
    |> documented ~operation_id:"registerUser" ~summary:"Register a user"
    |> accepts (Request.json (module Dto.Registration_request))
    |> returns (created <|> invalid <|> conflict <|> unavailable_case)
    |> handle_with ~context
       @@ fun (dependencies : _ Controller_context.dependencies) registration ->
       let%bind result =
         Users.register ~database:dependencies.Controller_context.database registration
       in
       match result with
       | Ok user ->
         respond
           created
           (Dto.User_response.make
              ~token:(dependencies.Controller_context.issue ~user_id:user.id)
              user)
       | Error (`Validation fields) -> respond invalid (error fields)
       | Error `Email_taken ->
         respond conflict (error [ "email", [ "has already been taken" ] ])
       | Error `Username_taken ->
         respond conflict (error [ "username", [ "has already been taken" ] ])
       | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let login ~context =
    let ok = case `OK user_json in
    let invalid = case `Unprocessable_entity error_json in
    let unauthorized = case `Unauthorized error_json in
    let unavailable_case = case `Internal_server_error error_json in
    post / "users" / "login"
    |> documented ~operation_id:"loginUser" ~summary:"Log in"
    |> accepts (Request.json (module Dto.Login_request))
    |> returns (ok <|> invalid <|> unauthorized <|> unavailable_case)
    |> handle_with ~context
       @@ fun (dependencies : _ Controller_context.dependencies) credentials ->
       if String.is_empty (String.strip credentials.Dto.Login_request.email) then
         respond invalid (error [ "email", [ "can't be blank" ] ])
       else if String.is_empty (String.strip credentials.Dto.Login_request.password) then
         respond invalid (error [ "password", [ "can't be blank" ] ])
       else (
         let%bind result =
           Users.login
             ~database:dependencies.Controller_context.database
             ~email:credentials.Dto.Login_request.email
             ~password:credentials.Dto.Login_request.password
         in
         match result with
         | Ok user ->
           respond
             ok
             (Dto.User_response.make
                ~token:(dependencies.Controller_context.issue ~user_id:user.id)
                user)
         | Error `Invalid_credentials ->
           respond unauthorized (error [ "credentials", [ "invalid" ] ])
         | Error (`Persistence _) -> respond unavailable_case unavailable)
  ;;

  let current ~context =
    let ok = case `OK user_json in
    let unauthorized = case `Unauthorized error_json in
    let unavailable_case = case `Internal_server_error error_json in
    get / "user"
    |> documented ~operation_id:"getCurrentUser" ~summary:"Get current user"
    |> accepts Request.empty
    |> returns (ok <|> unauthorized <|> unavailable_case)
    |> handle_with ~context
       @@ fun (authenticated : _ Controller_context.authenticated) () ->
       let dependencies = authenticated.Controller_context.dependencies in
       let%bind result =
         Users.current
           ~database:dependencies.Controller_context.database
           authenticated.Controller_context.user_id
       in
       match result with
       | Ok user ->
         respond
           ok
           (Dto.User_response.make
              ~token:(dependencies.Controller_context.issue ~user_id:user.id)
              user)
       | Error `Unauthorized -> respond unauthorized (error [ "token", [ "is invalid" ] ])
       | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let update ~context =
    let ok = case `OK user_json in
    let invalid = case `Unprocessable_entity error_json in
    let conflict = case `Conflict error_json in
    let unauthorized = case `Unauthorized error_json in
    let unavailable_case = case `Internal_server_error error_json in
    put / "user"
    |> documented ~operation_id:"updateCurrentUser" ~summary:"Update current user"
    |> accepts (Request.json (module Dto.User_update_request))
    |> returns (ok <|> invalid <|> conflict <|> unauthorized <|> unavailable_case)
    |> handle_with ~context
       @@ fun (authenticated : _ Controller_context.authenticated) request ->
       match request with
       | Dto.User_update_request.Invalid (field, message) ->
         respond invalid (error [ field, [ message ] ])
       | Valid changes ->
         let dependencies = authenticated.Controller_context.dependencies in
         let%bind result =
           Users.update
             ~database:dependencies.Controller_context.database
             ~user_id:authenticated.Controller_context.user_id
             changes
         in
         (match result with
          | Ok user ->
            respond
              ok
              (Dto.User_response.make
                 ~token:(dependencies.Controller_context.issue ~user_id:user.id)
                 user)
          | Error (`Validation fields) -> respond invalid (error fields)
          | Error `Email_taken ->
            respond conflict (error [ "email", [ "has already been taken" ] ])
          | Error `Username_taken ->
            respond conflict (error [ "username", [ "has already been taken" ] ])
          | Error `Unauthorized ->
            respond unauthorized (error [ "token", [ "is invalid" ] ])
          | Error (`Persistence _) -> respond unavailable_case unavailable)
  ;;

  let profile ~context =
    let ok = case `OK profile_json in
    let missing = case `Not_found error_json in
    let unavailable_case = case `Internal_server_error error_json in
    get / "profiles" /: username
    |> documented ~operation_id:"getProfile" ~summary:"Get a profile"
    |> accepts Request.empty
    |> returns (ok <|> missing <|> unavailable_case)
    |> handle_with ~context
       @@ fun username (optional_auth : _ Controller_context.optional_auth) () ->
       let%bind result =
         Users.profile
           ~database:optional_auth.Controller_context.dependencies.database
           ~viewer_id:optional_auth.Controller_context.viewer_id
           ~username
       in
       match result with
       | Ok (Some profile) -> respond ok (Dto.Profile_response.make profile)
       | Ok None -> respond missing (not_found "profile")
       | Error _ -> respond unavailable_case unavailable
  ;;

  let follow ~context =
    let ok = case `OK profile_json in
    let missing = case `Not_found error_json in
    let invalid = case `Unprocessable_entity error_json in
    let unavailable_case = case `Internal_server_error error_json in
    post / "profiles" /: username / "follow"
    |> documented ~operation_id:"followUser" ~summary:"Follow a user"
    |> accepts Request.empty
    |> returns (ok <|> missing <|> invalid <|> unavailable_case)
    |> handle_with ~context
       @@ fun username (authenticated : _ Controller_context.authenticated) () ->
       let%bind result =
         Users.follow
           ~database:authenticated.Controller_context.dependencies.database
           ~follower_id:authenticated.Controller_context.user_id
           ~username
       in
       match result with
       | Ok profile -> respond ok (Dto.Profile_response.make profile)
       | Error `Cannot_follow_self ->
         respond invalid (error [ "profile", [ "cannot follow yourself" ] ])
       | Error `Not_found -> respond missing (not_found "profile")
       | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let unfollow ~context =
    let ok = case `OK profile_json in
    let missing = case `Not_found error_json in
    let unavailable_case = case `Internal_server_error error_json in
    delete / "profiles" /: username / "follow"
    |> documented ~operation_id:"unfollowUser" ~summary:"Unfollow a user"
    |> accepts Request.empty
    |> returns (ok <|> missing <|> unavailable_case)
    |> handle_with ~context
       @@ fun username (authenticated : _ Controller_context.authenticated) () ->
       let%bind result =
         Users.unfollow
           ~database:authenticated.Controller_context.dependencies.database
           ~follower_id:authenticated.Controller_context.user_id
           ~username
       in
       match result with
       | Ok profile -> respond ok (Dto.Profile_response.make profile)
       | Error `Not_found -> respond missing (not_found "profile")
       | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let group dependencies =
    let public = Contexts.public dependencies in
    let authenticated = Contexts.authenticated dependencies in
    let optional_auth = Contexts.optional_auth dependencies in
    Group.make
      ~prefix:[ "api" ]
      ~decode_error:Contexts.decode_error
      ~tags:[ "Users" ]
      ~description:"Users and profiles"
      [ register ~context:public
      ; login ~context:public
      ; current ~context:authenticated
      ; update ~context:authenticated
      ; profile ~context:optional_auth
      ; follow ~context:authenticated
      ; unfollow ~context:authenticated
      ]
  ;;
end
