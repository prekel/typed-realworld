open! Base
open Typed_endpoint

module Make
    (Backend : Backend.S with type 'a io = 'a Lwt.t)
    (Comments : Realworld_application.Comment_service.S) =
struct
  module Contexts = Controller_context.Make (Backend)
  module Endpoint = Contexts.Endpoint
  open Endpoint
  open Io.Let_syntax

  let comment_json = Response.json (module Dto.Comment_response)
  let comments_json = Response.json (module Dto.Comments_response)
  let error_json = Response.json (module Dto.Error_response)
  let error fields = Dto.Error_response.make fields
  let slug = arg "slug" (Parameter.string ~description:"Article slug" ())
  let comment_id = arg "id" (Parameter.int ~description:"Comment identifier" ())
  let unavailable = error [ "server", [ "is temporarily unavailable" ] ]
  let not_found resource = error [ resource, [ "not found" ] ]

  let list ~context =
    let ok = case `OK comments_json in
    let missing = case `Not_found error_json in
    let unavailable_case = case `Internal_server_error error_json in
    get / "articles" /: slug / "comments"
    |> documented ~operation_id:"getComments" ~summary:"Get article comments"
    |> accepts Request.empty
    |> returns (ok <|> missing <|> unavailable_case)
    |> handle_with ~context
       @@ fun slug (optional_auth : _ Controller_context.optional_auth) () ->
       let%bind result =
         Comments.list
           ~database:optional_auth.Controller_context.dependencies.database
           ~viewer_id:optional_auth.Controller_context.viewer_id
           ~slug
       in
       match result with
       | Ok comments -> respond ok (Dto.Comments_response.make comments)
       | Error `Article_not_found -> respond missing (not_found "article")
       | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let create ~context =
    let created = case `Created comment_json in
    let invalid = case `Unprocessable_entity error_json in
    let missing = case `Not_found error_json in
    let unavailable_case = case `Internal_server_error error_json in
    post / "articles" /: slug / "comments"
    |> documented ~operation_id:"createComment" ~summary:"Create a comment"
    |> accepts (Request.json (module Dto.Comment_create_request))
    |> returns (created <|> invalid <|> missing <|> unavailable_case)
    |> handle_with ~context
       @@ fun slug (authenticated : _ Controller_context.authenticated) body ->
       let%bind result =
         Comments.create
           ~database:authenticated.Controller_context.dependencies.database
           ~author_id:authenticated.Controller_context.user_id
           ~slug
           ~body
       in
       match result with
       | Ok comment -> respond created (Dto.Comment_response.make comment)
       | Error (`Validation fields) -> respond invalid (error fields)
       | Error `Article_not_found -> respond missing (not_found "article")
       | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let delete_comment ~context =
    let no_content =
      case `No_content (Response.empty ~description:"Comment deleted" ())
    in
    let missing = case `Not_found error_json in
    let forbidden_case = case `Forbidden error_json in
    let unavailable_case = case `Internal_server_error error_json in
    delete / "articles" /: slug / "comments" /: comment_id
    |> documented ~operation_id:"deleteComment" ~summary:"Delete a comment"
    |> accepts Request.empty
    |> returns (no_content <|> missing <|> forbidden_case <|> unavailable_case)
    |> handle_with ~context
       @@ fun slug comment_id (authenticated : _ Controller_context.authenticated) () ->
       let%bind result =
         Comments.delete
           ~database:authenticated.Controller_context.dependencies.database
           ~author_id:authenticated.Controller_context.user_id
           ~slug
           ~comment_id
       in
       match result with
       | Ok () -> respond no_content ()
       | Error `Article_not_found -> respond missing (not_found "article")
       | Error `Comment_not_found -> respond missing (not_found "comment")
       | Error `Forbidden -> respond forbidden_case (error [ "comment", [ "forbidden" ] ])
       | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let group dependencies =
    let authenticated = Contexts.authenticated dependencies in
    let optional_auth = Contexts.optional_auth dependencies in
    Group.make
      ~prefix:[ "api" ]
      ~decode_error:Contexts.decode_error
      ~tags:[ "Comments" ]
      ~description:"Article comments"
      [ list ~context:optional_auth
      ; create ~context:authenticated
      ; delete_comment ~context:authenticated
      ]
  ;;
end
