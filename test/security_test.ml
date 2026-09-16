open! Base
module Domain = Realworld_domain.Domain
module Password = Realworld_security.Password_scrypt
module Jwt = Realworld_security.Jwt_hs256

let () =
  Mirage_crypto_rng_unix.use_default ();
  let encoded = Password.hash "password123" |> Result.ok_or_failwith in
  assert (Password.verify ~encoded "password123");
  assert (not (Password.verify ~encoded "wrong-password"));
  let module Token = (val Jwt.create ~secret:"test-secret") in
  let user_id = Domain.User.Id.of_int64_exn 42L in
  let token = Token.issue ~user_id in
  assert (
    Option.value_map (Token.verify token) ~default:false ~f:(Domain.User.Id.equal user_id));
  assert (Option.is_none (Token.verify (token ^ "x")));
  assert (
    Domain.Article.slugify "Hello, OCaml world!"
    |> Option.exists ~f:(fun slug ->
      String.equal (Domain.Article.Slug.to_string slug) "hello-ocaml-world"))
;;
