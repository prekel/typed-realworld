open! Base
open Typed_sql
open Infix
open Lwt.Let_syntax
module Schema = Realworld_sqlite.Schema
module Users = Schema.Users
module Articles = Schema.Articles
module Tags = Schema.Tags
module Article_tags = Schema.Article_tags
module Favorites = Schema.Favorites
module Follows = Schema.Follows
module Comments = Schema.Comments
module Adapter = Typed_sql_caqti_lwt
module Domain = Realworld_domain.Domain

module Insert_user = struct
  type t =
    { id : int64
    ; email : string
    ; username : string
    }
end

let insert_user =
  Statement.Portable.command_exn (fun params ->
    let id = params.column Users.id_column ~get:(fun input -> input.Insert_user.id) in
    let email =
      params.column Users.email_column ~get:(fun input -> input.Insert_user.email)
    in
    let username =
      params.column Users.username_column ~get:(fun input -> input.Insert_user.username)
    in
    Insert.(
      into Users.table
      |> set_expr Users.id_column id
      |> set_expr Users.email_column email
      |> set_expr Users.username_column username
      |> set Users.password_hash_column "test-hash"
      |> set Users.bio_column None
      |> set Users.image_column None
      |> command))
;;

module Insert_article = struct
  type t =
    { id : int64
    ; slug : string
    ; author_id : int64
    ; now : Ptime.t
    }
end

let insert_article =
  Statement.Portable.command_exn (fun params ->
    let id =
      params.column Articles.id_column ~get:(fun input -> input.Insert_article.id)
    in
    let slug =
      params.column Articles.slug_column ~get:(fun input -> input.Insert_article.slug)
    in
    let author_id =
      params.column Articles.author_id_column ~get:(fun input ->
        input.Insert_article.author_id)
    in
    let now =
      params.column Articles.created_at_column ~get:(fun input ->
        input.Insert_article.now)
    in
    Insert.(
      into Articles.table
      |> set_expr Articles.id_column id
      |> set_expr Articles.author_id_column author_id
      |> set_expr Articles.slug_column slug
      |> set Articles.title_column "Generated schema"
      |> set Articles.description_column "A typed SQL integration test"
      |> set Articles.body_column "Content survives schema upgrades."
      |> set_expr Articles.created_at_column now
      |> set_expr Articles.updated_at_column now
      |> command))
;;

let article_by_id =
  Statement.Portable.expect_one_exn (fun params ->
    let id = params.column Articles.id_column ~get:Fn.id in
    Query.(
      from Articles.table
      |> where (fun row -> Articles.id row =. id)
      |> limit_one
      |> select Articles.projection))
;;

module Add_favorite = struct
  type t =
    { user_id : int64
    ; article_id : int64
    }
end

let add_favorite =
  Statement.Portable.command_exn (fun params ->
    let user_id =
      params.column Favorites.user_id_column ~get:(fun input ->
        input.Add_favorite.user_id)
    in
    let article_id =
      params.column Favorites.article_id_column ~get:(fun input ->
        input.Add_favorite.article_id)
    in
    Insert.(
      into Favorites.table
      |> set_expr Favorites.user_id_column user_id
      |> set_expr Favorites.article_id_column article_id
      |> on_conflict_do_nothing
      |> command))
;;

module Follow = struct
  type t =
    { follower_id : int64
    ; followed_id : int64
    }
end

let follow =
  Statement.Portable.command_exn (fun params ->
    let follower_id =
      params.column Follows.follower_id_column ~get:(fun input ->
        input.Follow.follower_id)
    in
    let followed_id =
      params.column Follows.followed_id_column ~get:(fun input ->
        input.Follow.followed_id)
    in
    Insert.(
      into Follows.table
      |> set_expr Follows.follower_id_column follower_id
      |> set_expr Follows.followed_id_column followed_id
      |> command))
;;

module Insert_article_tag = struct
  type t =
    { article_id : int64
    ; tag_id : int64
    }
end

let insert_article_tag =
  Statement.Portable.command_exn (fun params ->
    let article_id =
      params.column Article_tags.article_id_column ~get:(fun input ->
        input.Insert_article_tag.article_id)
    in
    let tag_id =
      params.column Article_tags.tag_id_column ~get:(fun input ->
        input.Insert_article_tag.tag_id)
    in
    Insert.(
      into Article_tags.table
      |> set_expr Article_tags.article_id_column article_id
      |> set_expr Article_tags.tag_id_column tag_id
      |> set Article_tags.position_column 0L
      |> command))
;;

module Insert_comment = struct
  type t =
    { article_id : int64
    ; body : string
    ; now : Ptime.t
    }
end

let insert_comment =
  Statement.Portable.command_exn (fun params ->
    let article_id =
      params.column Comments.article_id_column ~get:(fun input ->
        input.Insert_comment.article_id)
    in
    let body =
      params.column Comments.body_column ~get:(fun input -> input.Insert_comment.body)
    in
    let now =
      params.column Comments.created_at_column ~get:(fun input ->
        input.Insert_comment.now)
    in
    Insert.(
      into Comments.table
      |> set_expr Comments.article_id_column article_id
      |> set Comments.author_id_column 2L
      |> set_expr Comments.body_column body
      |> set_expr Comments.created_at_column now
      |> set_expr Comments.updated_at_column now
      |> command))
;;

let joined_article_author =
  Statement.Portable.expect_one_exn (fun params ->
    let id = params.column Articles.id_column ~get:Fn.id in
    Query.(
      from Articles.table
      |> inner_join Users.table ~on:(fun article user ->
        Articles.author_id article =. Users.id user)
      |> where (fun (article, _) -> Articles.id article =. id)
      |> limit_one
      |> select (fun (article, user) ->
        Projection.pair (Articles.title article) (Users.username user))))
;;

let delete_article =
  Statement.Portable.command_exn (fun params ->
    let id = params.column Articles.id_column ~get:Fn.id in
    Delete.(from Articles.table |> where (fun row -> Articles.id row =. id) |> command))
;;

let all_favorites : (unit, Favorites.t list, Dialect.portable) Statement.t =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(from Favorites.table |> select Favorites.projection))
;;

let all_comments : (unit, Comments.t list, Dialect.portable) Statement.t =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(from Comments.table |> select Comments.projection))
;;

let all_article_tags : (unit, Article_tags.t list, Dialect.portable) Statement.t =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(from Article_tags.table |> select Article_tags.projection))
;;

let all_tags : (unit, Tags.t list, Dialect.portable) Statement.t =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(from Tags.table |> select Tags.projection))
;;

let or_fail result =
  result |> Result.map_error ~f:Adapter.error_to_string |> Result.ok_or_failwith
;;

let execute ~conn statement input =
  let%map result = Adapter.run ~conn statement input in
  ignore (or_fail result : Affected_rows.t)
;;

let email = "before'upgrade@example.test"
let seed conn = execute ~conn insert_user { id = 1L; email; username = "before-upgrade" }

let check_user conn =
  let%bind result = Adapter.run ~conn Realworld_sqlite.User_queries.by_email email in
  let user = or_fail result |> Option.value_exn in
  assert (Domain.User.Id.equal user.id (Domain.User.Id.of_int64_exn 1L));
  assert (String.equal (Domain.User.Username.to_string user.username) "before-upgrade");
  assert (String.equal user.password_hash "test-hash");
  assert (Option.is_none user.bio);
  assert (Option.is_none user.image);
  let missing_id = Domain.User.Id.of_int64_exn 999L in
  let%map missing = Adapter.run ~conn Realworld_sqlite.User_queries.by_id missing_id in
  assert (Option.is_none (or_fail missing))
;;

let expect_constraint kind = function
  | Error (Adapter.Constraint_violation { kind = actual; _ }) ->
    (match kind, actual with
     | `Unique, Adapter.Unique | `Foreign_key, Foreign_key | `Check, Check -> ()
     | _ -> Stdlib.failwith "unexpected integrity constraint classification")
  | Error error -> Stdlib.failwith (Adapter.error_to_string error)
  | Ok _ -> Stdlib.failwith "invalid row was accepted"
;;

let verify conn =
  let%bind () = check_user conn in
  let%bind duplicate =
    Adapter.run ~conn insert_user { id = 10L; email; username = "another-name" }
  in
  expect_constraint `Unique duplicate;
  let%bind case_duplicate =
    Adapter.run
      ~conn
      insert_user
      { id = 11L; email = "BEFORE'UPGRADE@EXAMPLE.TEST"; username = "case-duplicate" }
  in
  expect_constraint `Unique case_duplicate;
  let%bind () =
    execute
      ~conn
      insert_user
      { id = 2L; email = "reader@example.test"; username = "reader" }
  in
  let now =
    Ptime.of_rfc3339 "2026-09-13T12:34:56Z" |> Result.ok |> Option.value_exn
    |> fun (t, _, _) -> t
  in
  let%bind invalid_author =
    Adapter.run
      ~conn
      insert_article
      { id = 1L; slug = "generated-schema"; author_id = 999L; now }
  in
  expect_constraint `Foreign_key invalid_author;
  let%bind () =
    execute
      ~conn
      insert_article
      { id = 1L; slug = "generated-schema"; author_id = 1L; now }
  in
  let%bind () =
    execute ~conn insert_article { id = 2L; slug = "other-article"; author_id = 2L; now }
  in
  let%bind selected = Adapter.run ~conn article_by_id 1L in
  let stored = or_fail selected in
  assert (Ptime.equal stored.created_at now);
  assert (String.equal stored.body "Content survives schema upgrades.");
  let favorite : Add_favorite.t = { user_id = 2L; article_id = 1L } in
  let%bind () = execute ~conn add_favorite favorite in
  let%bind () = execute ~conn add_favorite favorite in
  let%bind favorites = Adapter.run ~conn all_favorites () in
  assert (Int.equal (List.length (or_fail favorites)) 1);
  let%bind self_follow =
    Adapter.run ~conn follow { follower_id = 2L; followed_id = 2L }
  in
  expect_constraint `Check self_follow;
  let%bind () = execute ~conn follow { follower_id = 2L; followed_id = 1L } in
  let tag = Domain.Article.Tag.of_string_exn "ocaml" in
  let%bind inserted_tag =
    Adapter.run ~conn Realworld_sqlite.Article_queries.upsert_tag tag
  in
  let inserted_tag = or_fail inserted_tag in
  let%bind existing_tag =
    Adapter.run ~conn Realworld_sqlite.Article_queries.upsert_tag tag
  in
  let existing_tag = or_fail existing_tag in
  assert (Int64.equal inserted_tag.id existing_tag.id);
  let%bind stored_tags = Adapter.run ~conn all_tags () in
  assert (Int.equal (List.length (or_fail stored_tags)) 1);
  let%bind () =
    execute ~conn insert_article_tag { article_id = 1L; tag_id = inserted_tag.id }
  in
  let%bind () =
    execute ~conn insert_comment { article_id = 1L; body = "A comment"; now }
  in
  let%bind () =
    execute
      ~conn
      insert_comment
      { article_id = 2L; body = "A comment on another article"; now }
  in
  let%bind article_comments =
    Adapter.run ~conn Realworld_sqlite.Comment_queries.by_article 1L
  in
  let article_comments = or_fail article_comments in
  assert (Int.equal (List.length article_comments) 1);
  assert (String.equal (List.hd_exn article_comments).body "A comment");
  (* Check dialect-neutral query construction now; PostgreSQL execution is a later step. *)
  List.iter [ Dialect.Sqlite; Dialect.Postgresql ] ~f:(fun dialect ->
    Statement.sql_exn ~dialect ~input:1L joined_article_author |> ignore);
  let%bind joined_result = Adapter.run ~conn joined_article_author 1L in
  let title, username = or_fail joined_result in
  assert (String.equal title "Generated schema");
  assert (String.equal username "before-upgrade");
  let filters : Domain.Article.filters =
    { tag = Some (Domain.Article.Tag.of_string_exn "ocaml")
    ; author = Some (Domain.User.Username.of_string_exn "before-upgrade")
    ; favorited_by = Some (Domain.User.Username.of_string_exn "reader")
    }
  in
  let page =
    Domain.Page.create
      ~limit:(Domain.Page.Limit.of_int 1 |> Option.value_exn)
      ~offset:(Domain.Page.Offset.of_int 0 |> Option.value_exn)
      ()
  in
  let%bind filtered =
    Adapter.run
      ~conn
      Realworld_sqlite.Article_queries.page
      { filters; followed_by = None; page }
  in
  assert (Int.equal (List.length (or_fail filtered)) 1);
  let%bind filtered_count =
    Adapter.run
      ~conn
      Realworld_sqlite.Article_queries.count
      { filters; followed_by = None }
  in
  assert (Int64.equal (or_fail filtered_count) 1L);
  let%bind feed =
    Adapter.run
      ~conn
      Realworld_sqlite.Article_queries.page
      { filters = Domain.Article.no_filters
      ; followed_by = Some (Domain.User.Id.of_int64_exn 2L)
      ; page
      }
  in
  assert (Int.equal (List.length (or_fail feed)) 1);
  let%bind () = execute ~conn delete_article 1L in
  let%bind () = execute ~conn delete_article 2L in
  let%bind comments = Adapter.run ~conn all_comments () in
  let%bind favorites = Adapter.run ~conn all_favorites () in
  let%bind article_tags = Adapter.run ~conn all_article_tags () in
  assert (List.is_empty (or_fail comments));
  assert (List.is_empty (or_fail favorites));
  assert (List.is_empty (or_fail article_tags));
  let%map tags = Adapter.run ~conn all_tags () in
  assert (Int.equal (List.length (or_fail tags)) 1)
;;

let run operation url =
  let%bind connected = Caqti_lwt_unix.connect (Uri.of_string url) in
  let conn = connected |> Result.map_error ~f:Caqti.Error.show |> Result.ok_or_failwith in
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Lwt.finalize
    (fun () ->
       let request =
         Caqti.Template.Request.create
           Caqti.Template.Request.Direct
           Caqti.Template.Request_type.Infix.(
             Caqti.Template.Row_type.unit -->. Caqti.Template.Row_type.unit)
           (fun _ -> Caqti.Template.Query.parse "PRAGMA foreign_keys = ON")
       in
       let%bind configured = Connection.exec request () in
       configured |> Result.map_error ~f:Caqti.Error.show |> Result.ok_or_failwith;
       match operation with
       | "seed" -> seed conn
       | "check-user" -> check_user conn
       | "verify" -> verify conn
       | _ -> Stdlib.failwith "unknown test operation")
    (fun () -> Connection.disconnect ())
;;

let () =
  match Stdlib.Sys.argv with
  | [| _; operation; url |] -> Lwt_main.run (run operation url)
  | _ ->
    Stdlib.failwith "Usage: schema_integration_test seed|check-user|verify SQLITE_URL"
;;
