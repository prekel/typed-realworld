open! Base
open Lwt.Let_syntax
module Application = Realworld_application
module Domain = Realworld_domain.Domain

let persistence message = Application.Persistence_error.of_string message

module Database = struct
  type 'a io = 'a Lwt.t
  type connection = unit
  type t = unit

  let connections = ref 0
  let transactions = ref 0
  let commits = ref 0
  let rollbacks = ref 0

  let reset () =
    connections := 0;
    transactions := 0;
    commits := 0;
    rollbacks := 0
  ;;

  let with_connection () ~on_error:_ ~f =
    Int.incr connections;
    f ~conn:()
  ;;

  let transaction () ~on_error:_ ~f =
    Int.incr transactions;
    let%map result = f ~conn:() in
    (match result with
     | Ok _ -> Int.incr commits
     | Error _ -> Int.incr rollbacks);
    result
  ;;
end

let now =
  Ptime.of_rfc3339 "2026-09-23T12:34:56Z" |> Result.ok |> Option.value_exn
  |> fun (value, _, _) -> value
;;

let user ?(id = 1L) ?(email = "alice@example.test") ?(username = "alice") () =
  Domain.User.
    { id = Id.of_int64_exn id
    ; email = Email.of_string_exn email
    ; username = Username.of_string_exn username
    ; bio = None
    ; image = None
    }
;;

let profile ?(username = "alice") ?(following = false) () =
  Domain.Profile.
    { username = Domain.User.Username.of_string_exn username
    ; bio = None
    ; image = None
    ; following
    }
;;

let article ?(slug = "typed-ocaml") ?(title = "Typed OCaml") () =
  Domain.Article.
    { id = Id.of_int64_exn 1L
    ; slug = Slug.of_string_exn slug
    ; title
    ; description = "A useful description"
    ; body = "A useful article body"
    ; tag_list = [ Tag.of_string_exn "ocaml" ]
    ; created_at = now
    ; updated_at = now
    ; favorited = false
    ; favorites_count = 0
    ; author = profile ()
    }
;;

module Hasher = struct
  let hash_calls = ref 0
  let verify_calls = ref 0

  let reset () =
    hash_calls := 0;
    verify_calls := 0
  ;;

  let hash password =
    Int.incr hash_calls;
    Ok ("hash:" ^ password)
  ;;

  let verify ~encoded password =
    Int.incr verify_calls;
    String.equal encoded ("hash:" ^ password)
  ;;
end

module Users = struct
  type 'a io = 'a Lwt.t
  type connection = unit

  let credentials = ref None
  let create_result = ref (Ok (user ()))
  let update_result = ref (Ok (user ()))
  let follow_result = ref (Ok (profile ~following:true ()))
  let unfollow_result = ref (Ok (profile ()))
  let create_calls = ref 0
  let update_calls = ref 0

  let reset () =
    credentials := None;
    create_result := Ok (user ());
    update_result := Ok (user ());
    follow_result := Ok (profile ~following:true ());
    unfollow_result := Ok (profile ());
    create_calls := 0;
    update_calls := 0
  ;;

  let create ~conn:() ~email:_ ~username:_ ~password_hash:_ =
    Int.incr create_calls;
    Lwt.return !create_result
  ;;

  let find_by_id ~conn:() _ = Lwt.return (Ok (Some (user ())))
  let find_credentials_by_email ~conn:() _ = Lwt.return (Ok !credentials)

  let update ~conn:() ~id:_ _ =
    Int.incr update_calls;
    Lwt.return !update_result
  ;;

  let profile ~conn:() ~viewer_id:_ ~username:_ = Lwt.return (Ok (Some (profile ())))
  let follow ~conn:() ~follower_id:_ ~username:_ = Lwt.return !follow_result
  let unfollow ~conn:() ~follower_id:_ ~username:_ = Lwt.return !unfollow_result
end

module User_service = Application.User_service.Make (Database) (Users) (Hasher)

module Clock = struct
  let calls = ref 0

  let now () =
    Int.incr calls;
    now
  ;;
end

module Articles = struct
  type 'a io = 'a Lwt.t
  type connection = unit

  type create_behavior =
    | Succeed_after of int
    | Always_conflict
    | Fail

  let create_behavior = ref (Succeed_after 0)
  let create_calls = ref 0
  let seen_slugs = ref []
  let seen_times = ref []
  let seen_update_times = ref []
  let update_result = ref (Ok (article ()))
  let delete_result = ref (Ok ())

  let reset () =
    create_behavior := Succeed_after 0;
    create_calls := 0;
    seen_slugs := [];
    seen_times := [];
    seen_update_times := [];
    update_result := Ok (article ());
    delete_result := Ok ();
    Clock.calls := 0
  ;;

  let list ~conn:() ~viewer_id:_ ~filters:_ ~page:_ =
    Lwt.return (Ok Application.Article_repository.{ articles = []; count = 0 })
  ;;

  let feed ~conn:() ~viewer_id:_ ~page:_ =
    Lwt.return (Ok Application.Article_repository.{ articles = []; count = 0 })
  ;;

  let find ~conn:() ~viewer_id:_ ~slug:_ = Lwt.return (Ok None)

  let create ~conn:() ~author_id:_ ~slug ~now (article_input : Domain.Article.create) =
    Int.incr create_calls;
    seen_slugs := Domain.Article.Slug.to_string slug :: !seen_slugs;
    seen_times := now :: !seen_times;
    match !create_behavior with
    | Succeed_after conflicts when !create_calls <= conflicts ->
      Lwt.return (Error `Slug_taken)
    | Succeed_after _ ->
      Lwt.return
        (Ok
           (article
              ~slug:(Domain.Article.Slug.to_string slug)
              ~title:article_input.title
              ()))
    | Always_conflict -> Lwt.return (Error `Slug_taken)
    | Fail -> Lwt.return (Error (`Persistence (persistence "tag sync failed")))
  ;;

  let update ~conn:() ~author_id:_ ~slug:_ ~new_slug:_ ~now _ =
    seen_update_times := now :: !seen_update_times;
    Lwt.return !update_result
  ;;

  let delete ~conn:() ~author_id:_ ~slug:_ = Lwt.return !delete_result
  let favorite ~conn:() ~user_id:_ ~slug:_ = Lwt.return (Ok (article ()))
  let unfavorite ~conn:() ~user_id:_ ~slug:_ = Lwt.return (Ok (article ()))
  let tags ~conn:() = Lwt.return (Ok [ "ocaml" ])
end

module Article_service = Application.Article_service.Make (Database) (Articles) (Clock)

module Comments = struct
  type 'a io = 'a Lwt.t
  type connection = unit

  let delete_result = ref (Ok ())
  let list ~conn:() ~viewer_id:_ ~slug:_ = Lwt.return (Ok [])
  let create ~conn:() ~author_id:_ ~slug:_ ~body:_ ~now:_ = assert false
  let delete ~conn:() ~author_id:_ ~slug:_ ~comment_id:_ = Lwt.return !delete_result
end

module Comment_service = Application.Comment_service.Make (Database) (Comments) (Clock)

let run value = Lwt_main.run value

let reset () =
  Database.reset ();
  Hasher.reset ();
  Users.reset ();
  Articles.reset ();
  Comments.delete_result := Ok ()
;;

let valid_registration : Domain.User.registration =
  { email = "Alice@Example.Test"; username = "Alice"; password = "password123" }
;;

let valid_article : Domain.Article.create =
  { title = "Typed OCaml"
  ; description = "A useful description"
  ; body = "A useful article body"
  ; tag_list = [ Domain.Article.Tag.of_string_exn "ocaml" ]
  }
;;

let test_validation_before_effects () =
  reset ();
  let invalid_registration = { valid_registration with password = "short" } in
  (match run (User_service.register ~database:() invalid_registration) with
   | Error (`Validation _) -> ()
   | _ -> assert false);
  assert (Int.equal !Hasher.hash_calls 0);
  assert (Int.equal !Database.transactions 0);
  assert (Int.equal !Users.create_calls 0);
  let invalid_update = { Domain.User.empty_update with password = Some "short" } in
  (match
     run
       (User_service.update
          ~database:()
          ~user_id:(Domain.User.Id.of_int64_exn 1L)
          invalid_update)
   with
   | Error (`Validation _) -> ()
   | _ -> assert false);
  assert (Int.equal !Hasher.hash_calls 0);
  assert (Int.equal !Users.update_calls 0)
;;

let test_registration_and_login () =
  reset ();
  let registered = run (User_service.register ~database:() valid_registration) in
  assert (Result.is_ok registered);
  assert (Int.equal !Hasher.hash_calls 1);
  assert (Int.equal !Database.commits 1);
  let missing =
    run (User_service.login ~database:() ~email:"missing@example.test" ~password:"wrong")
  in
  Users.credentials
  := Some
       Application.User_repository.{ user = user (); password_hash = "hash:password123" };
  let wrong =
    run (User_service.login ~database:() ~email:"alice@example.test" ~password:"wrong")
  in
  assert (Poly.equal missing (Error `Invalid_credentials));
  assert (Poly.equal wrong (Error `Invalid_credentials));
  let correct =
    run
      (User_service.login
         ~database:()
         ~email:"ALICE@EXAMPLE.TEST"
         ~password:"password123")
  in
  assert (Result.is_ok correct)
;;

let test_slug_retry_and_clock () =
  reset ();
  Articles.create_behavior := Succeed_after 2;
  let created =
    run
      (Article_service.create
         ~database:()
         ~author_id:(Domain.User.Id.of_int64_exn 1L)
         valid_article)
  in
  let created =
    match created with
    | Ok article -> article
    | Error _ -> assert false
  in
  assert (String.equal (Domain.Article.Slug.to_string created.slug) "typed-ocaml-3");
  assert (
    List.equal
      String.equal
      (List.rev !Articles.seen_slugs)
      [ "typed-ocaml"; "typed-ocaml-2"; "typed-ocaml-3" ]);
  assert (List.for_all !Articles.seen_times ~f:(Ptime.equal now));
  assert (Int.equal !Clock.calls 1);
  assert (Int.equal !Database.transactions 3);
  assert (Int.equal !Database.rollbacks 2);
  assert (Int.equal !Database.commits 1)
;;

let test_retry_bound_and_rollback () =
  reset ();
  Articles.create_behavior := Always_conflict;
  (match
     run
       (Article_service.create
          ~database:()
          ~author_id:(Domain.User.Id.of_int64_exn 1L)
          valid_article)
   with
   | Error (`Persistence _) -> ()
   | _ -> assert false);
  assert (Int.equal !Articles.create_calls 1000);
  assert (Int.equal !Database.transactions 1000);
  assert (Int.equal !Database.rollbacks 1000);
  reset ();
  Articles.create_behavior := Fail;
  (match
     run
       (Article_service.create
          ~database:()
          ~author_id:(Domain.User.Id.of_int64_exn 1L)
          valid_article)
   with
   | Error (`Persistence _) -> ()
   | _ -> assert false);
  assert (Int.equal !Database.rollbacks 1);
  assert (Int.equal !Database.commits 0)
;;

let test_application_error_mapping () =
  reset ();
  Users.follow_result := Error `Cannot_follow_self;
  let username = Domain.User.Username.of_string_exn "alice" in
  let user_id = Domain.User.Id.of_int64_exn 1L in
  assert (
    Poly.equal
      (run (User_service.follow ~database:() ~follower_id:user_id ~username))
      (Error `Cannot_follow_self));
  Articles.update_result := Error `Forbidden;
  let slug = Domain.Article.Slug.of_string_exn "typed-ocaml" in
  assert (
    Poly.equal
      (run
         (Article_service.update
            ~database:()
            ~author_id:user_id
            ~slug
            Domain.Article.empty_update))
      (Error `Forbidden));
  assert (List.equal Ptime.equal !Articles.seen_update_times [ now ]);
  assert (Int.equal !Clock.calls 1);
  Articles.delete_result := Error `Not_found;
  assert (
    Poly.equal
      (run (Article_service.delete ~database:() ~author_id:user_id ~slug))
      (Error `Not_found));
  let comment_id = Domain.Comment.Id.of_int64_exn 1L in
  Comments.delete_result := Error `Article_not_found;
  assert (
    Poly.equal
      (run (Comment_service.delete ~database:() ~author_id:user_id ~slug ~comment_id))
      (Error `Article_not_found));
  Comments.delete_result := Error `Comment_not_found;
  assert (
    Poly.equal
      (run (Comment_service.delete ~database:() ~author_id:user_id ~slug ~comment_id))
      (Error `Comment_not_found));
  Comments.delete_result := Error `Forbidden;
  assert (
    Poly.equal
      (run (Comment_service.delete ~database:() ~author_id:user_id ~slug ~comment_id))
      (Error `Forbidden));
  assert (Int.equal !Database.rollbacks 6)
;;

let () =
  test_validation_before_effects ();
  test_registration_and_login ();
  test_slug_retry_and_clock ();
  test_retry_bound_and_rollback ();
  test_application_error_mapping ()
;;
