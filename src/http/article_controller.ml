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

  let tag_filter =
    arg
      "tag"
      (Endpoint_parameter.string_value
         (module Domain.Article.Tag)
         ~schema_name:"ArticleTag"
         ~description:"Filter by tag"
         ())
  ;;

  let username_filter name description =
    arg
      name
      (Endpoint_parameter.string_value
         (module Domain.User.Username)
         ~schema_name:"Username"
         ~description
         ())
  ;;

  let author_filter = username_filter "author" "Filter by author"
  let favorited_filter = username_filter "favorited" "Filter by users who favorited"

  let limit =
    arg
      "limit"
      (Endpoint_parameter.page_value
         (module Domain.Page.Limit)
         ~schema_name:"PageLimit"
         ~description:"Maximum number of articles"
         ())
  ;;

  let offset =
    arg
      "offset"
      (Endpoint_parameter.page_value
         (module Domain.Page.Offset)
         ~schema_name:"PageOffset"
         ~description:"Number of articles to skip"
         ())
  ;;

  let unavailable = error [ "server", [ "is temporarily unavailable" ] ]
  let not_found resource = error [ resource, [ "not found" ] ]
  let forbidden resource = error [ resource, [ "forbidden" ] ]
  let page limit offset = Domain.Page.create ?limit ?offset ()

  let list =
    get / "articles" /? tag_filter /? author_filter /? favorited_filter /? limit /? offset
    |> documented ~operation_id:"listArticles" ~summary:"List articles"
    |> accepts Request.empty
    |> returns
         (case `OK (Response.json (module Dto.Articles_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun tag author favorited limit offset ok unavailable_case context () ->
    let database = Contexts.Optional_auth.database context in
    let viewer_id = Contexts.Optional_auth.viewer_id context in
    let page = page limit offset in
    let filters = Domain.Article.{ tag; author; favorited_by = favorited } in
    let%bind result = Articles.list ~database ~viewer_id ~filters ~page in
    match result with
    | Ok page ->
      respond ok (Dto.Articles_response.make ~articles:page.articles ~count:page.count)
    | Error _ -> respond unavailable_case unavailable
  ;;

  let feed =
    get / "articles" / "feed" /? limit /? offset
    |> documented ~operation_id:"feedArticles" ~summary:"Get followed authors' articles"
    |> accepts Request.empty
    |> returns
         (case `OK (Response.json (module Dto.Articles_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun limit offset ok unavailable_case context () ->
    let database = Contexts.Authenticated.database context in
    let user_id = Contexts.Authenticated.user_id context in
    let page = page limit offset in
    let%bind result = Articles.feed ~database ~viewer_id:user_id ~page in
    match result with
    | Ok page ->
      respond ok (Dto.Articles_response.make ~articles:page.articles ~count:page.count)
    | Error _ -> respond unavailable_case unavailable
  ;;

  let find =
    get / "articles" /: slug
    |> documented ~operation_id:"getArticle" ~summary:"Get an article"
    |> accepts Request.empty
    |> returns
         (case `OK (Response.json (module Dto.Article_response))
          <|> case `Not_found (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun slug ok missing unavailable_case context () ->
    let database = Contexts.Optional_auth.database context in
    let viewer_id = Contexts.Optional_auth.viewer_id context in
    let%bind result = Articles.find ~database ~viewer_id ~slug in
    match result with
    | Ok (Some article) -> respond ok (Dto.Article_response.make article)
    | Ok None -> respond missing (not_found "article")
    | Error _ -> respond unavailable_case unavailable
  ;;

  let create =
    post / "articles"
    |> documented ~operation_id:"createArticle" ~summary:"Create an article"
    |> accepts (Request.json (module Dto.Article_create_request))
    |> returns
         (case `Created (Response.json (module Dto.Article_response))
          <|> case `Unprocessable_entity (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun created invalid unavailable_case context article ->
    let database = Contexts.Authenticated.database context in
    let user_id = Contexts.Authenticated.user_id context in
    let%bind result = Articles.create ~database ~author_id:user_id article in
    match result with
    | Ok article -> respond created (Dto.Article_response.make article)
    | Error (`Validation fields) -> respond invalid (error fields)
    | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let update =
    put / "articles" /: slug
    |> documented ~operation_id:"updateArticle" ~summary:"Update an article"
    |> accepts (Request.json (module Dto.Article_update_request))
    |> returns
         (case `OK (Response.json (module Dto.Article_response))
          <|> case `Unprocessable_entity (Response.json (module Dto.Error_response))
          <|> case `Not_found (Response.json (module Dto.Error_response))
          <|> case `Forbidden (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun slug ok invalid missing forbidden_case unavailable_case context request ->
    let database = Contexts.Authenticated.database context in
    let user_id = Contexts.Authenticated.user_id context in
    match request with
    | Dto.Article_update_request.Invalid_tag_list ->
      respond invalid (error [ "tagList", [ "must be an array" ] ])
    | Valid changes ->
      let%bind result = Articles.update ~database ~author_id:user_id ~slug changes in
      (match result with
       | Ok article -> respond ok (Dto.Article_response.make article)
       | Error (`Validation fields) -> respond invalid (error fields)
       | Error `Not_found -> respond missing (not_found "article")
       | Error `Forbidden -> respond forbidden_case (forbidden "article")
       | Error (`Persistence _) -> respond unavailable_case unavailable)
  ;;

  let delete_article =
    delete / "articles" /: slug
    |> documented ~operation_id:"deleteArticle" ~summary:"Delete an article"
    |> accepts Request.empty
    |> returns
         (case `No_content (Response.empty ~description:"Article deleted" ())
          <|> case `Not_found (Response.json (module Dto.Error_response))
          <|> case `Forbidden (Response.json (module Dto.Error_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun slug no_content missing forbidden_case unavailable_case context () ->
    let database = Contexts.Authenticated.database context in
    let user_id = Contexts.Authenticated.user_id context in
    let%bind result = Articles.delete ~database ~author_id:user_id ~slug in
    match result with
    | Ok () -> respond no_content ()
    | Error `Not_found -> respond missing (not_found "article")
    | Error `Forbidden -> respond forbidden_case (forbidden "article")
    | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let favorite ~add =
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
      |> returns
           (case `OK (Response.json (module Dto.Article_response))
            <|> case `Not_found (Response.json (module Dto.Error_response))
            <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    in
    declaration ==> fun slug ok missing unavailable_case context () ->
    let database = Contexts.Authenticated.database context in
    let user_id = Contexts.Authenticated.user_id context in
    let call =
      if add then
        Articles.favorite
      else
        Articles.unfavorite
    in
    let%bind result = call ~database ~user_id ~slug in
    match result with
    | Ok article -> respond ok (Dto.Article_response.make article)
    | Error `Not_found -> respond missing (not_found "article")
    | Error (`Persistence _) -> respond unavailable_case unavailable
  ;;

  let tags =
    get / "tags"
    |> documented ~operation_id:"getTags" ~summary:"Get tags"
    |> accepts Request.empty
    |> returns
         (case `OK (Response.json (module Dto.Tags_response))
          <|> case `Internal_server_error (Response.json (module Dto.Error_response)))
    ==> fun ok unavailable_case context () ->
    let database = Contexts.Public.database context in
    let%bind result = Articles.tags ~database in
    match result with
    | Ok tags -> respond ok (Dto.Tags_response.make tags)
    | Error _ -> respond unavailable_case unavailable
  ;;

  let groups dependencies =
    let group ~context ~tags ~description routes =
      Group.make_with_context
        ~context
        ~prefix:[ "api" ]
        ~decode_error:Contexts.decode_error
        ~tags
        ~description
        routes
    in
    [ group
        ~context:(Contexts.optional_auth dependencies)
        ~tags:[ "Articles" ]
        ~description:"Public article queries"
        [ list; find ]
    ; group
        ~context:(Contexts.authenticated dependencies)
        ~tags:[ "Articles" ]
        ~description:"Authenticated article operations"
        [ feed; create; update; delete_article; favorite ~add:true; favorite ~add:false ]
    ; group
        ~context:(Contexts.public dependencies)
        ~tags:[ "Tags" ]
        ~description:"Tags"
        [ tags ]
    ]
  ;;
end
