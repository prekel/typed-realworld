open! Base
open Lwt.Let_syntax
module Application = Realworld_application
module Domain = Realworld_domain.Domain

module type Database_runtime = sig
  type t
  type connection = Caqti_lwt.connection
  type 'a io = 'a Lwt.t

  val create : Uri.t -> (t, Application.Persistence_error.t) Result.t Lwt.t
  val disconnect : t -> unit Lwt.t

  include
    Application.Database.S
    with type t := t
     and type connection := connection
     and type 'a io := 'a io
end

module Make (Database : Database_runtime) = struct
  module Hasher = struct
    let hash password = Ok ("test:" ^ password)
    let verify ~encoded password = String.equal encoded ("test:" ^ password)
  end

  module Clock = struct
    let now () =
      Ptime.of_rfc3339 "2026-09-23T12:34:56Z" |> Result.ok |> Option.value_exn
      |> fun (value, _, _) -> value
    ;;
  end

  module Users =
    Application.User_service.Make (Database) (Realworld_sql.User_repository_sql) (Hasher)

  module Articles =
    Application.Article_service.Make (Database) (Realworld_sql.Article_repository_sql)
      (Clock)

  module Comments =
    Application.Comment_service.Make (Database) (Realworld_sql.Comment_repository_sql)
      (Clock)

  let fail_persistence error =
    Stdlib.failwith (Application.Persistence_error.to_string error)
  ;;

  let registered = function
    | Ok user -> user
    | Error (`Persistence error) -> fail_persistence error
    | Error _ -> Stdlib.failwith "expected registration to succeed"
  ;;

  let created_article = function
    | Ok article -> article
    | Error (`Persistence error) -> fail_persistence error
    | Error _ -> Stdlib.failwith "expected article creation to succeed"
  ;;

  let created_comment = function
    | Ok comment -> comment
    | Error (`Persistence error) -> fail_persistence error
    | Error _ -> Stdlib.failwith "expected comment creation to succeed"
  ;;

  let registration email username : Domain.User.registration =
    { email; username; password = "password123" }
  ;;

  let article_input title : Domain.Article.create =
    { title
    ; description = "Repository integration"
    ; body = "This article exercises the complete persistence boundary."
    ; tag_list =
        [ Domain.Article.Tag.of_string_exn "ocaml"
        ; Domain.Article.Tag.of_string_exn "typed-sql"
        ]
    }
  ;;

  let assert_profile_following expected = function
    | Ok (Some (profile : Domain.Profile.t)) ->
      assert (Bool.equal profile.following expected)
    | Ok None -> Stdlib.failwith "profile is missing"
    | Error error -> fail_persistence error
  ;;

  let run url =
    let%bind connected = Database.create (Uri.of_string url) in
    let database =
      match connected with
      | Ok database -> database
      | Error error -> fail_persistence error
    in
    Lwt.finalize
      (fun () ->
         let%bind alice =
           Users.register ~database (registration "Alice@Example.Test" "Alice")
         in
         let alice = registered alice in
         let%bind bob =
           Users.register ~database (registration "bob@example.test" "Bob")
         in
         let bob = registered bob in
         assert (
           String.equal (Domain.User.Email.to_string alice.email) "alice@example.test");
         let%bind duplicate_email =
           Users.register ~database (registration "ALICE@EXAMPLE.TEST" "other")
         in
         assert (Poly.equal duplicate_email (Error `Email_taken));
         let%bind duplicate_username =
           Users.register ~database (registration "other@example.test" "BOB")
         in
         assert (Poly.equal duplicate_username (Error `Username_taken));
         let update_email =
           { Domain.User.empty_update with email = Some "ALICE@EXAMPLE.TEST" }
         in
         let%bind update_conflict = Users.update ~database ~user_id:bob.id update_email in
         assert (Poly.equal update_conflict (Error `Email_taken));
         let%bind before_follow =
           Users.profile ~database ~viewer_id:(Some bob.id) ~username:alice.username
         in
         assert_profile_following false before_follow;
         let%bind followed =
           Users.follow ~database ~follower_id:bob.id ~username:alice.username
         in
         (match followed with
          | Ok profile -> assert profile.following
          | Error _ -> Stdlib.failwith "follow failed");
         let%bind after_follow =
           Users.profile ~database ~viewer_id:(Some bob.id) ~username:alice.username
         in
         assert_profile_following true after_follow;
         let%bind anonymous =
           Users.profile ~database ~viewer_id:None ~username:alice.username
         in
         assert_profile_following false anonymous;
         let%bind self_follow =
           Users.follow ~database ~follower_id:alice.id ~username:alice.username
         in
         assert (Poly.equal self_follow (Error `Cannot_follow_self));
         let%bind alice_article =
           Articles.create ~database ~author_id:alice.id (article_input "Typed OCaml")
         in
         let alice_article = created_article alice_article in
         let%bind bob_article =
           Articles.create ~database ~author_id:bob.id (article_input "Typed OCaml")
         in
         let bob_article = created_article bob_article in
         assert (
           String.equal (Domain.Article.Slug.to_string alice_article.slug) "typed-ocaml");
         assert (
           String.equal (Domain.Article.Slug.to_string bob_article.slug) "typed-ocaml-2");
         let%bind renamed =
           Articles.update
             ~database
             ~author_id:bob.id
             ~slug:bob_article.slug
             { Domain.Article.empty_update with title = Some "Typed OCaml" }
         in
         let renamed =
           match renamed with
           | Ok article -> article
           | Error _ -> Stdlib.failwith "slug retry on update failed"
         in
         assert (String.equal (Domain.Article.Slug.to_string renamed.slug) "typed-ocaml-2");
         let%bind forbidden_update =
           Articles.update
             ~database
             ~author_id:bob.id
             ~slug:alice_article.slug
             { Domain.Article.empty_update with title = Some "Stolen title" }
         in
         assert (Poly.equal forbidden_update (Error `Forbidden));
         let%bind forbidden_delete =
           Articles.delete ~database ~author_id:bob.id ~slug:alice_article.slug
         in
         assert (Poly.equal forbidden_delete (Error `Forbidden));
         let%bind favorite =
           Articles.favorite ~database ~user_id:bob.id ~slug:alice_article.slug
         in
         (match favorite with
          | Ok article ->
            assert article.favorited;
            assert (Int.equal article.favorites_count 1)
          | Error _ -> Stdlib.failwith "favorite failed");
         let%bind found =
           Articles.find ~database ~viewer_id:(Some bob.id) ~slug:alice_article.slug
         in
         (match found with
          | Ok (Some article) ->
            assert article.favorited;
            assert (Int.equal article.favorites_count 1);
            assert article.author.following;
            assert (
              List.equal
                Domain.Article.Tag.equal
                article.tag_list
                [ Domain.Article.Tag.of_string_exn "ocaml"
                ; Domain.Article.Tag.of_string_exn "typed-sql"
                ])
          | Ok None -> Stdlib.failwith "article disappeared after forbidden mutations"
          | Error error -> fail_persistence error);
         let%bind feed =
           Articles.feed ~database ~viewer_id:bob.id ~page:Domain.Page.default
         in
         (match feed with
          | Ok page ->
            assert (Int.equal page.count 1);
            assert (Int.equal (List.length page.articles) 1)
          | Error error -> fail_persistence error);
         let%bind comment =
           Comments.create
             ~database
             ~author_id:bob.id
             ~slug:alice_article.slug
             ~body:"Scoped deletion"
         in
         let comment = created_comment comment in
         let%bind forbidden_comment_delete =
           Comments.delete
             ~database
             ~author_id:alice.id
             ~slug:alice_article.slug
             ~comment_id:comment.id
         in
         assert (Poly.equal forbidden_comment_delete (Error `Forbidden));
         let%bind still_there =
           Comments.list ~database ~viewer_id:(Some alice.id) ~slug:alice_article.slug
         in
         (match still_there with
          | Ok comments -> assert (Int.equal (List.length comments) 1)
          | Error _ -> Stdlib.failwith "comment list failed");
         let%bind deleted =
           Comments.delete
             ~database
             ~author_id:bob.id
             ~slug:alice_article.slug
             ~comment_id:comment.id
         in
         assert (Result.is_ok deleted);
         let%bind unfollowed =
           Users.unfollow ~database ~follower_id:bob.id ~username:alice.username
         in
         (match unfollowed with
          | Ok profile -> assert (not profile.following)
          | Error _ -> Stdlib.failwith "unfollow failed");
         Lwt.return_unit)
      (fun () -> Database.disconnect database)
  ;;
end

let () =
  match Stdlib.Sys.argv with
  | [| _; url |] ->
    (match Uri.scheme (Uri.of_string url) with
     | Some "postgresql" ->
       let module Test = Make (Realworld_postgres.Database_postgres_lwt) in
       Lwt_main.run (Test.run url)
     | Some "sqlite" | Some "sqlite3" ->
       let module Test = Make (Realworld_sqlite.Database_sqlite_lwt) in
       Lwt_main.run (Test.run url)
     | _ -> Stdlib.failwith "Expected a SQLite or PostgreSQL URL")
  | _ -> Stdlib.failwith "Usage: repository_integration_test DATABASE_URL"
;;
