open! Base
module Domain = Realworld_domain.Domain
module Json_schema = Typed_endpoint.Json_schema

module Generated_schema = struct
  module String_value = struct
    type t = string [@@deriving jsonschema]
  end

  module Boolean_value = struct
    type t = bool [@@deriving jsonschema]
  end

  module String_list = struct
    type t = string list [@@deriving jsonschema]
  end
end

module Wire = struct
  type profile =
    { username : string
    ; bio : string option
    ; image : string option
    ; following : bool
    }
  [@@deriving yojson, jsonschema { strict = true }]

  type user =
    { email : string
    ; token : string
    ; username : string
    ; bio : string option
    ; image : string option
    }
  [@@deriving yojson, jsonschema { strict = true }]

  type article =
    { body : string
    ; slug : string
    ; title : string
    ; description : string
    ; tag_list : string list [@key "tagList"]
    ; created_at : string [@key "createdAt"]
    ; updated_at : string [@key "updatedAt"]
    ; favorited : bool
    ; favorites_count : int [@key "favoritesCount"]
    ; author : profile
    }
  [@@deriving yojson, jsonschema { strict = true }]

  type article_list_item =
    { slug : string
    ; title : string
    ; description : string
    ; tag_list : string list [@key "tagList"]
    ; created_at : string [@key "createdAt"]
    ; updated_at : string [@key "updatedAt"]
    ; favorited : bool
    ; favorites_count : int [@key "favoritesCount"]
    ; author : profile
    }
  [@@deriving yojson, jsonschema { strict = true }]

  type comment =
    { id : int64
    ; created_at : string [@key "createdAt"]
    ; updated_at : string [@key "updatedAt"]
    ; body : string
    ; author : profile
    }
  [@@deriving yojson, jsonschema { strict = true }]

  type user_response = { user : user } [@@deriving yojson, jsonschema { strict = true }]

  type profile_response = { profile : profile }
  [@@deriving yojson, jsonschema { strict = true }]

  type article_response = { article : article }
  [@@deriving yojson, jsonschema { strict = true }]

  type articles_response =
    { articles : article_list_item list
    ; articles_count : int [@key "articlesCount"]
    }
  [@@deriving yojson, jsonschema { strict = true }]

  type comment_response = { comment : comment }
  [@@deriving yojson, jsonschema { strict = true }]

  type comments_response = { comments : comment list }
  [@@deriving yojson, jsonschema { strict = true }]

  type tags_response = { tags : string list }
  [@@deriving yojson, jsonschema { strict = true }]

  type registration_user =
    { email : string
    ; username : string
    ; password : string
    }
  [@@deriving jsonschema { strict = true }]

  type registration_request = { user : registration_user }
  [@@deriving jsonschema { strict = true }]

  type login_user =
    { email : string
    ; password : string
    }
  [@@deriving jsonschema { strict = true }]

  type login_request = { user : login_user } [@@deriving jsonschema { strict = true }]

  type user_update =
    { email : string option option [@jsonschema.option]
    ; username : string option option [@jsonschema.option]
    ; password : string option option [@jsonschema.option]
    ; bio : string option option [@jsonschema.option]
    ; image : string option option [@jsonschema.option]
    }
  [@@deriving jsonschema { strict = true }]

  type user_update_request = { user : user_update }
  [@@deriving jsonschema { strict = true }]

  type article_create =
    { title : string
    ; description : string
    ; body : string
    ; tag_list : string list option [@key "tagList"] [@jsonschema.option]
    }
  [@@deriving jsonschema { strict = true }]

  type article_create_request = { article : article_create }
  [@@deriving jsonschema { strict = true }]

  type article_update =
    { title : string option [@jsonschema.option]
    ; description : string option [@jsonschema.option]
    ; body : string option [@jsonschema.option]
    ; tag_list : string list option option [@key "tagList"] [@jsonschema.option]
    }
  [@@deriving jsonschema { strict = true }]

  type article_update_request = { article : article_update }
  [@@deriving jsonschema { strict = true }]

  type comment_create = { body : string } [@@deriving jsonschema { strict = true }]

  type comment_create_request = { comment : comment_create }
  [@@deriving jsonschema { strict = true }]
end

type schema_property = Property : string * 'a Json_schema.t -> schema_property

let property name schema = Property (name, schema)

let object_schema ~required properties =
  Json_schema.Deriver.record
    ~properties:
      (List.map properties ~f:(function Property (name, schema) ->
           name, Json_schema.pack schema))
    ~required
    ~additional_properties:Json_schema.Deriver.Deny
;;

let string_schema = Generated_schema.String_value.t_jsonschema
let bool_schema = Generated_schema.Boolean_value.t_jsonschema
let string_list_schema = Generated_schema.String_list.t_jsonschema
let non_empty_string = Json_schema.Deriver.with_string_lengths ~minimum:1 string_schema

let email_schema =
  Json_schema.Deriver.with_format
    "email"
    (Json_schema.Deriver.with_string_lengths ~minimum:1 string_schema)
;;

let password_schema =
  Json_schema.Deriver.with_format
    "password"
    (Json_schema.Deriver.with_string_lengths ~minimum:1 string_schema)
;;

let nullable_string_schema = Json_schema.nullable string_schema
let timestamp_schema = Json_schema.Deriver.with_format "date-time" string_schema
let positive_int64_schema = Json_schema.int64_exn ~format:`Int64 ~minimum:1L ()
let non_negative_int_schema = Json_schema.integer_exn ~minimum:0 ()

let envelope_schema name schema =
  object_schema ~required:[ name ] [ property name schema ]
;;

let metadata ~schema name description =
  Typed_endpoint.Metadata.v ~schema ~schema_name:name ~description ()
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

let optional_present_nullable_string json name =
  match object_field json name with
  | None -> Ok None
  | Some `Null -> Ok (Some None)
  | Some (`String value) -> Ok (Some (Some value))
  | Some _ -> Error (name ^ " must be a string or null")
;;

let optional_string_list json name =
  match object_field json name with
  | None -> Ok None
  | Some (`List values) ->
    values
    |> List.map ~f:(function
      | `String value -> Ok value
      | _ -> Error (name ^ " must contain strings"))
    |> Result.all
    |> Result.map ~f:Option.some
  | Some _ -> Error (name ^ " must be an array")
;;

let optional_present_string_list json name =
  match object_field json name with
  | None -> Ok None
  | Some `Null -> Ok (Some None)
  | Some (`List values) ->
    values
    |> List.map ~f:(function
      | `String value -> Ok value
      | _ -> Error (name ^ " must contain strings"))
    |> Result.all
    |> Result.map ~f:(fun values -> Some (Some values))
  | Some _ -> Error (name ^ " must be an array")
;;

let nested json name =
  match object_field json name with
  | Some (`Assoc _ as value) -> Ok value
  | Some _ -> Error (name ^ " must be an object")
  | None -> Error (name ^ " is required")
;;

let article_tags values =
  values
  |> List.map ~f:(fun value ->
    Domain.Article.Tag.of_string value
    |> Result.of_option ~error:"tagList must contain non-empty strings")
  |> Result.all
;;

let profile_schema : Wire.profile Json_schema.t =
  object_schema
    ~required:[ "username"; "bio"; "image"; "following" ]
    [ property "username" non_empty_string
    ; property "bio" nullable_string_schema
    ; property "image" nullable_string_schema
    ; property "following" bool_schema
    ]
;;

let user_schema : Wire.user Json_schema.t =
  object_schema
    ~required:[ "email"; "token"; "username"; "bio"; "image" ]
    [ property "email" email_schema
    ; property "token" non_empty_string
    ; property "username" non_empty_string
    ; property "bio" nullable_string_schema
    ; property "image" nullable_string_schema
    ]
;;

let article_schema ~include_body : Wire.article Json_schema.t =
  let required =
    [ "slug"
    ; "title"
    ; "description"
    ; "tagList"
    ; "createdAt"
    ; "updatedAt"
    ; "favorited"
    ; "favoritesCount"
    ; "author"
    ]
  in
  let required, properties =
    if include_body then
      "body" :: required, [ property "body" string_schema ]
    else
      required, []
  in
  object_schema
    ~required
    (properties
     @ [ property "slug" non_empty_string
       ; property "title" string_schema
       ; property "description" string_schema
       ; property "tagList" string_list_schema
       ; property "createdAt" timestamp_schema
       ; property "updatedAt" timestamp_schema
       ; property "favorited" bool_schema
       ; property "favoritesCount" non_negative_int_schema
       ; property "author" profile_schema
       ])
;;

let article_list_item_schema : Wire.article_list_item Json_schema.t =
  object_schema
    ~required:
      [ "slug"
      ; "title"
      ; "description"
      ; "tagList"
      ; "createdAt"
      ; "updatedAt"
      ; "favorited"
      ; "favoritesCount"
      ; "author"
      ]
    [ property "slug" non_empty_string
    ; property "title" string_schema
    ; property "description" string_schema
    ; property "tagList" string_list_schema
    ; property "createdAt" timestamp_schema
    ; property "updatedAt" timestamp_schema
    ; property "favorited" bool_schema
    ; property "favoritesCount" non_negative_int_schema
    ; property "author" profile_schema
    ]
;;

let comment_schema : Wire.comment Json_schema.t =
  object_schema
    ~required:[ "id"; "createdAt"; "updatedAt"; "body"; "author" ]
    [ property "id" positive_int64_schema
    ; property "createdAt" timestamp_schema
    ; property "updatedAt" timestamp_schema
    ; property "body" string_schema
    ; property "author" profile_schema
    ]
;;

let profile_wire (profile : Domain.Profile.t) : Wire.profile =
  { username = Domain.User.Username.to_string profile.username
  ; bio = profile.bio
  ; image = profile.image
  ; following = profile.following
  }
;;

let article_wire (article : Domain.Article.t) : Wire.article =
  { body = article.body
  ; slug = Domain.Article.Slug.to_string article.slug
  ; title = article.title
  ; description = article.description
  ; tag_list = List.map article.tag_list ~f:Domain.Article.Tag.to_string
  ; created_at = Ptime.to_rfc3339 ~frac_s:3 article.created_at
  ; updated_at = Ptime.to_rfc3339 ~frac_s:3 article.updated_at
  ; favorited = article.favorited
  ; favorites_count = article.favorites_count
  ; author = profile_wire article.author
  }
;;

let article_list_item_wire (article : Domain.Article.t) : Wire.article_list_item =
  { slug = Domain.Article.Slug.to_string article.slug
  ; title = article.title
  ; description = article.description
  ; tag_list = List.map article.tag_list ~f:Domain.Article.Tag.to_string
  ; created_at = Ptime.to_rfc3339 ~frac_s:3 article.created_at
  ; updated_at = Ptime.to_rfc3339 ~frac_s:3 article.updated_at
  ; favorited = article.favorited
  ; favorites_count = article.favorites_count
  ; author = profile_wire article.author
  }
;;

let comment_wire (comment : Domain.Comment.t) : Wire.comment =
  { id = Domain.Comment.Id.to_int64 comment.id
  ; created_at = Ptime.to_rfc3339 ~frac_s:3 comment.created_at
  ; updated_at = Ptime.to_rfc3339 ~frac_s:3 comment.updated_at
  ; body = comment.body
  ; author = profile_wire comment.author
  }
;;

module Error_response = struct
  type t = { errors : (string * string list) list }

  let metadata : t Typed_endpoint.Metadata.t =
    let messages = Json_schema.list_exn ~items:string_schema () in
    let fields = Json_schema.dictionary ~values:messages in
    let schema : t Json_schema.t = envelope_schema "errors" fields in
    metadata ~schema "Errors" "Validation or request errors grouped by field"
  ;;

  let make errors = { errors }

  let to_yojson value =
    `Assoc
      [ ( "errors"
        , `Assoc
            (List.map value.errors ~f:(fun (field, messages) ->
               field, `List (List.map messages ~f:(fun message -> `String message)))) )
      ]
  ;;
end

module User_response = struct
  type t = Wire.user_response

  let metadata : t Typed_endpoint.Metadata.t =
    let schema : t Json_schema.t = envelope_schema "user" user_schema in
    metadata ~schema "UserResponse" "Authenticated user"
  ;;

  let make ~token (user : Domain.User.t) : t =
    { Wire.user =
        { email = Domain.User.Email.to_string user.email
        ; token
        ; username = Domain.User.Username.to_string user.username
        ; bio = user.bio
        ; image = user.image
        }
    }
  ;;

  let to_yojson = Wire.user_response_to_yojson
end

module Profile_response = struct
  type t = Wire.profile_response

  let metadata : t Typed_endpoint.Metadata.t =
    let schema : t Json_schema.t = envelope_schema "profile" profile_schema in
    metadata ~schema "ProfileResponse" "User profile"
  ;;

  let make (value : Domain.Profile.t) : t = { Wire.profile = profile_wire value }
  let to_yojson = Wire.profile_response_to_yojson
end

module Article_response = struct
  type t = Wire.article_response

  let metadata : t Typed_endpoint.Metadata.t =
    let schema : t Json_schema.t =
      envelope_schema "article" (article_schema ~include_body:true)
    in
    metadata ~schema "ArticleResponse" "Article"
  ;;

  let make value : t = { Wire.article = article_wire value }
  let to_yojson = Wire.article_response_to_yojson
end

module Articles_response = struct
  type t = Wire.articles_response

  let metadata : t Typed_endpoint.Metadata.t =
    let items = Json_schema.list_exn ~items:article_list_item_schema () in
    let schema : t Json_schema.t =
      object_schema
        ~required:[ "articles"; "articlesCount" ]
        [ property "articles" items; property "articlesCount" non_negative_int_schema ]
    in
    metadata ~schema "ArticlesResponse" "A page of articles"
  ;;

  let make ~articles ~count : t =
    { Wire.articles = List.map articles ~f:article_list_item_wire
    ; articles_count = count
    }
  ;;

  let to_yojson = Wire.articles_response_to_yojson
end

module Comment_response = struct
  type t = Wire.comment_response

  let metadata : t Typed_endpoint.Metadata.t =
    let schema : t Json_schema.t = envelope_schema "comment" comment_schema in
    metadata ~schema "CommentResponse" "Comment"
  ;;

  let make value : t = { Wire.comment = comment_wire value }
  let to_yojson = Wire.comment_response_to_yojson
end

module Comments_response = struct
  type t = Wire.comments_response

  let metadata : t Typed_endpoint.Metadata.t =
    let comments = Json_schema.list_exn ~items:comment_schema () in
    let schema : t Json_schema.t = envelope_schema "comments" comments in
    metadata ~schema "CommentsResponse" "Article comments"
  ;;

  let make values : t = { Wire.comments = List.map values ~f:comment_wire }
  let to_yojson = Wire.comments_response_to_yojson
end

module Tags_response = struct
  type t = Wire.tags_response

  let metadata : t Typed_endpoint.Metadata.t =
    metadata ~schema:Wire.tags_response_jsonschema "TagsResponse" "Known tags"
  ;;

  let make tags : t = { Wire.tags }
  let to_yojson = Wire.tags_response_to_yojson
end

module Registration_request = struct
  type t = Wire.registration_request

  let metadata : t Typed_endpoint.Metadata.t =
    let registration =
      object_schema
        ~required:[ "email"; "username"; "password" ]
        [ property "email" email_schema
        ; property "username" non_empty_string
        ; property "password" password_schema
        ]
    in
    let schema : t Json_schema.t = envelope_schema "user" registration in
    metadata ~schema "RegistrationRequest" "New user registration"
  ;;

  let of_yojson json : (t, string) Result.t =
    let open Result.Let_syntax in
    let%bind user = nested json "user" in
    let%bind email = required_string user "email" in
    let%bind username = required_string user "username" in
    let%map password = required_string user "password" in
    let user : Wire.registration_user = { email; username; password } in
    let request : Wire.registration_request = { user } in
    request
  ;;

  let to_domain (request : t) : Domain.User.registration =
    let user = request.Wire.user in
    Domain.User.{ email = user.email; username = user.username; password = user.password }
  ;;
end

module Login_request = struct
  type t = Wire.login_request

  let metadata : t Typed_endpoint.Metadata.t =
    let credentials =
      object_schema
        ~required:[ "email"; "password" ]
        [ property "email" email_schema; property "password" password_schema ]
    in
    let schema : t Json_schema.t = envelope_schema "user" credentials in
    metadata ~schema "LoginRequest" "User credentials"
  ;;

  let of_yojson json : (t, string) Result.t =
    let open Result.Let_syntax in
    let%bind user = nested json "user" in
    let%bind email = required_string user "email" in
    let%map password = required_string user "password" in
    let user : Wire.login_user = { email; password } in
    let request : Wire.login_request = { user } in
    request
  ;;

  let email (request : t) = request.Wire.user.email
  let password (request : t) = request.Wire.user.password
end

module User_update_request = struct
  type t = Wire.user_update_request

  let metadata : t Typed_endpoint.Metadata.t =
    let update =
      object_schema
        ~required:[]
        [ property "email" email_schema
        ; property "username" non_empty_string
        ; property "password" password_schema
        ; property "bio" nullable_string_schema
        ; property "image" nullable_string_schema
        ]
    in
    let schema : t Json_schema.t = envelope_schema "user" update in
    metadata ~schema "UserUpdateRequest" "Fields to update on the current user"
  ;;

  let of_yojson json : (t, string) Result.t =
    let open Result.Let_syntax in
    let%bind user = nested json "user" in
    let%bind email = optional_present_nullable_string user "email" in
    let%bind username = optional_present_nullable_string user "username" in
    let%bind password = optional_present_nullable_string user "password" in
    let%bind bio = optional_present_nullable_string user "bio" in
    let%map image = optional_present_nullable_string user "image" in
    let user : Wire.user_update = { email; username; password; bio; image } in
    let request : Wire.user_update_request = { user } in
    request
  ;;

  let to_domain (request : t) =
    let user = request.Wire.user in
    let required_string_field name = function
      | None -> Ok None
      | Some (Some value) -> Ok (Some value)
      | Some None -> Error (name, "must be a string")
    in
    let open Result.Let_syntax in
    let%bind email = required_string_field "email" user.email in
    let%bind username = required_string_field "username" user.username in
    let%bind password = required_string_field "password" user.password in
    let patch = function
      | None -> Domain.Patch.Keep
      | Some None -> Domain.Patch.Clear
      | Some (Some value) -> Domain.Patch.Set value
    in
    Ok
      Domain.User.
        { email; username; password; bio = patch user.bio; image = patch user.image }
  ;;
end

module Article_create_request = struct
  type t = Wire.article_create_request

  let metadata : t Typed_endpoint.Metadata.t =
    let create =
      object_schema
        ~required:[ "title"; "description"; "body" ]
        [ property "title" non_empty_string
        ; property "description" non_empty_string
        ; property "body" non_empty_string
        ; property "tagList" string_list_schema
        ]
    in
    let schema : t Json_schema.t = envelope_schema "article" create in
    metadata ~schema "ArticleCreateRequest" "A new article"
  ;;

  let of_yojson json : (t, string) Result.t =
    let open Result.Let_syntax in
    let%bind article = nested json "article" in
    let%bind title = required_string article "title" in
    let%bind description = required_string article "description" in
    let%bind body = required_string article "body" in
    let%bind tag_list = optional_string_list article "tagList" in
    let%map () =
      match tag_list with
      | None -> Ok ()
      | Some values -> article_tags values |> Result.map ~f:(fun _ -> ())
    in
    let article : Wire.article_create = { title; description; body; tag_list } in
    let request : Wire.article_create_request = { article } in
    request
  ;;

  let to_domain (request : t) : Domain.Article.create =
    let article = request.Wire.article in
    let tag_list =
      Option.value article.tag_list ~default:[]
      |> List.map ~f:Domain.Article.Tag.of_string_exn
    in
    Domain.Article.
      { title = article.title
      ; description = article.description
      ; body = article.body
      ; tag_list
      }
  ;;
end

module Article_update_request = struct
  type t = Wire.article_update_request

  let metadata : t Typed_endpoint.Metadata.t =
    let update =
      object_schema
        ~required:[]
        [ property "title" non_empty_string
        ; property "description" non_empty_string
        ; property "body" non_empty_string
        ; property "tagList" string_list_schema
        ]
    in
    let schema : t Json_schema.t = envelope_schema "article" update in
    metadata ~schema "ArticleUpdateRequest" "Fields to update on an article"
  ;;

  let of_yojson json : (t, string) Result.t =
    let open Result.Let_syntax in
    let%bind article = nested json "article" in
    let%bind title = optional_string article "title" in
    let%bind description = optional_string article "description" in
    let%bind body = optional_string article "body" in
    let%bind tag_list = optional_present_string_list article "tagList" in
    let%map () =
      match tag_list with
      | None | Some None -> Ok ()
      | Some (Some values) -> article_tags values |> Result.map ~f:(fun _ -> ())
    in
    let article : Wire.article_update = { title; description; body; tag_list } in
    let request : Wire.article_update_request = { article } in
    request
  ;;

  let to_domain (request : t) =
    let article = request.Wire.article in
    match article.tag_list with
    | Some None -> Error ()
    | None ->
      Ok
        Domain.Article.
          { title = article.title
          ; description = article.description
          ; body = article.body
          ; tag_list = None
          }
    | Some (Some tags) ->
      let tag_list = Some (List.map tags ~f:Domain.Article.Tag.of_string_exn) in
      Ok
        Domain.Article.
          { title = article.title
          ; description = article.description
          ; body = article.body
          ; tag_list
          }
  ;;
end

module Comment_create_request = struct
  type t = Wire.comment_create_request

  let metadata : t Typed_endpoint.Metadata.t =
    let create =
      object_schema ~required:[ "body" ] [ property "body" non_empty_string ]
    in
    let schema : t Json_schema.t = envelope_schema "comment" create in
    metadata ~schema "CommentCreateRequest" "A new article comment"
  ;;

  let of_yojson json : (t, string) Result.t =
    let open Result.Let_syntax in
    let%bind comment = nested json "comment" in
    let%map body = required_string comment "body" in
    let comment : Wire.comment_create = { body } in
    let request : Wire.comment_create_request = { comment } in
    request
  ;;

  let body (request : t) = request.Wire.comment.body
end
