open! Base
module Domain = Realworld_domain.Domain

let unused () = Stdlib.failwith "service handler was called while generating OpenAPI"

module Users : Realworld_application.User_service.S with type database = unit = struct
  type database = unit

  let register ~database:_ _ = unused ()
  let login ~database:_ ~email:_ ~password:_ = unused ()
  let current ~database:_ _ = unused ()
  let update ~database:_ ~user_id:_ _ = unused ()
  let profile ~database:_ ~viewer_id:_ ~username:_ = unused ()
  let follow ~database:_ ~follower_id:_ ~username:_ = unused ()
  let unfollow ~database:_ ~follower_id:_ ~username:_ = unused ()
end

module Articles : Realworld_application.Article_service.S with type database = unit =
struct
  type database = unit

  let list ~database:_ ~viewer_id:_ ~filters:_ ~page:_ = unused ()
  let feed ~database:_ ~viewer_id:_ ~page:_ = unused ()
  let find ~database:_ ~viewer_id:_ ~slug:_ = unused ()
  let create ~database:_ ~author_id:_ _ = unused ()
  let update ~database:_ ~author_id:_ ~slug:_ _ = unused ()
  let delete ~database:_ ~author_id:_ ~slug:_ = unused ()
  let favorite ~database:_ ~user_id:_ ~slug:_ = unused ()
  let unfavorite ~database:_ ~user_id:_ ~slug:_ = unused ()
  let tags ~database:_ = unused ()
end

module Comments : Realworld_application.Comment_service.S with type database = unit =
struct
  type database = unit

  let list ~database:_ ~viewer_id:_ ~slug:_ = unused ()
  let create ~database:_ ~author_id:_ ~slug:_ ~body:_ = unused ()
  let delete ~database:_ ~author_id:_ ~slug:_ ~comment_id:_ = unused ()
end

module Http = Realworld_http.App.Make (Typed_endpoint_opium) (Users) (Articles) (Comments)

let document =
  Http.compile ~database:() ~issue:(fun ~user_id:_ -> "token") ~verify:(fun _ -> None)
  |> Http.Endpoint.Compiled.openapi ~config:Realworld_http.App.openapi_config
;;

let validate_schema_fragment ~location schema =
  match
    Jsonschema.validate Jsonschema.draft2020_12_validator (Yojson.Safe.to_basic schema)
  with
  | Ok () -> ()
  | Error error ->
    Stdlib.failwith (location ^ ": " ^ Jsonschema.Validation_error.to_string_verbose error)
;;

let validate_openapi_schemas document =
  let open Yojson.Safe.Util in
  document
  |> member "components"
  |> member "schemas"
  |> to_assoc
  |> List.iter ~f:(fun (name, schema) ->
    validate_schema_fragment ~location:("#/components/schemas/" ^ name) schema);
  let rec visit path = function
    | `Assoc fields ->
      List.iter fields ~f:(fun (name, value) ->
        let path = path ^ "/" ^ name in
        if String.equal name "schema" then
          validate_schema_fragment ~location:path value;
        visit path value)
    | `List values ->
      List.iteri values ~f:(fun index value ->
        visit (path ^ "/" ^ Int.to_string index) value)
    | `Null | `Bool _ | `Int _ | `Intlit _ | `Float _ | `String _ -> ()
  in
  visit "#" document
;;

let assert_operation paths (path_name, meth, operation_id) =
  let open Yojson.Safe.Util in
  let actual =
    paths |> member path_name |> member meth |> member "operationId" |> to_string
  in
  assert (String.equal actual operation_id)
;;

let assert_property schemas component property =
  let open Yojson.Safe.Util in
  let value = schemas |> member component |> member "properties" |> member property in
  assert (not (Yojson.Safe.equal value `Null))
;;

let assert_response paths path_name meth status =
  let open Yojson.Safe.Util in
  let response =
    paths
    |> member path_name
    |> member meth
    |> member "responses"
    |> member (Int.to_string status)
  in
  assert (not (Yojson.Safe.equal response `Null))
;;

let () =
  validate_openapi_schemas document;
  let open Yojson.Safe.Util in
  assert (String.equal (document |> member "openapi" |> to_string) "3.1.0");
  assert (
    String.equal (document |> member "info" |> member "version" |> to_string) "1.0.0");
  let paths = document |> member "paths" in
  List.iter
    [ "/api/users", "post", "registerUser"
    ; "/api/users/login", "post", "loginUser"
    ; "/api/user", "get", "getCurrentUser"
    ; "/api/user", "put", "updateCurrentUser"
    ; "/api/profiles/{username}", "get", "getProfile"
    ; "/api/profiles/{username}/follow", "post", "followUser"
    ; "/api/profiles/{username}/follow", "delete", "unfollowUser"
    ; "/api/articles", "get", "listArticles"
    ; "/api/articles", "post", "createArticle"
    ; "/api/articles/feed", "get", "feedArticles"
    ; "/api/articles/{slug}", "get", "getArticle"
    ; "/api/articles/{slug}", "put", "updateArticle"
    ; "/api/articles/{slug}", "delete", "deleteArticle"
    ; "/api/articles/{slug}/favorite", "post", "favoriteArticle"
    ; "/api/articles/{slug}/favorite", "delete", "unfavoriteArticle"
    ; "/api/articles/{slug}/comments", "get", "getComments"
    ; "/api/articles/{slug}/comments", "post", "createComment"
    ; "/api/articles/{slug}/comments/{id}", "delete", "deleteComment"
    ; "/api/tags", "get", "getTags"
    ]
    ~f:(assert_operation paths);
  let schemas = document |> member "components" |> member "schemas" in
  List.iter
    [ "Errors"
    ; "UserResponse"
    ; "ProfileResponse"
    ; "ArticleResponse"
    ; "ArticlesResponse"
    ; "CommentResponse"
    ; "CommentsResponse"
    ; "TagsResponse"
    ; "RegistrationRequest"
    ; "LoginRequest"
    ; "UserUpdateRequest"
    ; "ArticleCreateRequest"
    ; "ArticleUpdateRequest"
    ; "CommentCreateRequest"
    ]
    ~f:(fun name -> assert (not (Yojson.Safe.equal (schemas |> member name) `Null)));
  assert_property schemas "UserResponse" "user";
  assert_property schemas "ArticlesResponse" "articlesCount";
  assert (
    String.equal (schemas |> member "CommentId" |> member "format" |> to_string) "int64");
  assert (Int.equal (schemas |> member "CommentId" |> member "minimum" |> to_int) 1);
  assert (Int.equal (schemas |> member "ArticleSlug" |> member "minLength" |> to_int) 1);
  assert (Int.equal (schemas |> member "PageLimit" |> member "minimum" |> to_int) 0);
  let list_parameters =
    paths |> member "/api/articles" |> member "get" |> member "parameters" |> to_list
  in
  let parameter_names =
    List.map list_parameters ~f:(fun parameter -> parameter |> member "name" |> to_string)
  in
  assert (
    List.equal
      String.equal
      parameter_names
      [ "tag"; "author"; "favorited"; "limit"; "offset" ]);
  List.iter
    [ "/api/users", "post", 201
    ; "/api/users", "post", 409
    ; "/api/articles", "post", 201
    ; "/api/articles/{slug}", "get", 404
    ; "/api/articles/{slug}", "put", 403
    ; "/api/articles/{slug}", "delete", 204
    ; "/api/articles/{slug}/comments", "post", 201
    ; "/api/articles/{slug}/comments/{id}", "delete", 403
    ]
    ~f:(fun (path_name, meth, status) -> assert_response paths path_name meth status);
  let list_item =
    schemas
    |> member "ArticlesResponse"
    |> member "properties"
    |> member "articles"
    |> member "items"
    |> member "properties"
  in
  assert (Yojson.Safe.equal (list_item |> member "body") `Null);
  let article_body =
    schemas
    |> member "ArticleResponse"
    |> member "properties"
    |> member "article"
    |> member "properties"
    |> member "body"
  in
  assert (String.equal (article_body |> member "type" |> to_string) "string");
  let security path meth =
    paths |> member path |> member meth |> member "security" |> to_list
  in
  assert (Int.equal (List.length (security "/api/articles" "get")) 2);
  assert (Int.equal (List.length (security "/api/profiles/{username}" "get")) 2);
  assert (Int.equal (List.length (security "/api/articles" "post")) 1);
  assert (
    Yojson.Safe.equal
      (paths |> member "/api/users" |> member "post" |> member "security")
      `Null);
  let rendered = Yojson.Safe.to_string document in
  assert (not (String.is_substring rendered ~substring:"password_hash"));
  assert (Yojson.Safe.equal (paths |> member "/openapi.json") `Null);
  assert (Yojson.Safe.equal (paths |> member "/docs") `Null)
;;
