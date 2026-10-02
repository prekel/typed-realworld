open! Base
open Typed_endpoint
module Domain = Realworld_domain.Domain

module Make
    (Backend : Backend.S with type 'a io = 'a Lwt.t)
    (Comments : Realworld_application.Comment_service.S) =
struct
  module Contexts = Controller_context.Make (Backend)
  module Endpoint = Contexts.Endpoint
  open Endpoint
  open Io.Let_syntax

  let error fields = Dto.Error_response.make fields

  let slug =
    arg
      "slug"
      (Endpoint_parameter.string_value
         (module Domain.Article.Slug)
         ~schema_name:"ArticleSlug"
         ~description:"Article slug"
         ())
  ;;

  let comment_id =
    arg
      "id"
      (Endpoint_parameter.entity_id
         (module Domain.Comment.Id)
         ~schema_name:"CommentId"
         ~description:"Comment identifier"
         ())
  ;;

  let unavailable = error [ "server", [ "is temporarily unavailable" ] ]
  let not_found resource = error [ resource, [ "not found" ] ]

  let list =
    get / "articles" /: slug / "comments"
    |> documented ~operation_id:"getComments" ~summary:"Get article comments"
    |> accepts Request.empty
    |> returns
         (case `OK (Response.json (module Dto.Comments_response))
          <|> case `Not_found (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun slug ok missing unavailable_case context () ->
    let database = Contexts.Optional_auth.database context in
    let viewer_id = Contexts.Optional_auth.viewer_id context in
    let%bind result = Comments.list ~database ~viewer_id ~slug in
    match result with
    | Ok comments -> respond ok (Dto.Comments_response.make comments)
    | Error `Article_not_found -> respond missing (not_found "article")
    | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let create =
    post / "articles" /: slug / "comments"
    |> documented ~operation_id:"createComment" ~summary:"Create a comment"
    |> accepts (Request.json (module Dto.Comment_create_request))
    |> returns
         (case `Created (Response.json (module Dto.Comment_response))
          <|> case `Unprocessable_entity (Response.json (module Dto.Error_response))
          <|> case `Not_found (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun slug created invalid missing unavailable_case context request_body ->
    let%bind body = Request_body.read request_body in
    match body with
    | Error body_error -> Request_body.reject body_error
    | Ok body ->
      let body = Dto.Comment_create_request.body body in
      let database = Contexts.Authenticated.database context in
      let user_id = Contexts.Authenticated.user_id context in
      let%bind result = Comments.create ~database ~author_id:user_id ~slug ~body in
      (match result with
       | Ok comment -> respond created (Dto.Comment_response.make comment)
       | Error (`Validation fields) -> respond invalid (error fields)
       | Error `Article_not_found -> respond missing (not_found "article")
       | Error (`Persistence _) -> respond unavailable_case unavailable)
  ;;

  let delete_comment =
    delete / "articles" /: slug / "comments" /: comment_id
    |> documented ~operation_id:"deleteComment" ~summary:"Delete a comment"
    |> accepts Request.empty
    |> returns
         (case `No_content (Response.empty ~description:"Comment deleted" ())
          <|> case `Not_found (Response.json (module Dto.Error_response))
          <|> case `Forbidden (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==>
    fun slug comment_id no_content missing forbidden_case unavailable_case context () ->
    let database = Contexts.Authenticated.database context in
    let user_id = Contexts.Authenticated.user_id context in
    let%bind result = Comments.delete ~database ~author_id:user_id ~slug ~comment_id in
    match result with
    | Ok () -> respond no_content ()
    | Error `Article_not_found -> respond missing (not_found "article")
    | Error `Comment_not_found -> respond missing (not_found "comment")
    | Error `Forbidden -> respond forbidden_case (error [ "comment", [ "forbidden" ] ])
    | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let groups dependencies =
    let group ~context ~description routes =
      Group.make_with_context
        ~context
        ~prefix:[ "api" ]
        ~decode_error:Contexts.decode_error
        ~tags:[ "Comments" ]
        ~description
        routes
    in
    [ group
        ~context:(Contexts.optional_auth dependencies)
        ~description:"Public comment queries"
        [ list ]
    ; group
        ~context:(Contexts.authenticated dependencies)
        ~description:"Authenticated comment operations"
        [ create; delete_comment ]
    ]
  ;;
end
