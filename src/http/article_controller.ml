open! Base
open Typed_endpoint
module Domain = Realworld_domain.Domain

module Make
    (Backend : Backend.S with type 'a io = 'a Lwt.t)
    (Articles : Realworld_application.Article_service.S) =
struct
  module Contexts = Controller_context.Make (Backend)
  module Endpoint = Contexts.Endpoint
  open Endpoint
  open Io.Let_syntax

  let article_json = Response.json (module Dto.Article_response)
  let articles_json = Response.json (module Dto.Articles_response)
  let tags_json = Response.json (module Dto.Tags_response)
  let error_json = Response.json (module Dto.Error_response)
  let error fields = Dto.Error_response.make fields
  let slug = arg "slug" (Parameter.string ~description:"Article slug" ())
  let filter name description = arg name (Parameter.string ~description ())
  let limit = arg "limit" (Parameter.int ~description:"Maximum number of articles" ())
  let offset = arg "offset" (Parameter.int ~description:"Number of articles to skip" ())
  let unavailable = error [ "server", [ "is temporarily unavailable" ] ]
  let not_found resource = error [ resource, [ "not found" ] ]
  let forbidden resource = error [ resource, [ "forbidden" ] ]
  let page limit offset = Domain.Page.create ?limit ?offset ()

  let list ~context =
    let ok = case `OK articles_json in
    let invalid = case `Unprocessable_entity error_json in
    let unavailable_case = case `Internal_server_error error_json in
    get
    / "articles"
    /? filter "tag" "Filter by tag"
    /? filter "author" "Filter by author"
    /? filter "favorited" "Filter by users who favorited"
    /? limit
    /? offset
    |> documented ~operation_id:"listArticles" ~summary:"List articles"
    |> accepts Request.empty
    |> returns (ok <|> invalid <|> unavailable_case)
    |> handle_with ~context
       @@
       fun tag
         author
         favorited
         limit
         offset
         (optional_auth : _ Controller_context.optional_auth)
         () ->
       match page limit offset with
       | Error message -> respond invalid (error [ "pagination", [ message ] ])
       | Ok page ->
         let filters =
           Domain.Article.
             { tag
             ; author = Option.map author ~f:String.lowercase
             ; favorited_by = Option.map favorited ~f:String.lowercase
             }
         in
         let%bind result =
           Articles.list
             ~database:optional_auth.Controller_context.dependencies.database
             ~viewer_id:optional_auth.Controller_context.viewer_id
             ~filters
             ~page
         in
         (match result with
          | Ok page ->
            respond
              ok
              (Dto.Articles_response.make ~articles:page.articles ~count:page.count)
          | Error _ -> respond unavailable_case unavailable)
  ;;

  let feed ~context =
    let ok = case `OK articles_json in
    let invalid = case `Unprocessable_entity error_json in
    let unavailable_case = case `Internal_server_error error_json in
    get / "articles" / "feed" /? limit /? offset
    |> documented ~operation_id:"feedArticles" ~summary:"Get followed authors' articles"
    |> accepts Request.empty
    |> returns (ok <|> invalid <|> unavailable_case)
    |> handle_with ~context
       @@ fun limit offset (authenticated : _ Controller_context.authenticated) () ->
       match page limit offset with
       | Error message -> respond invalid (error [ "pagination", [ message ] ])
       | Ok page ->
         let%bind result =
           Articles.feed
             ~database:authenticated.Controller_context.dependencies.database
             ~viewer_id:authenticated.Controller_context.user_id
             ~page
         in
         (match result with
          | Ok page ->
            respond
              ok
              (Dto.Articles_response.make ~articles:page.articles ~count:page.count)
          | Error _ -> respond unavailable_case unavailable)
  ;;

  let find ~context =
    let ok = case `OK article_json in
    let missing = case `Not_found error_json in
    let unavailable_case = case `Internal_server_error error_json in
    get / "articles" /: slug
    |> documented ~operation_id:"getArticle" ~summary:"Get an article"
    |> accepts Request.empty
    |> returns (ok <|> missing <|> unavailable_case)
    |> handle_with ~context
       @@ fun slug (optional_auth : _ Controller_context.optional_auth) () ->
       let%bind result =
         Articles.find
           ~database:optional_auth.Controller_context.dependencies.database
           ~viewer_id:optional_auth.Controller_context.viewer_id
           ~slug
       in
       match result with
       | Ok (Some article) -> respond ok (Dto.Article_response.make article)
       | Ok None -> respond missing (not_found "article")
       | Error _ -> respond unavailable_case unavailable
  ;;

  let create ~context =
    let created = case `Created article_json in
    let invalid = case `Unprocessable_entity error_json in
    let unavailable_case = case `Internal_server_error error_json in
    post / "articles"
    |> documented ~operation_id:"createArticle" ~summary:"Create an article"
    |> accepts (Request.json (module Dto.Article_create_request))
    |> returns (created <|> invalid <|> unavailable_case)
    |> handle_with ~context
       @@ fun (authenticated : _ Controller_context.authenticated) article ->
       let%bind result =
         Articles.create
           ~database:authenticated.Controller_context.dependencies.database
           ~author_id:authenticated.Controller_context.user_id
           article
       in
       match result with
       | Ok article -> respond created (Dto.Article_response.make article)
       | Error (`Validation fields) -> respond invalid (error fields)
       | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let update ~context =
    let ok = case `OK article_json in
    let invalid = case `Unprocessable_entity error_json in
    let missing = case `Not_found error_json in
    let forbidden_case = case `Forbidden error_json in
    let unavailable_case = case `Internal_server_error error_json in
    put / "articles" /: slug
    |> documented ~operation_id:"updateArticle" ~summary:"Update an article"
    |> accepts (Request.json (module Dto.Article_update_request))
    |> returns (ok <|> invalid <|> missing <|> forbidden_case <|> unavailable_case)
    |> handle_with ~context
       @@ fun slug (authenticated : _ Controller_context.authenticated) request ->
       match request with
       | Dto.Article_update_request.Invalid_tag_list ->
         respond invalid (error [ "tagList", [ "must be an array" ] ])
       | Valid changes ->
         let%bind result =
           Articles.update
             ~database:authenticated.Controller_context.dependencies.database
             ~author_id:authenticated.Controller_context.user_id
             ~slug
             changes
         in
         (match result with
          | Ok article -> respond ok (Dto.Article_response.make article)
          | Error (`Validation fields) -> respond invalid (error fields)
          | Error `Not_found -> respond missing (not_found "article")
          | Error `Forbidden -> respond forbidden_case (forbidden "article")
          | Error (`Persistence _) -> respond unavailable_case unavailable)
  ;;

  let delete_article ~context =
    let no_content =
      case `No_content (Response.empty ~description:"Article deleted" ())
    in
    let missing = case `Not_found error_json in
    let forbidden_case = case `Forbidden error_json in
    let unavailable_case = case `Internal_server_error error_json in
    delete / "articles" /: slug
    |> documented ~operation_id:"deleteArticle" ~summary:"Delete an article"
    |> accepts Request.empty
    |> returns (no_content <|> missing <|> forbidden_case <|> unavailable_case)
    |> handle_with ~context
       @@ fun slug (authenticated : _ Controller_context.authenticated) () ->
       let%bind result =
         Articles.delete
           ~database:authenticated.Controller_context.dependencies.database
           ~author_id:authenticated.Controller_context.user_id
           ~slug
       in
       match result with
       | Ok () -> respond no_content ()
       | Error `Not_found -> respond missing (not_found "article")
       | Error `Forbidden -> respond forbidden_case (forbidden "article")
       | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let favorite ~context ~add =
    let ok = case `OK article_json in
    let missing = case `Not_found error_json in
    let unavailable_case = case `Internal_server_error error_json in
    let declaration =
      (if add then
         post
       else
         delete)
      / "articles" /: slug / "favorite"
      |> documented
           ~operation_id:
             (if add then
                "favoriteArticle"
              else
                "unfavoriteArticle")
           ~summary:
             (if add then
                "Favorite an article"
              else
                "Unfavorite an article")
      |> accepts Request.empty
      |> returns (ok <|> missing <|> unavailable_case)
    in
    declaration
    |> handle_with ~context
       @@ fun slug (authenticated : _ Controller_context.authenticated) () ->
       let call =
         if add then
           Articles.favorite
         else
           Articles.unfavorite
       in
       let%bind result =
         call
           ~database:authenticated.Controller_context.dependencies.database
           ~user_id:authenticated.Controller_context.user_id
           ~slug
       in
       match result with
       | Ok article -> respond ok (Dto.Article_response.make article)
       | Error `Not_found -> respond missing (not_found "article")
       | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let tags ~context =
    let ok = case `OK tags_json in
    let unavailable_case = case `Internal_server_error error_json in
    get / "tags"
    |> documented ~operation_id:"getTags" ~summary:"Get tags"
    |> accepts Request.empty
    |> returns (ok <|> unavailable_case)
    |> handle_with ~context
       @@ fun (dependencies : _ Controller_context.dependencies) () ->
       let%bind result =
         Articles.tags ~database:dependencies.Controller_context.database
       in
       match result with
       | Ok tags -> respond ok (Dto.Tags_response.make tags)
       | Error _ -> respond unavailable_case unavailable
  ;;

  let groups dependencies =
    let public = Contexts.public dependencies in
    let authenticated = Contexts.authenticated dependencies in
    let optional_auth = Contexts.optional_auth dependencies in
    [ Group.make
        ~prefix:[ "api" ]
        ~decode_error:Contexts.decode_error
        ~tags:[ "Articles" ]
        ~description:"Articles"
        [ list ~context:optional_auth
        ; feed ~context:authenticated
        ; find ~context:optional_auth
        ; create ~context:authenticated
        ; update ~context:authenticated
        ; delete_article ~context:authenticated
        ; favorite ~context:authenticated ~add:true
        ; favorite ~context:authenticated ~add:false
        ]
    ; Group.make
        ~prefix:[ "api" ]
        ~decode_error:Contexts.decode_error
        ~tags:[ "Tags" ]
        ~description:"Tags"
        [ tags ~context:public ]
    ]
  ;;
end
