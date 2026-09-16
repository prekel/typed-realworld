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

let or_fail result =
  result |> Result.map_error ~f:Adapter.error_to_string |> Result.ok_or_failwith
;;

let execute ~conn command =
  let%map result = Adapter.execute ~conn command in
  ignore (or_fail result : Affected_rows.t)
;;

let email = "before'upgrade@example.test"

let seed conn =
  execute
    ~conn
    Insert.(
      into Users.table
      |> set Users.id_column 1L
      |> set Users.email_column email
      |> set Users.username_column "before-upgrade"
      |> set Users.password_hash_column "test-hash"
      |> set Users.bio_column None
      |> set Users.image_column None
      |> command)
;;

let check_user conn =
  let%bind result =
    Adapter.fetch_opt ~conn (Realworld_sqlite.User_queries.by_email email)
  in
  let user = or_fail result |> Option.value_exn in
  assert (Domain.User.Id.equal user.id (Domain.User.Id.of_int64_exn 1L));
  assert (String.equal (Domain.User.Username.to_string user.username) "before-upgrade");
  assert (String.equal user.password_hash "test-hash");
  assert (Option.is_none user.bio);
  assert (Option.is_none user.image);
  let missing_id = Domain.User.Id.of_int64_exn 999L in
  let%map missing =
    Adapter.fetch_opt ~conn (Realworld_sqlite.User_queries.by_id missing_id)
  in
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
    Adapter.execute
      ~conn
      Insert.(
        into Users.table
        |> set Users.email_column email
        |> set Users.username_column "another-name"
        |> set Users.password_hash_column "test-hash"
        |> command)
  in
  expect_constraint `Unique duplicate;
  let%bind case_duplicate =
    Adapter.execute
      ~conn
      Insert.(
        into Users.table
        |> set Users.email_column "BEFORE'UPGRADE@EXAMPLE.TEST"
        |> set Users.username_column "case-duplicate"
        |> set Users.password_hash_column "test-hash"
        |> command)
  in
  expect_constraint `Unique case_duplicate;
  let%bind () =
    execute
      ~conn
      Insert.(
        into Users.table
        |> set Users.id_column 2L
        |> set Users.email_column "reader@example.test"
        |> set Users.username_column "reader"
        |> set Users.password_hash_column "test-hash"
        |> command)
  in
  let now =
    Ptime.of_rfc3339 "2026-09-13T12:34:56Z" |> Result.ok |> Option.value_exn
    |> fun (t, _, _) -> t
  in
  let article ~id ~slug author_id =
    Insert.(
      into Articles.table
      |> set Articles.id_column id
      |> set Articles.author_id_column author_id
      |> set Articles.slug_column slug
      |> set Articles.title_column "Generated schema"
      |> set Articles.description_column "A typed SQL integration test"
      |> set Articles.body_column "Content survives schema upgrades."
      |> set Articles.created_at_column now
      |> set Articles.updated_at_column now
      |> command)
  in
  let%bind invalid_author =
    Adapter.execute ~conn (article ~id:1L ~slug:"generated-schema" 999L)
  in
  expect_constraint `Foreign_key invalid_author;
  let%bind () = execute ~conn (article ~id:1L ~slug:"generated-schema" 1L) in
  let%bind () = execute ~conn (article ~id:2L ~slug:"other-article" 2L) in
  let%bind selected =
    Adapter.fetch_one
      ~conn
      Query.(
        from Articles.table
        |> where (fun row -> Articles.id row =$ 1L)
        |> select Articles.projection)
  in
  let stored = or_fail selected in
  assert (Ptime.equal stored.created_at now);
  assert (String.equal stored.body "Content survives schema upgrades.");
  let favorite =
    Insert.(
      into Favorites.table
      |> set Favorites.user_id_column 2L
      |> set Favorites.article_id_column 1L
      |> on_conflict_do_nothing
      |> command)
  in
  let%bind () = execute ~conn favorite in
  let%bind () = execute ~conn favorite in
  let%bind favorites =
    Adapter.fetch ~conn Query.(from Favorites.table |> select Favorites.projection)
  in
  assert (Int.equal (List.length (or_fail favorites)) 1);
  let follow followed_id =
    Insert.(
      into Follows.table
      |> set Follows.follower_id_column 2L
      |> set Follows.followed_id_column followed_id
      |> command)
  in
  let%bind self_follow = Adapter.execute ~conn (follow 2L) in
  expect_constraint `Check self_follow;
  let%bind () = execute ~conn (follow 1L) in
  let tag = Domain.Article.Tag.of_string_exn "ocaml" in
  let%bind inserted_tag =
    Adapter.fetch_one ~conn (Realworld_sqlite.Article_queries.upsert_tag tag)
  in
  let inserted_tag = or_fail inserted_tag in
  let%bind existing_tag =
    Adapter.fetch_one ~conn (Realworld_sqlite.Article_queries.upsert_tag tag)
  in
  let existing_tag = or_fail existing_tag in
  assert (Int64.equal inserted_tag.id existing_tag.id);
  let%bind stored_tags =
    Adapter.fetch ~conn Query.(from Tags.table |> select Tags.projection)
  in
  assert (Int.equal (List.length (or_fail stored_tags)) 1);
  let%bind () =
    execute
      ~conn
      Insert.(
        into Article_tags.table
        |> set Article_tags.article_id_column 1L
        |> set Article_tags.tag_id_column inserted_tag.id
        |> set Article_tags.position_column 0L
        |> command)
  in
  let%bind () =
    execute
      ~conn
      Insert.(
        into Comments.table
        |> set Comments.article_id_column 1L
        |> set Comments.author_id_column 2L
        |> set Comments.body_column "A comment"
        |> set Comments.created_at_column now
        |> set Comments.updated_at_column now
        |> command)
  in
  let%bind () =
    execute
      ~conn
      Insert.(
        into Comments.table
        |> set Comments.article_id_column 2L
        |> set Comments.author_id_column 2L
        |> set Comments.body_column "A comment on another article"
        |> set Comments.created_at_column now
        |> set Comments.updated_at_column now
        |> command)
  in
  let%bind article_comments =
    Adapter.fetch ~conn (Realworld_sqlite.Comment_queries.by_article 1L)
  in
  let article_comments = or_fail article_comments in
  assert (Int.equal (List.length article_comments) 1);
  assert (String.equal (List.hd_exn article_comments).body "A comment");
  let joined =
    Query.(
      from Articles.table
      |> inner_join Users.table ~on:(fun article user ->
        Articles.author_id article =. Users.id user)
      |> where (fun (article, _) -> Articles.id article =$ 1L)
      |> select (fun (article, user) ->
        Projection.pair (Articles.title article) (Users.username user)))
  in
  (* Check dialect-neutral query construction now; PostgreSQL execution is a later step. *)
  List.iter [ Dialect.Sqlite; Dialect.Postgresql ] ~f:(fun dialect ->
    Compiler.compile ~dialect joined
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
    |> ignore);
  let%bind joined_result = Adapter.fetch_one ~conn joined in
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
    Adapter.fetch
      ~conn
      (Realworld_sqlite.Article_queries.page ~filters ~followed_by:None ~page)
  in
  assert (Int.equal (List.length (or_fail filtered)) 1);
  let%bind filtered_count =
    Adapter.fetch_one
      ~conn
      (Realworld_sqlite.Article_queries.count ~filters ~followed_by:None)
  in
  assert (Int64.equal (or_fail filtered_count) 1L);
  let%bind feed =
    Adapter.fetch
      ~conn
      (Realworld_sqlite.Article_queries.page
         ~filters:Domain.Article.no_filters
         ~followed_by:(Some (Domain.User.Id.of_int64_exn 2L))
         ~page)
  in
  assert (Int.equal (List.length (or_fail feed)) 1);
  let%bind () =
    execute
      ~conn
      Delete.(from Articles.table |> where (fun row -> Articles.id row =$ 1L) |> command)
  in
  let%bind () =
    execute
      ~conn
      Delete.(from Articles.table |> where (fun row -> Articles.id row =$ 2L) |> command)
  in
  let%bind comments =
    Adapter.fetch ~conn Query.(from Comments.table |> select Comments.projection)
  in
  let%bind favorites =
    Adapter.fetch ~conn Query.(from Favorites.table |> select Favorites.projection)
  in
  let%bind article_tags =
    Adapter.fetch ~conn Query.(from Article_tags.table |> select Article_tags.projection)
  in
  assert (List.is_empty (or_fail comments));
  assert (List.is_empty (or_fail favorites));
  assert (List.is_empty (or_fail article_tags));
  let%map tags = Adapter.fetch ~conn Query.(from Tags.table |> select Tags.projection) in
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
