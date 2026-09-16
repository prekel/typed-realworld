open! Base
module Domain = Realworld_domain.Domain

let () =
  assert (Option.is_none (Domain.User.Id.of_int64 0L));
  assert (Option.is_none (Domain.Article.Id.of_int64 (-1L)));
  assert (Option.is_none (Domain.Comment.Id.of_string "not-an-id"));
  assert (Option.is_none (Domain.Comment.Id.of_string "0"));
  assert (Option.is_none (Domain.User.Username.of_string ""));
  assert (
    Domain.User.Username.of_string " Alice "
    |> Option.exists ~f:(fun username ->
      String.equal (Domain.User.Username.to_string username) "alice"));
  assert (Option.is_none (Domain.Article.Slug.of_string "invalid slug"));
  assert (
    Domain.Article.Slug.of_string "valid-slug"
    |> Option.exists ~f:(fun slug ->
      String.equal (Domain.Article.Slug.to_string slug) "valid-slug"));
  assert (Option.is_none (Domain.Article.Tag.of_string "  "));
  assert (
    Domain.Article.Tag.of_string " ocaml "
    |> Option.exists ~f:(fun tag ->
      String.equal (Domain.Article.Tag.to_string tag) "ocaml"));
  assert (Option.is_none (Domain.Page.Limit.of_int (-1)));
  assert (Option.is_none (Domain.Page.Offset.of_string "invalid"));
  let page =
    Domain.Page.create
      ~limit:(Domain.Page.Limit.of_int 10 |> Option.value_exn)
      ~offset:(Domain.Page.Offset.of_int 30 |> Option.value_exn)
      ()
  in
  assert (Int.equal (Domain.Page.limit page) 10);
  assert (Int.equal (Domain.Page.offset page) 30);
  let user_id = Domain.User.Id.of_int64_exn 42L in
  let article_id = Domain.Article.Id.of_int64_exn 42L in
  let comment_id = Domain.Comment.Id.of_int64_exn 42L in
  assert (Int64.equal (Domain.User.Id.to_int64 user_id) 42L);
  assert (Int64.equal (Domain.Article.Id.to_int64 article_id) 42L);
  assert (String.equal (Domain.Comment.Id.to_string comment_id) "42");
  assert (
    Domain.Comment.Id.of_string "42"
    |> Option.exists ~f:(Domain.Comment.Id.equal comment_id));
  assert (
    Option.equal
      String.equal
      (Domain.Patch.apply Domain.Patch.Keep ~current:(Some "before"))
      (Some "before"));
  assert (
    Option.equal
      String.equal
      (Domain.Patch.apply (Domain.Patch.Set "after") ~current:(Some "before"))
      (Some "after"));
  assert (Option.is_none (Domain.Patch.apply Domain.Patch.Clear ~current:(Some "before")))
;;
