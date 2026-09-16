open! Base
module Domain = Realworld_domain.Domain

let null_or_string = function
  | None -> `Null
  | Some value -> `String value
;;

let timestamp value = `String (Ptime.to_rfc3339 ~frac_s:3 value)

let errors values =
  `Assoc
    [ ( "errors"
      , `Assoc
          (List.map values ~f:(fun (field, messages) ->
             field, `List (List.map messages ~f:(fun message -> `String message)))) )
    ]
;;

let profile (profile : Domain.Profile.t) =
  `Assoc
    [ "username", `String (Domain.User.Username.to_string profile.username)
    ; "bio", null_or_string profile.bio
    ; "image", null_or_string profile.image
    ; "following", `Bool profile.following
    ]
;;

let user ~token (user : Domain.User.t) =
  `Assoc
    [ ( "user"
      , `Assoc
          [ "email", `String user.email
          ; "token", `String token
          ; "username", `String (Domain.User.Username.to_string user.username)
          ; "bio", null_or_string user.bio
          ; "image", null_or_string user.image
          ] )
    ]
;;

let article_json ~include_body (article : Domain.Article.t) =
  let fields =
    [ "slug", `String (Domain.Article.Slug.to_string article.slug)
    ; "title", `String article.title
    ; "description", `String article.description
    ; ( "tagList"
      , `List
          (List.map article.tag_list ~f:(fun tag ->
             `String (Domain.Article.Tag.to_string tag))) )
    ; "createdAt", timestamp article.created_at
    ; "updatedAt", timestamp article.updated_at
    ; "favorited", `Bool article.favorited
    ; "favoritesCount", `Int article.favorites_count
    ; "author", profile article.author
    ]
  in
  let fields =
    if include_body then
      ("body", `String article.body) :: fields
    else
      fields
  in
  `Assoc [ "article", `Assoc fields ]
;;

let article = article_json

let articles articles ~count =
  let item article =
    match article_json ~include_body:false article with
    | `Assoc [ (_, value) ] -> value
    | _ -> assert false
  in
  `Assoc [ "articles", `List (List.map articles ~f:item); "articlesCount", `Int count ]
;;

let comment_json (comment : Domain.Comment.t) =
  `Assoc
    [ ( "comment"
      , `Assoc
          [ "id", `Intlit (Domain.Comment.Id.to_string comment.id)
          ; "createdAt", timestamp comment.created_at
          ; "updatedAt", timestamp comment.updated_at
          ; "body", `String comment.body
          ; "author", profile comment.author
          ] )
    ]
;;

let comment = comment_json

let comments comments =
  let item comment =
    match comment_json comment with
    | `Assoc [ (_, value) ] -> value
    | _ -> assert false
  in
  `Assoc [ "comments", `List (List.map comments ~f:item) ]
;;

let tags values =
  `Assoc [ "tags", `List (List.map values ~f:(fun value -> `String value)) ]
;;

let object_field json name =
  match json with
  | `Assoc fields -> List.Assoc.find fields ~equal:String.equal name
  | _ -> None
;;

let required_string json name =
  match object_field json name with
  | Some (`String value) -> Ok value
  | Some _ -> Error (name ^ " must be a string")
  | None -> Error (name ^ " can't be blank")
;;

let optional_string json name =
  match object_field json name with
  | None -> Ok None
  | Some (`String value) -> Ok (Some value)
  | Some _ -> Error (name ^ " must be a string")
;;

let optional_nullable_string json name =
  match object_field json name with
  | None -> Ok Domain.Patch.Keep
  | Some `Null -> Ok Clear
  | Some (`String value) -> Ok (Set value)
  | Some _ -> Error (name ^ " must be a string or null")
;;

let optional_string_list json name =
  match object_field json name with
  | None -> Ok Domain.Patch.Keep
  | Some `Null -> Ok Clear
  | Some (`List values) ->
    values
    |> List.map ~f:(function
      | `String value -> Ok value
      | _ -> Error (name ^ " must contain strings"))
    |> Result.all
    |> Result.map ~f:(fun values -> Domain.Patch.Set values)
  | Some _ -> Error (name ^ " must be an array")
;;

let article_tags values =
  values
  |> List.map ~f:(fun value ->
    Domain.Article.Tag.of_string value
    |> Result.of_option ~error:"tagList must contain non-empty strings")
  |> Result.all
;;

let metadata name description =
  Typed_endpoint.Metadata.v
    ~schema:Typed_endpoint.Json_schema.any
    ~schema_name:name
    ~description
    ()
;;

let nested json name =
  match object_field json name with
  | Some (`Assoc _ as value) -> Ok value
  | Some _ -> Error (name ^ " must be an object")
  | None -> Error (name ^ " is required")
;;

module Error_response = struct
  type t = (string * string list) list

  let metadata : t Typed_endpoint.Metadata.t =
    metadata "Errors" "Validation or request errors grouped by field"
  ;;

  let make fields = fields
  let to_yojson = errors
end

module User_response = struct
  type t =
    { token : string
    ; user : Domain.User.t
    }

  let metadata : t Typed_endpoint.Metadata.t =
    metadata "UserResponse" "Authenticated user"
  ;;

  let make ~token user = { token; user }
  let to_yojson response = user ~token:response.token response.user
end

module Profile_response = struct
  type t = Domain.Profile.t

  let metadata : t Typed_endpoint.Metadata.t = metadata "ProfileResponse" "User profile"
  let make value = value
  let to_yojson value = `Assoc [ "profile", profile value ]
end

module Article_response = struct
  type t = Domain.Article.t

  let metadata : t Typed_endpoint.Metadata.t = metadata "ArticleResponse" "Article"
  let make value = value
  let to_yojson value = article ~include_body:true value
end

module Articles_response = struct
  type t =
    { articles : Domain.Article.t list
    ; count : int
    }

  let metadata : t Typed_endpoint.Metadata.t =
    metadata "ArticlesResponse" "A page of articles"
  ;;

  let make ~articles ~count = { articles; count }
  let to_yojson response = articles response.articles ~count:response.count
end

module Comment_response = struct
  type t = Domain.Comment.t

  let metadata : t Typed_endpoint.Metadata.t = metadata "CommentResponse" "Comment"
  let make value = value
  let to_yojson value = comment value
end

module Comments_response = struct
  type t = Domain.Comment.t list

  let metadata : t Typed_endpoint.Metadata.t =
    metadata "CommentsResponse" "Article comments"
  ;;

  let make values = values
  let to_yojson values = comments values
end

module Tags_response = struct
  type t = string list

  let metadata : t Typed_endpoint.Metadata.t = metadata "TagsResponse" "Known tags"
  let make values = values
  let to_yojson values = tags values
end

module Registration_request = struct
  type t = Domain.User.registration

  let metadata : t Typed_endpoint.Metadata.t =
    metadata "RegistrationRequest" "New user registration"
  ;;

  let of_yojson json =
    let open Result.Let_syntax in
    let%bind user = nested json "user" in
    let%bind email = required_string user "email" in
    let%bind username = required_string user "username" in
    let%map password = required_string user "password" in
    Domain.User.{ email; username; password }
  ;;
end

module Login_request = struct
  type t =
    { email : string
    ; password : string
    }

  let metadata : t Typed_endpoint.Metadata.t = metadata "LoginRequest" "User credentials"

  let of_yojson json =
    let open Result.Let_syntax in
    let%bind user = nested json "user" in
    let%bind email = required_string user "email" in
    let%map password = required_string user "password" in
    { email; password }
  ;;
end

module User_update_request = struct
  type t =
    | Valid of Domain.User.update
    | Invalid of string * string

  let metadata : t Typed_endpoint.Metadata.t =
    metadata "UserUpdateRequest" "Fields to update on the current user"
  ;;

  let of_yojson json =
    let open Result.Let_syntax in
    let%bind user = nested json "user" in
    match
      List.find [ "email"; "username"; "password" ] ~f:(fun name ->
        Yojson.Safe.equal (Option.value (object_field user name) ~default:`Null) `Null
        && Option.is_some (object_field user name))
    with
    | Some field -> Ok (Invalid (field, "must be a string"))
    | None ->
      let%bind email = optional_string user "email" in
      let%bind username = optional_string user "username" in
      let%bind password = optional_string user "password" in
      let%bind bio = optional_nullable_string user "bio" in
      let%map image = optional_nullable_string user "image" in
      Valid Domain.User.{ email; username; password; bio; image }
  ;;
end

module Article_create_request = struct
  type t = Domain.Article.create

  let metadata : t Typed_endpoint.Metadata.t =
    metadata "ArticleCreateRequest" "A new article"
  ;;

  let of_yojson json =
    let open Result.Let_syntax in
    let%bind article = nested json "article" in
    let%bind title = required_string article "title" in
    let%bind description = required_string article "description" in
    let%bind body = required_string article "body" in
    let%bind tag_list = optional_string_list article "tagList" in
    match tag_list with
    | Clear -> Error "tagList must be an array"
    | Keep ->
      Ok
        (Domain.Article.{ title; description; body; tag_list = [] }
         : Domain.Article.create)
    | Set tag_list ->
      let%map tag_list = article_tags tag_list in
      (Domain.Article.{ title; description; body; tag_list } : Domain.Article.create)
  ;;
end

module Article_update_request = struct
  type t =
    | Valid of Domain.Article.update
    | Invalid_tag_list

  let metadata : t Typed_endpoint.Metadata.t =
    metadata "ArticleUpdateRequest" "Fields to update on an article"
  ;;

  let of_yojson json =
    let open Result.Let_syntax in
    let%bind article = nested json "article" in
    let%bind title = optional_string article "title" in
    let%bind description = optional_string article "description" in
    let%bind body = optional_string article "body" in
    let%bind tag_list = optional_string_list article "tagList" in
    match tag_list with
    | Clear -> Ok Invalid_tag_list
    | Keep -> Ok (Valid Domain.Article.{ title; description; body; tag_list = None })
    | Set tag_list ->
      let%map tag_list = article_tags tag_list in
      Valid Domain.Article.{ title; description; body; tag_list = Some tag_list }
  ;;
end

module Comment_create_request = struct
  type t = string

  let metadata : t Typed_endpoint.Metadata.t =
    metadata "CommentCreateRequest" "A new article comment"
  ;;

  let of_yojson json =
    let open Result.Let_syntax in
    let%bind comment = nested json "comment" in
    required_string comment "body"
  ;;
end
